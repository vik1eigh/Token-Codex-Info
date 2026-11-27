import XCTest
@testable import TokenCodexInfoCore

final class UsageSnapshotTests: XCTestCase {
    func testPercentCalculationAndRemainingClamp() {
        let snapshot = UsageSnapshot(
            usedTokens: 300,
            limitTokens: 200,
            resetAt: nil,
            observedAt: Date(timeIntervalSince1970: 0),
            source: .rateLimits
        )

        XCTAssertEqual(snapshot.rawPercent, 150)
        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertEqual(snapshot.remainingPercent, 0)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 0)
    }

    func testEmptySnapshot() {
        let snapshot = UsageSnapshot.empty(limitTokens: 244_800, weeklyLimitTokens: 1_713_600, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.usedTokens, 0)
        XCTAssertEqual(snapshot.rawPercent, 0)
        XCTAssertEqual(snapshot.remainingFraction, 1)
        XCTAssertEqual(snapshot.remainingPercent, 100)
        XCTAssertEqual(snapshot.weekly.usedTokens, 0)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 100)
        XCTAssertEqual(snapshot.secondsUntilReset(from: Date(timeIntervalSince1970: 0)), 0)
        XCTAssertFalse(snapshot.hasData)
        XCTAssertFalse(snapshot.fiveHour.isAvailable)
        XCTAssertFalse(snapshot.weekly.isAvailable)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · No limits")
        XCTAssertFalse(snapshot.menuBarAccessibilityTitle(now: Date()).contains("100%"))
    }

    func testLegacyTokenEstimatesAreNeverDisplayedAsAccountLimits() {
        let now = Date()
        for source in [UsageDataSource.logs, .threadsEstimate] {
            for tokens in [0, 9000000] {
                let snapshot = UsageSnapshot(usedTokens: tokens, limitTokens: 100, resetAt: now.addingTimeInterval(3600), observedAt: now, source: source)
                XCTAssertFalse(snapshot.hasData)
                XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "Codex · No limits")
                XCTAssertFalse(snapshot.menuBarAccessibilityTitle(now: now).contains("%"))
            }
        }
    }

    func testReportedUnusedWindowCanStillShowFullAllowance() {
        let now = Date()
        let snapshot = UsageSnapshot(usedTokens: 0, limitTokens: 100, resetAt: now.addingTimeInterval(3600), observedAt: now, source: .rateLimits)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "100% · 1:00")
        XCTAssertEqual(snapshot.statusTitle, "Reported limits")
    }

    func testUnavailableStatesNeverShowAPercentage() {
        let cases: [(CodexDataIssue, String)] = [
            (.checking, "Checking"), (.folderMissing, "Setup"), (.notDirectory, "Setup"),
            (.accessDenied, "No access"), (.noUsageData, "No limits"), (.readFailed, "Read error"),
            (.codexUnavailable, "Setup"), (.liveRequestFailed, "Offline")
        ]
        for (issue, label) in cases {
            let snapshot = UsageSnapshot.empty(limitTokens: 100, now: Date(), issue: issue)
            XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · \(label)")
            XCTAssertFalse(snapshot.menuBarAccessibilityTitle(now: Date()).contains("%"))
        }
    }

    func testRemainingPercentCountsDownFromFullLimit() {
        let snapshot = UsageSnapshot(
            usedTokens: 50,
            limitTokens: 200,
            resetAt: nil,
            observedAt: Date(timeIntervalSince1970: 0),
            source: .rateLimits
        )

        XCTAssertEqual(snapshot.rawPercent, 25)
        XCTAssertEqual(snapshot.remainingPercent, 75)
    }

    func testWeeklyPercentCanDifferFromFiveHourPercent() {
        let snapshot = UsageSnapshot(
            usedTokens: 50,
            limitTokens: 200,
            resetAt: nil,
            weeklyUsedTokens: 300,
            weeklyLimitTokens: 1_000,
            weeklyResetAt: nil,
            observedAt: Date(timeIntervalSince1970: 0),
            source: .rateLimits
        )

        XCTAssertEqual(snapshot.remainingPercent, 75)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 70)
    }

    func testMenuBarFallsBackToWeeklyWhenFiveHourIsUnavailable() {
        let now = Date(timeIntervalSince1970: 20_000)
        let snapshot = UsageSnapshot(
            fiveHour: .empty(limitTokens: 100, isAvailable: false),
            weekly: UsageWindowSnapshot(
                usedTokens: 12,
                limitTokens: 100,
                resetAt: Date(timeIntervalSince1970: 624_800)
            ),
            observedAt: now,
            source: .rateLimits
        )

        XCTAssertEqual(snapshot.menuBarWindow, snapshot.weekly)
        XCTAssertEqual(snapshot.menuBarWindowName, "weekly")
        XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "88% · 8 Jan")
        XCTAssertEqual(snapshot.menuBarAccessibilityTitle(now: now), "88% of weekly limit remaining, resets on 8 Jan")
    }
}
