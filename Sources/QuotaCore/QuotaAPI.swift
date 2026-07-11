import Foundation

public struct Credentials: Sendable {
    public let accessToken: String
    public let accountID: String?
}

public enum QuotaAPI {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let creditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    public static func parseUsage(_ data: Data, now: Date = .now) throws -> QuotaSnapshot {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let limits = (root["rate_limit"] ?? root["rateLimit"] ?? root) as? [String: Any] ?? [:]
        let fiveHour = window(limits["primary_window"] ?? limits["primaryWindow"], expected: 18_000)
        guard let fiveHour else { return .unavailable(message: "Quota response is missing the 5h window.") }
        let weekly = window(limits["secondary_window"] ?? limits["secondaryWindow"], expected: 604_800)
        let plan = (root["plan_type"] ?? root["planType"] as Any?) as? String
        return .init(plan: plan?.uppercased(), fiveHour: fiveHour, weekly: weekly, resetCredits: nil, resetCreditExpirations: [], refreshedAt: now, status: .ok, message: nil)
    }

    public static func fetch() async -> QuotaSnapshot {
        do {
            let credentials = try CodexAuth.load()
            var request = URLRequest(url: usageURL)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
            request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
            if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .unavailable(message: "Quota service is unavailable.") }
            if response.statusCode == 401 || response.statusCode == 403 { return .init(plan: nil, fiveHour: nil, weekly: nil, resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .signedOut, message: "Codex login expired. Please sign in again.") }
            guard (200..<300).contains(response.statusCode) else { return .unavailable(message: "Quota service is temporarily unavailable.") }
            return try parseUsage(data)
        } catch { return .unavailable(message: "Please sign in to Codex Desktop, then refresh.") }
    }

    private static func window(_ value: Any?, expected: TimeInterval) -> QuotaWindow? {
        guard let value = value as? [String: Any] else { return nil }
        let used = number(value["used_percent"] ?? value["usedPercent"])
        let remaining = number(value["remaining_percent"] ?? value["remainingPercent"])
        guard let percent = remaining ?? used.map({ 100 - $0 }) else { return nil }
        let normalized = percent <= 1 ? percent * 100 : percent
        let reset = date(value["reset_at"] ?? value["resetAt"])
        let duration = number(value["limit_window_seconds"] ?? value["limitWindowSeconds"]) ?? expected
        return .init(remainingPercent: normalized, resetsAt: reset, duration: duration)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }
        if let string = value as? String { return ISO8601DateFormatter().date(from: string) }
        return nil
    }
}
