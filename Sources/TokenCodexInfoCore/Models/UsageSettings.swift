import Foundation

public struct UsageSettings: Equatable, Sendable {
    public var codexHomePath: String
    public var fiveHourTokenLimit: Int
    public var weeklyTokenLimit: Int
    public var refreshIntervalSeconds: Int
    public var windowSeconds: TimeInterval
    public var weeklyWindowSeconds: TimeInterval

    public init(
        codexHomePath: String,
        fiveHourTokenLimit: Int,
        weeklyTokenLimit: Int? = nil,
        refreshIntervalSeconds: Int,
        windowSeconds: TimeInterval = 5 * 60 * 60,
        weeklyWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.codexHomePath = codexHomePath
        self.fiveHourTokenLimit = max(1, fiveHourTokenLimit)
        self.weeklyTokenLimit = max(1, weeklyTokenLimit ?? fiveHourTokenLimit * 7)
        self.refreshIntervalSeconds = max(1, refreshIntervalSeconds)
        self.windowSeconds = windowSeconds
        self.weeklyWindowSeconds = weeklyWindowSeconds
    }

    public var expandedCodexHomeURL: URL {
        URL(fileURLWithPath: (codexHomePath as NSString).expandingTildeInPath)
    }
}
