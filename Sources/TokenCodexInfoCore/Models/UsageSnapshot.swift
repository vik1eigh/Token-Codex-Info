import Foundation

public enum UsageDataSource: String, Equatable, Sendable {
    case rateLimits
    case logs
    case threadsEstimate
    case unavailable

    public var isEstimate: Bool {
        self == .logs || self == .threadsEstimate
    }
}

public enum CodexDataIssue: String, Equatable, Sendable {
    case checking, folderMissing, notDirectory, accessDenied, noUsageData, readFailed

    public var title: String {
        switch self {
        case .checking: return "Checking Codex data…"
        case .folderMissing: return "Codex folder not found"
        case .notDirectory: return "Choose a folder"
        case .accessDenied: return "Access to Codex data denied"
        case .noUsageData: return "No usage data yet"
        case .readFailed: return "Unable to read Codex data"
        }
    }

    public var message: String {
        switch self {
        case .checking: return "Checking the selected folder for local usage data."
        case .folderMissing: return "Open Codex and start a session on this Mac, or choose your Codex data folder below."
        case .notDirectory: return "The selected path is a file. Choose the Codex data folder, usually ~/.codex."
        case .accessDenied: return "The app could not read the selected folder or its usage files. Choose the folder again to allow access, or check its permissions."
        case .noUsageData: return "The folder is accessible, but no usable limits or token activity were found. Run a session in Codex, then check again."
        case .readFailed: return "The folder exists, but its usage files could not be read. Check again after Codex finishes writing, or choose another folder."
        }
    }

    public var menuBarText: String {
        switch self {
        case .checking: return "Checking"
        case .folderMissing, .notDirectory: return "Setup"
        case .accessDenied: return "No access"
        case .noUsageData: return "No data"
        case .readFailed: return "Read error"
        }
    }
}

public struct UsageWindowSnapshot: Equatable, Sendable {
    public var usedTokens: Int
    public var limitTokens: Int
    public var resetAt: Date?
    public var isAvailable: Bool

    public init(
        usedTokens: Int,
        limitTokens: Int,
        resetAt: Date?,
        isAvailable: Bool = true
    ) {
        self.usedTokens = max(0, usedTokens)
        self.limitTokens = max(1, limitTokens)
        self.resetAt = resetAt
        self.isAvailable = isAvailable
    }

    public static func empty(limitTokens: Int, isAvailable: Bool = true) -> UsageWindowSnapshot {
        UsageWindowSnapshot(usedTokens: 0, limitTokens: limitTokens, resetAt: nil, isAvailable: isAvailable)
    }

    public var usedFraction: Double {
        Double(usedTokens) / Double(limitTokens)
    }

    public var remainingFraction: Double {
        min(1, max(0, 1 - usedFraction))
    }

    public var rawPercent: Int {
        max(0, Int((usedFraction * 100).rounded()))
    }

    public var remainingPercent: Int {
        Int((remainingFraction * 100).rounded())
    }

