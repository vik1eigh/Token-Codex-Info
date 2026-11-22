import Combine
import Foundation

public struct UsageLimitDisplayRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var percentText: String
    public var resetText: String
}

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot
    @Published public private(set) var now: Date
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastCheckedAt: Date?

    private let provider: UsageProviding
    private weak var settings: SettingsStore?
    private var timer: Timer?
    private var lastRefreshAt: Date?
    private var lastResetBoundaryRefreshAt: Date?
    private var started = false
    private var settingsSubscription: AnyCancellable?

    public init(provider: UsageProviding) {
        let initialNow = Date()
        self.provider = provider
        self.now = initialNow
        self.snapshot = .empty(
            limitTokens: SettingsStore.defaultFiveHourTokenLimit,
            weeklyLimitTokens: SettingsStore.defaultWeeklyTokenLimit,
            now: initialNow,
            issue: .checking
        )
    }

    deinit {
        timer?.invalidate()
    }

    public func start(settings: SettingsStore) {
        self.settings = settings

        guard !started else {
            return
        }

        started = true
        settingsSubscription = settings.$codexHomePath
            .combineLatest(settings.$fiveHourTokenLimit, settings.$weeklyTokenLimit, settings.$refreshIntervalSeconds)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.snapshot = .empty(limitTokens: settings.fiveHourTokenLimit, weeklyLimitTokens: settings.weeklyTokenLimit, now: Date(), issue: .checking)
                self.refreshNow()
            }
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    public func refreshNow() {
        guard let settings, !isRefreshing else {
            return
        }

        let usageSettings = settings.usageSettings
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [provider] in
            let loaded = provider.loadUsage(settings: usageSettings, now: Date())
            DispatchQueue.main.async {
                // A folder selection may change while the previous read is in flight.
                guard self.settings?.usageSettings == usageSettings else {
                    self.isRefreshing = false
                    self.refreshNow()
                    return
                }
                self.snapshot = loaded
                self.now = Date()
                self.lastRefreshAt = self.now
                self.lastCheckedAt = self.now
                if loaded.resetAt.map({ $0 > self.now }) == true {
                    self.lastResetBoundaryRefreshAt = nil
                }
                self.isRefreshing = false
            }
        }
    }

    private func tick() {
        now = Date()

        guard let settings else {
            return
        }

        if shouldRefreshAfterResetBoundary(now: now) {
            refreshNow()
            return
        }

        let refreshInterval = TimeInterval(settings.refreshIntervalSeconds)
        if lastRefreshAt == nil || now.timeIntervalSince(lastRefreshAt!) >= refreshInterval {
            refreshNow()
        }
    }

    private func shouldRefreshAfterResetBoundary(now: Date) -> Bool {
        guard !isRefreshing,
              let resetAt = snapshot.menuBarWindow.resetAt,
              resetAt <= now
        else {
            return false
        }

        if let lastResetBoundaryRefreshAt,
           now.timeIntervalSince(lastResetBoundaryRefreshAt) < 5 {
            return false
        }

        lastResetBoundaryRefreshAt = now
        return true
    }

    public var countdownSeconds: TimeInterval {
        snapshot.menuBarWindow.secondsUntilReset(from: now)
    }

    public var menuBarTitleParts: MenuBarTitleParts {
        snapshot.menuBarTitleParts(now: now)
    }

    public var accessibilityTitle: String {
        snapshot.menuBarAccessibilityTitle(now: now)
    }

    public var countdownWords: String {
        CountdownFormatter.words(seconds: countdownSeconds)
    }

    public var usageRows: [UsageLimitDisplayRow] {
        guard snapshot.hasData else { return [] }
        var rows: [UsageLimitDisplayRow] = []

        if snapshot.fiveHour.isAvailable {
            rows.append(UsageLimitDisplayRow(
                id: "5h",
                title: "5h",
                percentText: "\(snapshot.fiveHour.remainingPercent)%",
                resetText: timeResetText(snapshot.fiveHour.resetAt)
            ))
        }

        if snapshot.weekly.isAvailable {
            rows.append(UsageLimitDisplayRow(
                id: "weekly",
                title: "Weekly",
                percentText: "\(snapshot.weekly.remainingPercent)%",
                resetText: dateResetText(snapshot.weekly.resetAt)
            ))
        }

        return rows
    }

    public var errorMessage: String? {
        snapshot.errorMessage
    }

    private func timeResetText(_ resetAt: Date?) -> String {
        guard let resetAt else {
            return "--"
        }
        return resetAt.formatted(date: .omitted, time: .shortened)
    }

    private func dateResetText(_ resetAt: Date?) -> String {
        guard let resetAt else {
            return "--"
        }
        return ResetDateFormatter.menuDate(resetAt)
    }
}
