import Foundation

public enum QuotaStatus: Sendable, Equatable {
    case ok
    case stale
    case unavailable
    case signedOut
}

public struct QuotaWindow: Sendable, Equatable {
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let duration: TimeInterval

    public init(remainingPercent: Double, resetsAt: Date?, duration: TimeInterval) {
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.resetsAt = resetsAt
        self.duration = duration
    }
}

public struct QuotaSnapshot: Sendable, Equatable {
    public let plan: String?
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let resetCredits: Int?
    public let resetCreditExpirations: [Date]
    public let refreshedAt: Date
    public let status: QuotaStatus
    public let message: String?

    public init(plan: String?, fiveHour: QuotaWindow?, weekly: QuotaWindow?, resetCredits: Int?, resetCreditExpirations: [Date], refreshedAt: Date, status: QuotaStatus, message: String?) {
        self.plan = plan
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCredits = resetCredits
        self.resetCreditExpirations = resetCreditExpirations
        self.refreshedAt = refreshedAt
        self.status = status
        self.message = message
    }

    public static func unavailable(message: String) -> Self {
        .init(plan: nil, fiveHour: nil, weekly: nil, resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .unavailable, message: message)
    }
}

public enum QuotaFormatting {
    public static func menuTitle(for snapshot: QuotaSnapshot?) -> String {
        guard let snapshot, snapshot.status == .ok || snapshot.status == .stale,
              let fiveHour = snapshot.fiveHour?.remainingPercent else { return "5h — · W —" }
        let weekly = snapshot.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        return "5h \(Int(fiveHour.rounded()))% · W \(weekly)"
    }
}
