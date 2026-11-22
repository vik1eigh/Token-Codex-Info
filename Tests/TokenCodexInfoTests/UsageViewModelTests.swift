import Combine
import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class UsageViewModelTests: XCTestCase {
    @MainActor
    func testInitialStateNeverShowsFullAllowance() {
        let model = UsageViewModel(provider: ImmediateProvider())
        XCTAssertEqual(model.snapshot.issue, .checking)
        XCTAssertEqual(model.menuBarTitleParts.stringValue, "Codex · Checking")
        XCTAssertTrue(model.usageRows.isEmpty)
    }

    @MainActor
    func testChangingFolderRejectsAnOldReadAndLoadsTheNewFolder() async throws {
        let suite = "TokenCodexInfoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.codexHomePath = "first-folder"
        let firstReadStarted = expectation(description: "First folder read started")
        let newFolderLoaded = expectation(description: "New folder loaded")
        let provider = DelayedProvider(started: firstReadStarted)
        defer { provider.release.signal() }
        let model = UsageViewModel(provider: provider)
        var seenOldResult = false
        let subscription = model.$snapshot.sink { snapshot in
            if snapshot.hasData && snapshot.remainingPercent == 80 { seenOldResult = true }
            if snapshot.hasData && snapshot.remainingPercent == 20 { newFolderLoaded.fulfill() }
        }
        model.start(settings: settings)
        await fulfillment(of: [firstReadStarted], timeout: 3)
        settings.codexHomePath = "second-folder"
        provider.release.signal()
        await fulfillment(of: [newFolderLoaded], timeout: 3)
        XCTAssertFalse(seenOldResult)
        XCTAssertEqual(model.snapshot.remainingPercent, 20)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testAccessFailureRemovesAPreviouslyReportedFullAllowance() async throws {
        let suite = "TokenCodexInfoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.codexHomePath = "readable"
        let reported = expectation(description: "Reported allowance loaded")
        let denied = expectation(description: "Access failure replaces the allowance")
        let model = UsageViewModel(provider: FolderSwitchProvider())
        let subscription = model.$snapshot.sink { snapshot in
            if snapshot.hasData { reported.fulfill() }
            if snapshot.issue == .accessDenied { denied.fulfill() }
        }
        model.start(settings: settings)
        await fulfillment(of: [reported], timeout: 3)
        settings.codexHomePath = "denied"
        await fulfillment(of: [denied], timeout: 3)
        XCTAssertEqual(model.menuBarTitleParts.stringValue, "Codex · No access")
        XCTAssertTrue(model.usageRows.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testSetupCompletionPersistsAndStartsIncomplete() throws {
        let suite = "TokenCodexInfoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.hasCompletedSetup)
        settings.completeSetup()
        XCTAssertTrue(SettingsStore(defaults: defaults).hasCompletedSetup)
    }
}

private struct FolderSwitchProvider: UsageProviding {
    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        if settings.codexHomePath == "readable" {
            return UsageSnapshot(usedTokens: 0, limitTokens: 100, resetAt: now.addingTimeInterval(3600), observedAt: now, source: .rateLimits)
        }
        return .empty(limitTokens: 100, now: now, issue: .accessDenied)
    }
}

private struct ImmediateProvider: UsageProviding {
    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        .empty(limitTokens: 100, now: now, issue: .accessDenied)
    }
}

private final class DelayedProvider: UsageProviding, @unchecked Sendable {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)

    init(started: XCTestExpectation) { self.started = started }

    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        if settings.codexHomePath == "first-folder" {
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
        }
        return UsageSnapshot(usedTokens: settings.codexHomePath == "first-folder" ? 20 : 80,
                             limitTokens: 100, resetAt: now.addingTimeInterval(3600),
                             observedAt: now, source: .rateLimits)
    }
}
