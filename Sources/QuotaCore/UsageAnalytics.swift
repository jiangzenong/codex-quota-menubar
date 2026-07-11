import Foundation

public struct OfficialUsageEvent: Equatable, Sendable {
    public let date: String
    public let values: [String: Double]

    public static func parse(_ value: [String: Any]) -> Self? {
        guard let date = value["date"] as? String,
              let rawValues = value["product_surface_usage_values"] as? [String: Any] else { return nil }
        let values = rawValues.reduce(into: [String: Double]()) { result, entry in
            if let number = entry.value as? NSNumber { result[entry.key] = number.doubleValue }
        }
        guard !values.isEmpty else { return nil }
        return .init(date: date, values: values)
    }
}

public struct UsageAnalyticsSnapshot: Equatable, Sendable {
    public let events: [OfficialUsageEvent]
    public let isOfficial: Bool
    public static let unavailable = Self(events: [], isOfficial: false)
}
