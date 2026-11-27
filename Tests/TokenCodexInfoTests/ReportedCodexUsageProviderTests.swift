import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class ReportedCodexUsageProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)

    private func withHome(_ body: (UsageSettings) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(UsageSettings(codexHomePath: home.path, fiveHourTokenLimit: 1, weeklyTokenLimit: 1, refreshIntervalSeconds: 60))
    }

    func testLiveCodexBucketWinsOverLegacyBucketAndLocalTokens() throws {
        try withHome { settings in
            let client = FixtureAccountClient(json: #"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":23600}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":624800}}}}"#)
            let snapshot = ReportedCodexUsageProvider(client: client, local: MustNotReadLocalProvider()).loadUsage(settings: settings, now: now)
            XCTAssertEqual(snapshot.source, .liveRateLimits)
            XCTAssertEqual(snapshot.menuBarWindow.remainingPercent, 98)
            XCTAssertEqual(snapshot.menuBarWindow.resetAt, Date(timeIntervalSince1970: 624800))
            XCTAssertEqual(snapshot.menuBarWindowName, "weekly")
            XCTAssertFalse(snapshot.menuBarTitleParts(now: now).stringValue.contains("≈"))
        }
    }

    func testLiveFiveHourLimitsIgnoreLegacyTokenLimitSettings() throws {
        try withHome { settings in
            let client = FixtureAccountClient(json: #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":17,"windowDurationMins":300,"resetsAt":23600}}}"#)
            let snapshot = ReportedCodexUsageProvider(client: client).loadUsage(settings: settings, now: now)
            XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "83% · 1:00")
        }
    }

    func testLiveFailureDoesNotSubstituteAStaleLocalSnapshot() throws {
        try withHome { settings in
            let provider = ReportedCodexUsageProvider(client: FailedAccountClient(error: .requestFailed), local: MustNotReadLocalProvider())
            let snapshot = provider.loadUsage(settings: settings, now: now)
            XCTAssertEqual(snapshot.issue, .liveRequestFailed)
            XCTAssertFalse(snapshot.hasData)
            XCTAssertFalse(snapshot.menuBarTitleParts(now: now).stringValue.contains("%"))
        }
    }

    func testUnavailableCodexCanUseReportedLocalLimits() throws {
        try withHome { settings in
            let provider = ReportedCodexUsageProvider(client: FailedAccountClient(error: .executableNotFound), local: ReportedLocalProvider())
            let snapshot = provider.loadUsage(settings: settings, now: now)
            XCTAssertEqual(snapshot.source, .rateLimits)
            XCTAssertEqual(snapshot.menuBarWindow.remainingPercent, 80)
        }
    }

    func testMissingEmptyExpiredAndUnrelatedLiveWindowsNeverShowZeroOrFullAllowance() throws {
        let fixtures = [
            #"{}"#,
            #"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":23600}}}"#,
            #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":19999}}}"#,
            #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":-1,"windowDurationMins":300,"resetsAt":23600}}}"#
        ]
        for json in fixtures {
            try withHome { settings in
                let snapshot = ReportedCodexUsageProvider(client: FixtureAccountClient(json: json), local: MustNotReadLocalProvider()).loadUsage(settings: settings, now: now)
                XCTAssertFalse(snapshot.hasData)
                XCTAssertFalse(snapshot.menuBarTitleParts(now: now).stringValue.contains("%"))
            }
        }
    }

    func testRealInstalledCodexReturnsReportedLimits() throws {
        guard ProcessInfo.processInfo.environment["TOKEN_CODEX_RUN_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in account integration test")
        }
        let settings = UsageSettings(codexHomePath: "~/.codex", fiveHourTokenLimit: 1, refreshIntervalSeconds: 60)
        let snapshot = ReportedCodexUsageProvider().loadUsage(settings: settings, now: Date())
        XCTAssertEqual(snapshot.source, .liveRateLimits)
        XCTAssertTrue(snapshot.hasData)
        XCTAssertFalse(snapshot.menuBarTitleParts(now: Date()).stringValue.contains("≈"))
        print("Live account check: \(snapshot.menuBarWindow.remainingPercent)% remaining (\(snapshot.menuBarWindowName))")
    }
}

private struct FixtureAccountClient: CodexAccountReading {
    var json: String
    func readRateLimits(codexHome: URL) throws -> Data { Data(json.utf8) }
}

private struct FailedAccountClient: CodexAccountReading {
    var error: CodexAccountReadError
    func readRateLimits(codexHome: URL) throws -> Data { throw error }
}

private struct MustNotReadLocalProvider: UsageProviding {
    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        XCTFail("Live account results must not be replaced by local activity or stale snapshots")
        return .empty(limitTokens: 100, now: now)
    }
}

private struct ReportedLocalProvider: UsageProviding {
    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        UsageSnapshot(usedTokens: 20, limitTokens: 100, resetAt: now.addingTimeInterval(3600), observedAt: now, source: .rateLimits)
    }
}
