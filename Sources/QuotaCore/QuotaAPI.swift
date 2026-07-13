import Foundation
import CoreFoundation
import OSLog

private let log = Logger(subsystem: "sh.lumos.CodexQuotaMenuBar", category: "API")

public struct Credentials: Sendable {
    public let accessToken: String
    public let accountID: String?
}

public enum QuotaAPI {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public static func parseUsage(_ data: Data, now: Date = .now) throws -> QuotaSnapshot {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let limits = (root["rate_limit"] ?? root["rateLimit"]) as? [String: Any] ?? [:]
        guard !limits.isEmpty else {
            return .unavailable(message: "Quota response missing rate_limit.")
        }
        let windows = QuotaFormatting.sortedWindows(limits.compactMap { id, value in
            window(id: id, value: value, now: now)
        })
        guard !windows.isEmpty else {
            return .unavailable(message: "Quota response contains no valid windows.")
        }
        let plan = (root["plan_type"] ?? root["planType"] as Any?) as? String
        return .init(plan: plan?.uppercased(), windows: windows,
                     resetCredits: nil, resetCreditExpirations: [], refreshedAt: now, status: .ok, message: nil)
    }

    public static func fetch() async -> QuotaSnapshot {
        do {
            let credentials = try CodexAuth.load()
            var request = URLRequest(url: usageURL)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
            request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .unavailable(message: "Quota service is unavailable.") }
            if response.statusCode == 401 { return .init(plan: nil, windows: [], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .signedOut, message: "Codex login expired. Please sign in again.") }
            if response.statusCode == 403 { return .init(plan: nil, windows: [], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .unavailable, message: "Access denied — VPN may be required.") }
            guard (200..<300).contains(response.statusCode) else {
                log.warning("Quota fetch HTTP \(response.statusCode)")
                return .unavailable(message: "Quota service is temporarily unavailable.")
            }
            return try parseUsage(data)
        } catch {
            log.error("Quota fetch failed: \(error.localizedDescription)")
            return .unavailable(message: "Please sign in to Codex Desktop, then refresh.")
        }
    }

    // MARK: - Analytics

    public static func parseDesktopCredits(_ data: Data) throws -> [DailyValue] {
        let days = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return days.compactMap { day in
            guard let date = ymd(day["date"]) else { return nil }
            let surfaces = day["product_surface_usage_values"] as? [String: Any] ?? [:]
            return DailyValue(date: date, value: number(surfaces["desktop_app"]) ?? 0)
        }
    }

    /// Parse per-model turns from daily-workspace-usage-counts (matches official dashboard).
    public static func parseModelTurns(_ data: Data, topN: Int = 4) throws -> (dates: [Date], series: [ModelSeries]) {
        let days = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        var dates: [Date] = []
        var perDay: [[String: Double]] = []
        for day in days {
            guard let date = ymd(day["date"]) else { continue }
            dates.append(date)
            var turns: [String: Double] = [:]
            for entry in (day["models"] as? [[String: Any]] ?? []) {
                if let model = entry["model"] as? String { turns[model] = number(entry["turns"]) ?? 0 }
            }
            perDay.append(turns)
        }
        var totals: [String: Double] = [:]
        for day in perDay { for (model, t) in day { totals[model, default: 0] += t } }
        let top = totals.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
        let series = top.map { model in ModelSeries(model: model, points: perDay.map { $0[model] ?? 0 }) }
        return (dates, series)
    }

    /// Parse per-model credits from daily-token-usage-breakdown (used for verification).
    public static func parseModelCredits(_ data: Data, topN: Int = 4) throws -> (dates: [Date], series: [ModelSeries]) {
        let days = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        var dates: [Date] = []
        var perDay: [[String: Double]] = []
        for day in days {
            guard let date = ymd(day["date"]) else { continue }
            dates.append(date)
            var credits: [String: Double] = [:]
            for entry in (day["models"] as? [[String: Any]] ?? []) {
                if let model = entry["model"] as? String { credits[model] = number(entry["credits"]) ?? 0 }
            }
            perDay.append(credits)
        }
        var totals: [String: Double] = [:]
        for day in perDay { for (model, c) in day { totals[model, default: 0] += c } }
        let top = totals.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
        let series = top.map { model in ModelSeries(model: model, points: perDay.map { $0[model] ?? 0 }) }
        return (dates, series)
    }

    public static func parseSkills(_ data: Data, topN: Int = 8) throws -> [SkillUsage] {
        let days = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for day in days {
            for skill in (day["skill_usage_overviews"] as? [[String: Any]] ?? []) {
                guard let key = skill["skill_name"] as? String else { continue }
                counts[key, default: 0] += Int(number(skill["invocation_counts"]) ?? 0)
                names[key] = (skill["display_name"] as? String) ?? key
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(topN).map { SkillUsage(name: names[$0.key] ?? $0.key, count: $0.value) }
    }

    public static func fetchAnalytics(days: Int = 7, now: Date = .now) async -> UsageAnalytics? {
        guard let credentials = try? CodexAuth.load() else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let end = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let range = "start_date=\(ymdString(start))&end_date=\(ymdString(end))&group_by=day"

        async let creditsData = get("\(analyticsBase)/usage/daily-token-usage-breakdown?\(range)", credentials)
        async let turnsData   = get("\(analyticsBase)/analytics/daily-workspace-usage-counts?\(range)&workspace_user=true", credentials)
        async let skillsData  = get("\(analyticsBase)/analytics/daily-skill-usage-metrics?\(range)&workspace_user=true&top_skill_limit=10", credentials)

        let desktopCredits = (try? await creditsData).flatMap { try? parseDesktopCredits($0) } ?? []
        let model = (try? await turnsData).flatMap { try? parseModelTurns($0) } ?? (dates: [], series: [])
        let skills = (try? await skillsData).flatMap { try? parseSkills($0) } ?? []
        if desktopCredits.isEmpty && model.series.isEmpty && skills.isEmpty { return nil }
        return UsageAnalytics(desktopCredits: desktopCredits, turnDates: model.dates, modelTurns: model.series, skills: skills)
    }

    private static let analyticsBase = "https://chatgpt.com/backend-api/wham"

    private static func get(_ urlString: String, _ credentials: Credentials) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            log.warning("Analytics fetch HTTP \(status) for \(urlString)")
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Helpers

    private static func window(id: String, value: Any, now: Date) -> QuotaWindow? {
        guard let value = value as? [String: Any] else { return nil }
        let remainingRaw = value["remaining_percent"] ?? value["remainingPercent"]
        let usedRaw = value["used_percent"] ?? value["usedPercent"]

        let remaining: Double
        if let remainingRaw, !(remainingRaw is NSNull) {
            guard let parsed = number(remainingRaw) else { return nil }
            remaining = parsed
        } else {
            guard let usedRaw, !(usedRaw is NSNull), let used = number(usedRaw) else { return nil }
            remaining = 100 - used
        }
        guard remaining.isFinite, (0...100).contains(remaining) else { return nil }

        let duration = number(value["limit_window_seconds"] ?? value["limitWindowSeconds"])
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let absoluteReset = date(value["reset_at"] ?? value["resetAt"])
        let resetAfter = number(value["reset_after_seconds"] ?? value["resetAfterSeconds"])
        let relativeReset = resetAfter.flatMap { $0.isFinite && $0 >= 0 ? now.addingTimeInterval($0) : nil }
        let reset = absoluteReset ?? relativeReset
        guard duration != nil || reset != nil else { return nil }

        return .init(id: id, remainingPercent: remaining, resetsAt: reset, duration: duration)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    /// Parse a Unix timestamp, auto-detecting seconds vs milliseconds.
    /// Strategy: if the value is more than 10× the current Unix timestamp, it's in milliseconds.
    private static func date(_ value: Any?) -> Date? {
        guard let num = number(value) else {
            if let string = value as? String { return ISO8601DateFormatter().date(from: string) }
            return nil
        }
        let seconds = num >= 10_000_000_000 ? num / 1000 : num
        return Date(timeIntervalSince1970: seconds)
    }

    private static func ymd(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }

    private static func ymdString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
