import Foundation

public enum QuotaStatus: Sendable, Equatable {
    case ok
    case stale
    case unavailable
    case signedOut
}

public struct QuotaWindow: Identifiable, Sendable, Equatable {
    public let id: String
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let duration: TimeInterval?

    public init(id: String, remainingPercent: Double, resetsAt: Date?, duration: TimeInterval?) {
        self.id = id
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.duration = duration
    }
}

public struct QuotaSnapshot: Sendable, Equatable {
    public let plan: String?
    public let windows: [QuotaWindow]
    public let resetCredits: Int?
    public let resetCreditExpirations: [Date]
    public let refreshedAt: Date
    public let status: QuotaStatus
    public let message: String?

    public init(plan: String?, windows: [QuotaWindow], resetCredits: Int?, resetCreditExpirations: [Date], refreshedAt: Date, status: QuotaStatus, message: String?) {
        self.plan = plan
        self.windows = windows
        self.resetCredits = resetCredits
        self.resetCreditExpirations = resetCreditExpirations
        self.refreshedAt = refreshedAt
        self.status = status
        self.message = message
    }

    public static func unavailable(message: String) -> Self {
        .init(plan: nil, windows: [], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .unavailable, message: message)
    }
}

public struct DailyValue: Sendable, Equatable {
    public let date: Date
    public let value: Double
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

public struct ModelSeries: Sendable, Equatable {
    public let model: String
    public let points: [Double]
    public init(model: String, points: [Double]) { self.model = model; self.points = points }
}

public struct SkillUsage: Sendable, Equatable {
    public let name: String
    public let count: Int
    public init(name: String, count: Int) { self.name = name; self.count = count }
}

public struct UsageAnalytics: Sendable, Equatable {
    public let desktopCredits: [DailyValue]   // 个人使用情况
    public let turnDates: [Date]              // x-axis for modelTurns
    public let modelTurns: [ModelSeries]      // 各模型轮次趋势
    public let skills: [SkillUsage]           // 技能使用

    public init(desktopCredits: [DailyValue], turnDates: [Date], modelTurns: [ModelSeries], skills: [SkillUsage]) {
        self.desktopCredits = desktopCredits
        self.turnDates = turnDates
        self.modelTurns = modelTurns
        self.skills = skills
    }
}

public enum QuotaFormatting {
    public static func sortedWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        windows.sorted {
            switch ($0.duration, $1.duration) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }

    public static func preferredWindow(for snapshot: QuotaSnapshot?) -> QuotaWindow? {
        guard let snapshot, snapshot.status == .ok || snapshot.status == .stale else { return nil }
        return sortedWindows(snapshot.windows).first
    }

    public static func percentText(_ value: Double) -> String {
        let fixed = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        return fixed.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + "%"
    }

    public static func periodLabel(for window: QuotaWindow) -> String? {
        guard let duration = window.duration, duration.isFinite, duration > 0 else { return nil }
        var remaining = Int(duration.rounded())
        let units = [(86_400, "d"), (3_600, "h"), (60, "m"), (1, "s")]
        var parts: [String] = []
        for (seconds, suffix) in units {
            let value = remaining / seconds
            if value > 0 { parts.append("\(value)\(suffix)") }
            remaining %= seconds
        }
        return parts.joined()
    }

    public static func menuTitle(for snapshot: QuotaSnapshot?, quotaLabel: String = "额度") -> String {
        guard let snapshot, snapshot.status == .ok || snapshot.status == .stale,
              !snapshot.windows.isEmpty else { return "\(quotaLabel) —" }
        return sortedWindows(snapshot.windows).map {
            "\(periodLabel(for: $0) ?? quotaLabel) \(percentText($0.remainingPercent))"
        }.joined(separator: " · ")
    }
}

public enum StatusClickRoute: Equatable {
    case detailWindow
    case contextMenu

    public static func forRightMouseUp(_ isRightMouseUp: Bool) -> Self {
        isRightMouseUp ? .contextMenu : .detailWindow
    }
}
