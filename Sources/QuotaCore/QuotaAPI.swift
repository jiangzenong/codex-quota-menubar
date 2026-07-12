import Foundation

public struct Credentials: Sendable {
    public let accessToken: String
    public let accountID: String?
}

public enum QuotaAPI {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let creditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    public static let analyticsBase = "https://chatgpt.com/backend-api/wham"

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

    // MARK: - Analytics

    /// 个人使用情况: daily Desktop App credits from the token-usage breakdown.
    public static func parseDesktopCredits(_ data: Data) throws -> [DailyValue] {
        let days = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return days.compactMap { day in
            guard let date = ymd(day["date"]) else { return nil }
            let surfaces = day["product_surface_usage_values"] as? [String: Any] ?? [:]
            return DailyValue(date: date, value: number(surfaces["desktop_app"]) ?? 0)
        }
    }

    /// 各模型轮次趋势: per-day turns for the top models, from workspace usage counts.
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
        for day in perDay { for (model, turns) in day { totals[model, default: 0] += turns } }
        let top = totals.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
        let series = top.map { model in ModelSeries(model: model, points: perDay.map { $0[model] ?? 0 }) }
        return (dates, series)
    }

    /// 技能使用: skill invocation counts aggregated across the range.
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

    public static func fetchAnalytics(days: Int = 30, now: Date = .now) async -> UsageAnalytics? {
        guard let credentials = try? CodexAuth.load() else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let end = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let range = "start_date=\(ymdString(start))&end_date=\(ymdString(end))&group_by=day"

        async let creditsData = get("\(analyticsBase)/usage/daily-token-usage-breakdown?\(range)", credentials)
        async let turnsData = get("\(analyticsBase)/analytics/daily-workspace-usage-counts?\(range)&workspace_user=true", credentials)
        async let skillsData = get("\(analyticsBase)/analytics/daily-skill-usage-metrics?\(range)&workspace_user=true&top_skill_limit=10", credentials)

        let desktopCredits = (try? await creditsData).flatMap { try? parseDesktopCredits($0) } ?? []
        let turns = (try? await turnsData).flatMap { try? parseModelTurns($0) } ?? (dates: [], series: [])
        let skills = (try? await skillsData).flatMap { try? parseSkills($0) } ?? []
        if desktopCredits.isEmpty && turns.series.isEmpty && skills.isEmpty { return nil }
        return UsageAnalytics(desktopCredits: desktopCredits, turnDates: turns.dates, modelTurns: turns.series, skills: skills)
    }

    private static func get(_ urlString: String, _ credentials: Credentials) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
        if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
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