    public func secondsUntilReset(from now: Date) -> TimeInterval {
        guard let resetAt else {
            return 0
        }
        return max(0, resetAt.timeIntervalSince(now))
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public var fiveHour: UsageWindowSnapshot
    public var weekly: UsageWindowSnapshot
    public var observedAt: Date
    public var source: UsageDataSource
    public var errorMessage: String?
    public var issue: CodexDataIssue?

    public init(
        usedTokens: Int,
        limitTokens: Int,
        resetAt: Date?,
        weeklyUsedTokens: Int? = nil,
        weeklyLimitTokens: Int? = nil,
        weeklyResetAt: Date? = nil,
        observedAt: Date,
        source: UsageDataSource,
        errorMessage: String? = nil,
        issue: CodexDataIssue? = nil,
        fiveHourIsAvailable: Bool = true,
        weeklyIsAvailable: Bool = true
    ) {
        fiveHour = UsageWindowSnapshot(
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            resetAt: resetAt,
            isAvailable: fiveHourIsAvailable
        )
        weekly = UsageWindowSnapshot(
            usedTokens: weeklyUsedTokens ?? usedTokens,
            limitTokens: weeklyLimitTokens ?? limitTokens,
            resetAt: weeklyResetAt ?? resetAt,
            isAvailable: weeklyIsAvailable
        )
        self.observedAt = observedAt
        self.source = source
        self.errorMessage = errorMessage
        self.issue = issue
    }

    public init(
        fiveHour: UsageWindowSnapshot,
        weekly: UsageWindowSnapshot,
        observedAt: Date,
        source: UsageDataSource,
        errorMessage: String? = nil,
        issue: CodexDataIssue? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.observedAt = observedAt
        self.source = source
        self.errorMessage = errorMessage
        self.issue = issue
    }

    public static func empty(
        limitTokens: Int,
        weeklyLimitTokens: Int? = nil,
        now: Date,
        source: UsageDataSource = .unavailable,
        errorMessage: String? = nil,
        issue: CodexDataIssue = .noUsageData
    ) -> UsageSnapshot {
        UsageSnapshot(
            usedTokens: 0,
            limitTokens: limitTokens,
            resetAt: nil,
            weeklyUsedTokens: 0,
            weeklyLimitTokens: weeklyLimitTokens ?? limitTokens,
            weeklyResetAt: nil,
            observedAt: now,
            source: source,
            errorMessage: errorMessage ?? issue.message,
            issue: issue,
            fiveHourIsAvailable: false,
            weeklyIsAvailable: false
        )
    }

    public var hasData: Bool {
        source != .unavailable && (fiveHour.isAvailable || weekly.isAvailable)
    }

    public var statusTitle: String {
        guard hasData else { return (issue ?? .noUsageData).title }
        return source.isEstimate ? "Estimated usage" : "Reported limits"
    }

    public var statusMessage: String {
        guard hasData else { return (issue ?? .noUsageData).message }
        if source.isEstimate {
            let windowMessage = fiveHour.isAvailable ? "" : "No token activity was found in the last five hours; showing a weekly estimate. "
            return windowMessage + "No current reported limits were found in this folder. Estimates use local token activity and the limits below, and may miss usage on other Macs. Run a prompt in Codex, then click Check Again to look for updated limits."
        }
        return "Read from a local Codex rate-limit snapshot. Updates when Codex writes new data."
    }

    public var usedTokens: Int {
        fiveHour.usedTokens
    }

    public var limitTokens: Int {
        fiveHour.limitTokens
    }

    public var resetAt: Date? {
        fiveHour.resetAt
    }

    public var usedFraction: Double {
        fiveHour.usedFraction
    }

    public var remainingFraction: Double {
        fiveHour.remainingFraction
    }

    public var rawPercent: Int {
        fiveHour.rawPercent
    }

    public var remainingPercent: Int {
        fiveHour.remainingPercent
    }

    public func secondsUntilReset(from now: Date) -> TimeInterval {
        fiveHour.secondsUntilReset(from: now)
    }

    public var menuBarWindow: UsageWindowSnapshot {
        if fiveHour.isAvailable || !weekly.isAvailable {
            return fiveHour
        }
        return weekly
    }

    public var menuBarWindowName: String {
        if fiveHour.isAvailable || !weekly.isAvailable {
            return "5 hour"
        }
        return "weekly"
    }

    public var menuBarUsesDateReset: Bool {
        !fiveHour.isAvailable && weekly.isAvailable
    }

    public func menuBarTitleParts(now: Date) -> MenuBarTitleParts {
        guard hasData else {
            return MenuBarTitleParts(percent: "Codex", separator: "·", hours: (issue ?? .noUsageData).menuBarText, colon: "", minutes: "")
        }
        let window = menuBarWindow
        var parts: MenuBarTitleParts
        if menuBarUsesDateReset, let resetAt = window.resetAt {
            parts = MenuBarTitleFormatter.parts(percent: window.remainingPercent, resetText: ResetDateFormatter.menuDate(resetAt))
        } else {
            parts = MenuBarTitleFormatter.parts(percent: window.remainingPercent, resetAt: window.resetAt, now: now)
        }
        if source.isEstimate { parts.percent = "≈" + parts.percent }
        return parts
    }

    public func menuBarAccessibilityTitle(now: Date) -> String {
        guard hasData else { return "\(statusTitle). \(statusMessage)" }
        let window = menuBarWindow
        let resetDescription: String
        if let resetAt = window.resetAt {
            if menuBarUsesDateReset {
                resetDescription = "resets on \(ResetDateFormatter.menuDate(resetAt))"
            } else {
                resetDescription = "resets in \(CountdownFormatter.words(seconds: window.secondsUntilReset(from: now)))"
            }
        } else {
            resetDescription = "unknown reset time"
        }

        let prefix = source.isEstimate ? "Estimated: " : ""
        return "\(prefix)\(window.remainingPercent)% of \(menuBarWindowName) limit remaining, \(resetDescription)"
    }
}
