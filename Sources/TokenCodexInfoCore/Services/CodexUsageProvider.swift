import Foundation

public protocol UsageProviding: Sendable {
    func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot
}

public final class CodexUsageProvider: UsageProviding, @unchecked Sendable {
    private let sqlite: SQLiteQuerying
    private let folderChecker: CodexFolderChecking

    public init(sqlite: SQLiteQuerying = SQLiteCommandClient(), folderChecker: CodexFolderChecking = CodexFolderChecker()) {
        self.sqlite = sqlite
        self.folderChecker = folderChecker
    }

    public func loadUsage(settings: UsageSettings, now: Date = Date()) -> UsageSnapshot {
        guard !settings.codexHomePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return unavailable(settings: settings, now: now, issue: .folderMissing)
        }
        let access = folderChecker.check(settings.expandedCodexHomeURL)
        let issue: CodexDataIssue?
        switch access {
        case .readable: issue = nil
        case .missing: issue = .folderMissing
        case .notDirectory: issue = .notDirectory
        case .denied: issue = .accessDenied
        case .failed: issue = .readFailed
        }
        if let issue { return unavailable(settings: settings, now: now, issue: issue) }

        var failures: [Error] = []
        do {
            if let snapshot = try loadFromSessionEvents(settings: settings, now: now) {
                return snapshot
            }
        } catch { failures.append(error) }

        let home = settings.expandedCodexHomeURL
        if FileManager.default.fileExists(atPath: home.appendingPathComponent("logs_2.sqlite").path) {
            do {
                if let snapshot = try loadFromRateLimitEvents(settings: settings, now: now) { return snapshot }
                if let snapshot = try loadFromLogs(settings: settings, now: now) { return snapshot }
            } catch { failures.append(error) }
        }
        if FileManager.default.fileExists(atPath: home.appendingPathComponent("state_5.sqlite").path) {
            do {
                if let snapshot = try loadFromThreads(settings: settings, now: now) { return snapshot }
            } catch { failures.append(error) }
        }

