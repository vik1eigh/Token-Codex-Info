import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class CodexUsageProviderTests: XCTestCase {
    private func settings(_ home: TemporaryCodexHome) -> UsageSettings {
        UsageSettings(codexHomePath: home.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60)
    }

    func testMissingFolderExplainsSetupWithoutClaimingFullAllowance() throws {
        let home = try TemporaryCodexHome()
        var settings = settings(home)
        settings.codexHomePath = home.url.appendingPathComponent("missing").path
        let snapshot = CodexUsageProvider().loadUsage(settings: settings)
        XCTAssertEqual(snapshot.issue, .folderMissing)
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · Setup")
    }

    func testEmptyPathDoesNotReadTheCurrentWorkingDirectory() throws {
        let home = try TemporaryCodexHome()
        var settings = settings(home)
        settings.codexHomePath = "   "
        let snapshot = CodexUsageProvider().loadUsage(settings: settings)
        XCTAssertEqual(snapshot.issue, .folderMissing)
        XCTAssertFalse(snapshot.hasData)
    }

    func testSelectingAFileExplainsThatAFolderIsRequired() throws {
        let home = try TemporaryCodexHome()
        let file = home.url.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        var settings = settings(home)
        settings.codexHomePath = file.path
        let snapshot = CodexUsageProvider().loadUsage(settings: settings)
        XCTAssertEqual(snapshot.issue, .notDirectory)
    }

    func testDeniedFolderIsDifferentFromNoData() throws {
        let home = try TemporaryCodexHome()
        let provider = CodexUsageProvider(sqlite: MustNotReadSQLite(), folderChecker: DeniedFolderChecker())
        let snapshot = provider.loadUsage(settings: settings(home))
        XCTAssertEqual(snapshot.issue, .accessDenied)
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · No access")
    }

    func testAccessibleEmptyFolderReportsNoData() throws {
        let home = try TemporaryCodexHome()
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home))
        XCTAssertEqual(snapshot.issue, .noUsageData)
        XCTAssertFalse(snapshot.hasData)
    }

    func testUnreadableSessionReportsNoAccess() throws {
        let home = try TemporaryCodexHome()
        try home.createSessionLog(lines: ["{}"])
        let file = home.url.appendingPathComponent("sessions/1970/01/01/rollout-test.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home))
        XCTAssertEqual(snapshot.issue, .accessDenied)
        XCTAssertFalse(snapshot.hasData)
    }

    func testCorruptDatabaseReportsReadErrorWithoutExposingRawError() throws {
        let home = try TemporaryCodexHome()
        try Data("invalid database".utf8).write(to: home.url.appendingPathComponent("logs_2.sqlite"))
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home))
        XCTAssertEqual(snapshot.issue, .readFailed)
        XCTAssertFalse(snapshot.statusMessage.contains(home.url.path))
    }

    func testEmptyThreadDatabaseDoesNotInventUsage() throws {
        let home = try TemporaryCodexHome()
        try home.createStateDatabase(rows: [])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home))
        XCTAssertEqual(snapshot.issue, .noUsageData)
        XCTAssertFalse(snapshot.hasData)
    }

    func testAllExpiredWindowsDoNotBecomeReportedFullAllowance() throws {
        let home = try TemporaryCodexHome()
        try home.createSessionLog(lines: [
            #"{"payload":{"rate_limits":{"primary":{"used_percent":39,"window_minutes":300,"resets_at":19999},"secondary":{"used_percent":31,"window_minutes":10080,"resets_at":19999}}}}"#
        ])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 20_000))
        XCTAssertEqual(snapshot.issue, .noUsageData)
        XCTAssertFalse(snapshot.hasData)
    }

    func testZeroTokensDoNotImplyAFullAccountAllowance() throws {
        let home = try TemporaryCodexHome()
        try home.createLogsDatabase(rows: [(19_000, "post sampling token usage turn_id=turn-a total_usage_tokens=0")])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 20_000))
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · No limits")
    }

    func testOlderLogActivityCannotDetermineAccountAllowance() throws {
        let home = try TemporaryCodexHome()
        try home.createLogsDatabase(rows: [(80_000, "post sampling token usage turn_id=older-turn total_usage_tokens=400")])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 100_000))
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.source, .unavailable)
        XCTAssertFalse(snapshot.menuBarTitleParts(now: Date()).stringValue.contains("%"))
    }

    func testLargeHistoricalThreadCountsDoNotImplyAnExhaustedQuota() throws {
        let home = try TemporaryCodexHome()
        try home.createStateDatabase(rows: [(80_000, 0, 9_000_000)])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 100_000))
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: Date()).stringValue, "Codex · No limits")
        XCTAssertNil(snapshot.resetAt)
        XCTAssertNil(snapshot.weekly.resetAt)
    }

    func testUsesPayloadCodexSessionRateLimitsBeforeSQLiteEstimates() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (19_000, "post sampling token usage turn_id=turn-a total_usage_tokens=190")
        ])
        try codexHome.createSessionLog(lines: [
            #"{"timestamp":"1970-01-01T05:33:20.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":17.0,"window_minutes":300,"resets_at":23600},"secondary":{"used_percent":8.0,"window_minutes":10080,"resets_at":624800},"credits":null,"plan_type":"prolite"}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":42.0,"window_minutes":300,"resets_at":23600},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":624800},"credits":null,"plan_type":"prolite"}}"#
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertEqual(snapshot.usedTokens, 17)
        XCTAssertEqual(snapshot.remainingPercent, 83)
        XCTAssertEqual(snapshot.resetAt, Date(timeIntervalSince1970: 23_600))
        XCTAssertGreaterThan(snapshot.secondsUntilReset(from: now), 0)
        XCTAssertEqual(snapshot.weekly.usedTokens, 8)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 92)
        XCTAssertEqual(snapshot.weekly.resetAt, Date(timeIntervalSince1970: 624_800))
    }

    func testUsesPayloadWeeklyOnlySessionRateLimits() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (19_000, "post sampling token usage turn_id=turn-a total_usage_tokens=190")
        ])
        try codexHome.createSessionLog(lines: [
            #"{"timestamp":"1970-01-01T05:33:20.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":10080,"resets_at":624800},"secondary":null,"credits":null,"plan_type":"prolite"}}}"#
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertFalse(snapshot.fiveHour.isAvailable)
        XCTAssertTrue(snapshot.weekly.isAvailable)
        XCTAssertEqual(snapshot.weekly.usedTokens, 12)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 88)
        XCTAssertEqual(snapshot.weekly.resetAt, Date(timeIntervalSince1970: 624_800))
        XCTAssertEqual(snapshot.menuBarWindow, snapshot.weekly)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "88% · 8 Jan")
    }

    func testExpiredFiveHourSnapshotUsesValidWeeklyWindowWithoutInventingReset() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (19_000, "post sampling token usage turn_id=turn-a total_usage_tokens=190")
        ])
        try codexHome.createSessionLog(lines: [
            #"{"timestamp":"1970-01-01T05:33:20.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":39.0,"window_minutes":300,"resets_at":19999},"secondary":{"used_percent":31.0,"window_minutes":10080,"resets_at":624800},"credits":null,"plan_type":"prolite"}}}"#
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertFalse(snapshot.fiveHour.isAvailable)
        XCTAssertTrue(snapshot.weekly.isAvailable)
        XCTAssertEqual(snapshot.menuBarWindow.remainingPercent, 69)
        XCTAssertEqual(snapshot.menuBarWindow.resetAt, Date(timeIntervalSince1970: 624_800))
    }

    func testUsesCodexSessionRateLimitsBeforeSQLiteEstimates() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (19_000, "post sampling token usage turn_id=turn-a total_usage_tokens=190")
        ])
        try codexHome.createSessionLog(lines: [
            #"{"timestamp":"1970-01-01T05:33:19.000Z","type":"response_item","payload":{"type":"function_call_output","output":"embedded {\"rate_limits\":{\"primary\":{\"used_percent\":99,\"resets_at\":99999}}}"}}"#,
            #"{"timestamp":"1970-01-01T05:33:20.000Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex","primary":{"used_percent":42.0,"window_minutes":300,"resets_at":23600},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":624800},"credits":null,"plan_type":"prolite"}}"#
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertEqual(snapshot.usedTokens, 42)
        XCTAssertEqual(snapshot.remainingPercent, 58)
        XCTAssertEqual(snapshot.resetAt, Date(timeIntervalSince1970: 23_600))
        XCTAssertEqual(snapshot.weekly.usedTokens, 6)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 94)
        XCTAssertEqual(snapshot.weekly.resetAt, Date(timeIntervalSince1970: 624_800))
    }

    func testUsesCodexRateLimitsBeforeTokenEstimates() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (10_000, "post sampling token usage turn_id=turn-a total_usage_tokens=190"),
            (19_500, #"ToolCall: apply_patch Received message {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"allowed":true,"limit_reached":false,"primary":{"used_percent":90,"window_minutes":300,"reset_after_seconds":3600,"reset_at":23600},"secondary":{"used_percent":90,"window_minutes":10080,"reset_after_seconds":604800,"reset_at":624800}},"credits":null}"#),
            (19_000, #"Received message {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"allowed":true,"limit_reached":false,"primary":{"used_percent":32,"window_minutes":300,"reset_after_seconds":3600,"reset_at":23600},"secondary":{"used_percent":5,"window_minutes":10080,"reset_after_seconds":604800,"reset_at":624800}},"credits":null}"#)
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertEqual(snapshot.usedTokens, 32)
        XCTAssertEqual(snapshot.remainingPercent, 68)
        XCTAssertEqual(snapshot.resetAt, Date(timeIntervalSince1970: 23_600))
        XCTAssertEqual(snapshot.weekly.usedTokens, 5)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 95)
        XCTAssertEqual(snapshot.weekly.resetAt, Date(timeIntervalSince1970: 624_800))
    }

    func testExpiredSQLiteFiveHourWindowKeepsReportedWeeklyData() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)

        try codexHome.createLogsDatabase(rows: [
            (10_000, "post sampling token usage turn_id=turn-a total_usage_tokens=100"),
            (19_000, #"Received message {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"allowed":true,"limit_reached":false,"primary":{"used_percent":32,"window_minutes":300,"reset_after_seconds":0,"reset_at":19999},"secondary":{"used_percent":5,"window_minutes":10080,"reset_after_seconds":604800,"reset_at":624800}},"credits":null}"#)
        ])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .rateLimits)
        XCTAssertFalse(snapshot.fiveHour.isAvailable)
        XCTAssertEqual(snapshot.menuBarWindow.remainingPercent, 95)
    }

    func testRecentTokenLogsDoNotBecomeAnAccountPercentage() throws {
        let home = try TemporaryCodexHome()
        try home.createLogsDatabase(rows: [(19_000, "post sampling token usage turn_id=recent-turn total_usage_tokens=9000000")])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 20_000))
        XCTAssertFalse(snapshot.hasData)
        XCTAssertFalse(snapshot.menuBarTitleParts(now: Date()).stringValue.contains("%"))
        XCTAssertNil(snapshot.resetAt)
    }

    func testReadableLogsWithNoRowsReportsNoDataInsteadOfFullAllowance() throws {
        let codexHome = try TemporaryCodexHome()
        let now = Date(timeIntervalSince1970: 20_000)
        try codexHome.createLogsDatabase(rows: [])

        let provider = CodexUsageProvider()
        let snapshot = provider.loadUsage(
            settings: UsageSettings(codexHomePath: codexHome.url.path, fiveHourTokenLimit: 200, weeklyTokenLimit: 2_000, refreshIntervalSeconds: 60),
            now: now
        )

        XCTAssertEqual(snapshot.source, .unavailable)
        XCTAssertEqual(snapshot.issue, .noUsageData)
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.menuBarTitleParts(now: now).stringValue, "Codex · No limits")
    }

    func testExpiredReportedWindowsNeverFallBackToTokenEstimates() throws {
        let home = try TemporaryCodexHome()
        try home.createStateDatabase(rows: [(19_000, 0, 9_000_000)])
        try home.createSessionLog(lines: [
            #"{"payload":{"rate_limits":{"primary":{"used_percent":50,"window_minutes":10080,"resets_at":19999}}}}"#
        ])
        let snapshot = CodexUsageProvider().loadUsage(settings: settings(home), now: Date(timeIntervalSince1970: 20_000))
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.source, .unavailable)
        XCTAssertFalse(snapshot.menuBarTitleParts(now: Date()).stringValue.contains("%"))
    }

}

