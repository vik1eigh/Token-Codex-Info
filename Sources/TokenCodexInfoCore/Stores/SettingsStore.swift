import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let defaultCodexHomePath = "~/.codex"
    public static let defaultFiveHourTokenLimit = 244_800
    public static let defaultWeeklyTokenLimit = defaultFiveHourTokenLimit * 7
    public static let defaultRefreshIntervalSeconds = 60

    @Published public var codexHomePath: String {
        didSet {
            defaults.set(codexHomePath, forKey: Keys.codexHomePath)
        }
    }

    @Published public var fiveHourTokenLimit: Int {
        didSet {
            if fiveHourTokenLimit < 1 {
                fiveHourTokenLimit = 1
            }
            defaults.set(fiveHourTokenLimit, forKey: Keys.fiveHourTokenLimit)
        }
    }

    @Published public var weeklyTokenLimit: Int {
        didSet {
            if weeklyTokenLimit < 1 {
                weeklyTokenLimit = 1
            }
            defaults.set(weeklyTokenLimit, forKey: Keys.weeklyTokenLimit)
        }
    }

    @Published public var refreshIntervalSeconds: Int {
        didSet {
            if refreshIntervalSeconds < 1 {
                refreshIntervalSeconds = 1
            }
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        codexHomePath = defaults.string(forKey: Keys.codexHomePath) ?? Self.defaultCodexHomePath

        let storedLimit = defaults.integer(forKey: Keys.fiveHourTokenLimit)
        fiveHourTokenLimit = storedLimit > 0 ? storedLimit : Self.defaultFiveHourTokenLimit

        let storedWeeklyLimit = defaults.integer(forKey: Keys.weeklyTokenLimit)
        weeklyTokenLimit = storedWeeklyLimit > 0 ? storedWeeklyLimit : Self.defaultWeeklyTokenLimit

        let storedRefresh = defaults.integer(forKey: Keys.refreshIntervalSeconds)
        refreshIntervalSeconds = storedRefresh > 0 ? storedRefresh : Self.defaultRefreshIntervalSeconds
    }

    public var usageSettings: UsageSettings {
        UsageSettings(
            codexHomePath: codexHomePath,
            fiveHourTokenLimit: fiveHourTokenLimit,
            weeklyTokenLimit: weeklyTokenLimit,
            refreshIntervalSeconds: refreshIntervalSeconds
        )
    }

    public var hasCompletedSetup: Bool {
        defaults.bool(forKey: Keys.hasCompletedSetup)
    }

    public func completeSetup() {
        defaults.set(true, forKey: Keys.hasCompletedSetup)
    }

    private enum Keys {
        static let codexHomePath = "codexHomePath"
        static let fiveHourTokenLimit = "fiveHourTokenLimit"
        static let weeklyTokenLimit = "weeklyTokenLimit"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let hasCompletedSetup = "hasCompletedSetup"
    }
}