        // Folder permission does not guarantee permission to individual files.
        let denied = failures.contains(where: isCodexPermissionError)
            || ["sessions", "logs_2.sqlite", "state_5.sqlite"].contains { name in
                let path = home.appendingPathComponent(name).path
                return FileManager.default.fileExists(atPath: path) && !FileManager.default.isReadableFile(atPath: path)
            }
        return unavailable(settings: settings, now: now, issue: denied ? .accessDenied : (failures.isEmpty ? .noUsageData : .readFailed))
    }

    private func unavailable(settings: UsageSettings, now: Date, issue: CodexDataIssue) -> UsageSnapshot {
        .empty(limitTokens: settings.fiveHourTokenLimit, weeklyLimitTokens: settings.weeklyTokenLimit, now: now, issue: issue)
    }

    private func loadFromRateLimitEvents(settings: UsageSettings, now: Date) throws -> UsageSnapshot? {
        let dbPath = settings.expandedCodexHomeURL.appendingPathComponent("logs_2.sqlite").path
        let query = """
        SELECT feedback_log_body
        FROM logs
        WHERE feedback_log_body GLOB 'Received message {"type":"codex.rate_limits"*'
           OR feedback_log_body LIKE '%: websocket event: {"type":"codex.rate_limits"%'
        ORDER BY ts DESC
        LIMIT 100;
        """

        let output = try sqlite.runReadOnlyQuery(databasePath: dbPath, query: query)
        let decoder = JSONDecoder()

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard let json = line.codexRateLimitsJSON(),
                  let event = try? decoder.decode(CodexRateLimitsEvent.self, from: Data(json.utf8)),
                  let snapshot = event.snapshot(now: now)
            else {
                continue
            }

            return snapshot
        }

        return nil
    }

    private func loadFromSessionEvents(settings: UsageSettings, now: Date) throws -> UsageSnapshot? {
        let sessionsURL = settings.expandedCodexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sessionsURL.path) else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var readError: Error?
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                readError = error
                return true
            }
        ) else {
            return nil
        }

        let sessionFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> (url: URL, modifiedAt: Date)? in
                let values: URLResourceValues
                do {
                    values = try url.resourceValues(forKeys: resourceKeys)
                } catch {
                    readError = error
                    return nil
                }
                guard values.isRegularFile == true else { return nil }

                return (url: url, modifiedAt: values.contentModificationDate ?? .distantPast)
            }
            .sorted {
                if $0.modifiedAt == $1.modifiedAt {
                    return $0.url.path > $1.url.path
                }
                return $0.modifiedAt > $1.modifiedAt
            }

        let decoder = JSONDecoder()
        for file in sessionFiles.prefix(25) {
            do {
                if let snapshot = try newestSessionSnapshot(in: file.url, decoder: decoder, now: now) { return snapshot }
            } catch {
                readError = error
            }
        }

        if let readError { throw readError }
        return nil
    }

    private func newestSessionSnapshot(in url: URL, decoder: JSONDecoder, now: Date) throws -> UsageSnapshot? {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var lineEnd = data.count

        while lineEnd > 0 {
            while lineEnd > 0 && (data[lineEnd - 1] == 10 || data[lineEnd - 1] == 13) {
                lineEnd -= 1
            }
            guard lineEnd > 0 else {
                break
            }

            var lineStart = lineEnd
            while lineStart > 0 && data[lineStart - 1] != 10 {
                lineStart -= 1
            }

            let lineData = Data(data[lineStart..<lineEnd])
            if lineData.range(of: Data(#""rate_limits""#.utf8)) != nil,
               let snapshot = sessionSnapshot(from: lineData, decoder: decoder, now: now) {
                return snapshot
            }

            lineEnd = lineStart
        }

        return nil
    }

    private func sessionSnapshot(from lineData: Data, decoder: JSONDecoder, now: Date) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }

        let payload = object["payload"] as? [String: Any]
        for rateLimitsObject in [payload?["rate_limits"], object["rate_limits"]] {
            guard let rateLimitsObject,
                  JSONSerialization.isValidJSONObject(rateLimitsObject),
                  let rateLimitsData = try? JSONSerialization.data(withJSONObject: rateLimitsObject),
                  let rateLimits = try? decoder.decode(CodexSessionRateLimits.self, from: rateLimitsData),
                  let snapshot = rateLimits.snapshot(now: now)
            else {
                continue
            }

            return snapshot
        }

        return nil
    }

    private func loadFromLogs(settings: UsageSettings, now: Date) throws -> UsageSnapshot? {
        let dbPath = settings.expandedCodexHomeURL.appendingPathComponent("logs_2.sqlite").path
        let since = Int(now.addingTimeInterval(-settings.weeklyWindowSeconds).timeIntervalSince1970)
        let query = """
        SELECT ts, replace(replace(feedback_log_body, char(10), ' '), char(13), ' ')
        FROM logs
        WHERE ts >= \(since)
          AND feedback_log_body LIKE '%post sampling token usage%'
        ORDER BY ts ASC;
        """

        let output = try sqlite.runReadOnlyQuery(databasePath: dbPath, query: query)
        let events = output
            .split(whereSeparator: \.isNewline)
            .compactMap { LogUsageEvent(line: String($0), separator: SQLiteClientConstants.fieldSeparator) }
            .map(\.event)

        return snapshot(from: deduplicated(events: events), settings: settings, now: now, source: .logs)
    }

    private func loadFromThreads(settings: UsageSettings, now: Date) throws -> UsageSnapshot? {
        let dbPath = settings.expandedCodexHomeURL.appendingPathComponent("state_5.sqlite").path
        let since = Int(now.addingTimeInterval(-settings.weeklyWindowSeconds).timeIntervalSince1970)
        let query = """
        SELECT (CASE
                WHEN updated_at > 0 THEN updated_at
                WHEN updated_at_ms > 0 THEN updated_at_ms / 1000
                ELSE 0
              END), tokens_used
        FROM threads
        WHERE (CASE
                WHEN updated_at > 0 THEN updated_at
                WHEN updated_at_ms > 0 THEN updated_at_ms / 1000
                ELSE 0
              END) >= \(since)
          AND tokens_used > 0
        ORDER BY 1 ASC;
        """

        let output = try sqlite.runReadOnlyQuery(databasePath: dbPath, query: query)
        let events = output
            .split(whereSeparator: \.isNewline)
            .compactMap { ThreadUsageEvent(line: String($0), separator: SQLiteClientConstants.fieldSeparator) }

        return snapshot(
            from: events.map { UsageEvent(timestamp: $0.timestamp, turnID: $0.threadID, tokens: $0.tokens) },
            settings: settings,
            now: now,
            source: .threadsEstimate,
            errorMessage: "Using thread estimate; logs unavailable."
        )
    }

    private func deduplicated(events: [UsageEvent]) -> [UsageEvent] {
        var latestByTurn: [String: UsageEvent] = [:]

        for event in events {
            guard let existing = latestByTurn[event.turnID] else {
                latestByTurn[event.turnID] = event
                continue
            }

            if event.timestamp > existing.timestamp || (event.timestamp == existing.timestamp && event.tokens > existing.tokens) {
                latestByTurn[event.turnID] = event
            }
        }

        return latestByTurn.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func snapshot(
        from events: [UsageEvent],
        settings: UsageSettings,
        now: Date,
        source: UsageDataSource,
        errorMessage: String? = nil
    ) -> UsageSnapshot? {
        let fiveHourWindowStart = now.addingTimeInterval(-settings.windowSeconds)
        let fiveHourEvents = events.filter { $0.timestamp >= fiveHourWindowStart }
        let weeklyWindowStart = now.addingTimeInterval(-settings.weeklyWindowSeconds)
        let weeklyEvents = events.filter { $0.timestamp >= weeklyWindowStart }
        guard !weeklyEvents.isEmpty else { return nil }

        let usedTokens = fiveHourEvents.reduce(0) { $0 + $1.tokens }
        let oldest = fiveHourEvents.map(\.timestamp).min()
        let resetAt = oldest?.addingTimeInterval(settings.windowSeconds)

        let weeklyUsedTokens = weeklyEvents.reduce(0) { $0 + $1.tokens }
        let weeklyOldest = weeklyEvents.map(\.timestamp).min()
        let weeklyResetAt = weeklyOldest?.addingTimeInterval(settings.weeklyWindowSeconds)

        return UsageSnapshot(
            usedTokens: usedTokens,
            limitTokens: settings.fiveHourTokenLimit,
            resetAt: resetAt,
            weeklyUsedTokens: weeklyUsedTokens,
            weeklyLimitTokens: settings.weeklyTokenLimit,
            weeklyResetAt: weeklyResetAt,
            observedAt: now,
            source: source,
            errorMessage: errorMessage,
            // Older weekly activity says nothing about the current five-hour
            // allowance. Let the UI use the weekly estimate in that case.
            fiveHourIsAvailable: !fiveHourEvents.isEmpty,
            weeklyIsAvailable: true
        )
    }
}