private struct DeniedFolderChecker: CodexFolderChecking {
    func check(_ url: URL) -> CodexFolderAccess { .denied }
}

private struct MustNotReadSQLite: SQLiteQuerying {
    func runReadOnlyQuery(databasePath: String, query: String) throws -> String {
        XCTFail("Usage must not be read after folder access is denied.")
        return ""
    }
}

private final class TemporaryCodexHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenCodexInfoTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func createLogsDatabase(rows: [(timestamp: Int, body: String)]) throws {
        let db = url.appendingPathComponent("logs_2.sqlite")
        var sql = "CREATE TABLE logs (ts INTEGER NOT NULL, feedback_log_body TEXT);"
        for row in rows {
            sql += "INSERT INTO logs (ts, feedback_log_body) VALUES (\(row.timestamp), '\(escape(row.body))');"
        }
        try runSQLite(database: db, sql: sql)
    }

    func createSessionLog(lines: [String]) throws {
        let sessions = url
            .appendingPathComponent("sessions")
            .appendingPathComponent("1970")
            .appendingPathComponent("01")
            .appendingPathComponent("01")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-test.jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    func createStateDatabase(rows: [(updatedAt: Int, updatedAtMs: Int, tokens: Int)]) throws {
        let db = url.appendingPathComponent("state_5.sqlite")
        var sql = "CREATE TABLE threads (updated_at INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, tokens_used INTEGER NOT NULL);"
        for row in rows {
            sql += "INSERT INTO threads (updated_at, updated_at_ms, tokens_used) VALUES (\(row.updatedAt), \(row.updatedAtMs), \(row.tokens));"
        }
        try runSQLite(database: db, sql: sql)
    }

    private func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail(message)
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
