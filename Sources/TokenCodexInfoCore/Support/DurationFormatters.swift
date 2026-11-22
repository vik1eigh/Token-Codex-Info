import Foundation

public struct MenuBarTitleParts: Equatable, Sendable {
    public var percent: String
    public var separator: String
    public var hours: String
    public var colon: String
    public var minutes: String

    public var stringValue: String {
        "\(percent) \(separator) \(hours)\(colon)\(minutes)"
    }
}

public enum CountdownFormatter {
    public static func menuClock(seconds: TimeInterval) -> String {
        let totalMinutes = roundedUpMinutes(seconds: seconds)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    public static func menuParts(percent: Int, seconds: TimeInterval) -> MenuBarTitleParts {
        let clock = menuClock(seconds: seconds)
        let pieces = clock.split(separator: ":", maxSplits: 1).map(String.init)
        let hours = pieces.first ?? "0"
        let minutes = pieces.count > 1 ? pieces[1] : "00"

        return MenuBarTitleParts(
            percent: "\(percent)%",
            separator: "·",
            hours: hours,
            colon: ":",
            minutes: minutes
        )
    }

    public static func words(seconds: TimeInterval) -> String {
        let totalMinutes = roundedUpMinutes(seconds: seconds)
        if totalMinutes <= 0 {
            return "now"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func roundedUpMinutes(seconds: TimeInterval) -> Int {
        guard seconds > 0 else {
            return 0
        }
        return Int(ceil(seconds / 60))
    }
}

public enum MenuBarTitleFormatter {
    public static func string(percent: Int, countdownSeconds: TimeInterval) -> String {
        parts(percent: percent, countdownSeconds: countdownSeconds).stringValue
    }

    public static func string(percent: Int, resetAt: Date?, now: Date) -> String {
        parts(percent: percent, resetAt: resetAt, now: now).stringValue
    }

    public static func string(percent: Int, resetText: String) -> String {
        parts(percent: percent, resetText: resetText).stringValue
    }

    public static func parts(percent: Int, countdownSeconds: TimeInterval) -> MenuBarTitleParts {
        CountdownFormatter.menuParts(percent: min(100, max(0, percent)), seconds: countdownSeconds)
    }

    public static func parts(percent: Int, resetText: String) -> MenuBarTitleParts {
        MenuBarTitleParts(
            percent: "\(min(100, max(0, percent)))%",
            separator: "·",
            hours: resetText,
            colon: "",
            minutes: ""
        )
    }

    public static func parts(percent: Int, resetAt: Date?, now: Date) -> MenuBarTitleParts {
        guard let resetAt, resetAt > now else {
            return parts(percent: percent, resetText: "--")
        }

        return parts(percent: percent, countdownSeconds: max(0, resetAt.timeIntervalSince(now)))
    }
}

public enum ResetDateFormatter {
    public static func menuDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