private struct UsageEvent: Equatable {
    var timestamp: Date
    var turnID: String
    var tokens: Int
}

private struct LogUsageEvent {
    private static let turnIDPattern = #"turn_id=([A-Za-z0-9_-]+)"#
    private static let tokenPattern = #"total_usage_tokens=([0-9]+)"#

    init?(line: String, separator: Character) {
        let parts = line.split(separator: separator, maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let timestamp = TimeInterval(parts[0]),
              let turnID = parts[1].firstMatch(pattern: Self.turnIDPattern),
              let tokenText = parts[1].firstMatch(pattern: Self.tokenPattern),
              let tokens = Int(tokenText)
        else {
            return nil
        }

        event = UsageEvent(timestamp: Date(timeIntervalSince1970: timestamp), turnID: turnID, tokens: tokens)
    }

    var event: UsageEvent
}

private struct ThreadUsageEvent {
    init?(line: String, separator: Character) {
        let parts = line.split(separator: separator, maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let timestamp = TimeInterval(parts[0]),
              let tokens = Int(parts[1])
        else {
            return nil
        }

        self.timestamp = Date(timeIntervalSince1970: timestamp)
        self.tokens = tokens
        self.threadID = parts[0]
    }

    var timestamp: Date
    var threadID: String
    var tokens: Int
}

private struct CodexRateLimitsEvent: Decodable {
    var type: String
    var rateLimits: CodexRateLimitWindows

    private enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }

    func snapshot(now: Date) -> UsageSnapshot? {
        guard type == "codex.rate_limits" else {
            return nil
        }

        return rateLimits.snapshot(now: now)
    }
}

private struct CodexSessionEvent: Decodable {
    var rateLimits: CodexSessionRateLimits?

    private enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    func snapshot(now: Date) -> UsageSnapshot? {
        rateLimits?.snapshot(now: now)
    }
}

private struct CodexSessionRateLimits: Decodable {
    var limitID: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
    }

    func snapshot(now: Date) -> UsageSnapshot? {
        guard limitID == nil || limitID == "codex" else {
            return nil
        }

        return CodexRateLimitWindows(primary: primary, secondary: secondary)
            .snapshot(now: now)
    }
}

private struct CodexRateLimitWindows: Decodable {
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?

    func snapshot(now: Date) -> UsageSnapshot? {
        let windows = classifiedWindows()
        guard windows.fiveHour != nil || windows.weekly != nil else {
            return nil
        }

        let fiveHour = usageWindowSnapshot(for: windows.fiveHour, now: now)
        let weekly = usageWindowSnapshot(for: windows.weekly, now: now)
        guard fiveHour.isAvailable || weekly.isAvailable else { return nil }

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            observedAt: now,
            source: .rateLimits
        )
    }

    private func classifiedWindows() -> (fiveHour: CodexRateLimitWindow?, weekly: CodexRateLimitWindow?) {
        let allWindows = [primary, secondary].compactMap { $0 }

        let fiveHour = allWindows.first { $0.isFiveHourWindow }
            ?? fallbackFiveHourWindow()
        let weekly = allWindows.first { $0.isWeeklyWindow }
            ?? fallbackWeeklyWindow()

        return (fiveHour, weekly)
    }

    private func fallbackFiveHourWindow() -> CodexRateLimitWindow? {
        guard primary?.windowMinutes == nil,
              secondary?.windowMinutes == nil
        else {
            return nil
        }
        return primary
    }

    private func fallbackWeeklyWindow() -> CodexRateLimitWindow? {
        guard primary?.windowMinutes == nil,
              secondary?.windowMinutes == nil
        else {
            return nil
        }
        return secondary
    }

    private func usageWindowSnapshot(
        for window: CodexRateLimitWindow?,
        now: Date
    ) -> UsageWindowSnapshot {
        guard let window else {
            return .empty(limitTokens: 100, isAvailable: false)
        }

        let reset = window.resetDate
        if reset.map({ $0 <= now }) == true {
            return .empty(limitTokens: 100, isAvailable: false)
        }

        return UsageWindowSnapshot(
            usedTokens: window.usedPercentRounded,
            limitTokens: 100,
            resetAt: reset
        )
    }
}

private struct CodexRateLimitWindow: Decodable {
    var usedPercent: Double
    var resetAt: TimeInterval?
    var windowMinutes: Double?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetAt = "reset_at"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        windowMinutes = try container.decodeIfPresent(Double.self, forKey: .windowMinutes)
        resetAt = try container.decodeIfPresent(TimeInterval.self, forKey: .resetAt)
            ?? container.decodeIfPresent(TimeInterval.self, forKey: .resetsAt)
    }

    var resetDate: Date? {
        guard let resetAt else {
            return nil
        }
        return Date(timeIntervalSince1970: resetAt)
    }

    var isFiveHourWindow: Bool {
        guard let windowMinutes else {
            return false
        }
        return abs(windowMinutes - 300) < 0.1
    }

    var isWeeklyWindow: Bool {
        guard let windowMinutes else {
            return false
        }
        return abs(windowMinutes - 10_080) < 0.1
    }

    var usedPercentRounded: Int {
        Int(min(max(usedPercent, 0), 100).rounded())
    }
}

private extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }

        return String(self[captureRange])
    }

    func codexRateLimitsJSON() -> String? {
        guard let start = range(of: #"{"type":"codex.rate_limits""#)?.lowerBound else {
            return nil
        }

        var depth = 0
        var isEscaped = false
        var isInsideString = false
        var index = start

        while index < endIndex {
            let character = self[index]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(self[start...index])
                    }
                }
            }

            index = self.index(after: index)
        }

        return nil
    }
}
