import XCTest
@testable import QuotaCore

final class QuotaCoreTests: XCTestCase {
    func testUnavailableSnapshotContainsNoQuotaValues() {
        let snapshot = QuotaSnapshot.unavailable(message: "Quota response is missing the 5h window.")

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.weekly)
    }

    func testParsesFiveHourAndWeeklyWindows() throws {
        let json = #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":26,"reset_at":1738300000,"limit_window_seconds":18000},"secondary_window":{"remaining_percent":0.6,"reset_at":1738900000,"limit_window_seconds":604800}}}"#

        let snapshot = try QuotaAPI.parseUsage(Data(json.utf8), now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshot.plan, "PRO")
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 74)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 60)
    }

    func testMenuTitleShowsBothRemainingWindows() {
        let snapshot = QuotaSnapshot(plan: nil, fiveHour: .init(remainingPercent: 72.4, resetsAt: nil, duration: 18_000), weekly: .init(remainingPercent: 54.4, resetsAt: nil, duration: 604_800), resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .ok, message: nil)
        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot), "5h 72% · 7d 54%")
    }

    func testRightClickRoutesToContextMenu() {
        XCTAssertEqual(StatusClickRoute.forRightMouseUp(true), .contextMenu)
        XCTAssertEqual(StatusClickRoute.forRightMouseUp(false), .detailWindow)
    }

    func testParsesDesktopCreditsPerDay() throws {
        let json = #"{"data":[{"date":"2026-06-13","product_surface_usage_values":{"desktop_app":0.0,"cli":1.0}},{"date":"2026-06-14","product_surface_usage_values":{"desktop_app":47.1}}]}"#
        let values = try QuotaAPI.parseDesktopCredits(Data(json.utf8))
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[1].value, 47.1, accuracy: 0.001)
    }

    func testParsesTopModelTurns() throws {
        let json = #"{"data":[{"date":"2026-06-15","models":[{"model":"gpt-5.5","turns":47},{"model":"gpt-5.4","turns":4}]},{"date":"2026-06-16","models":[{"model":"gpt-5.5","turns":10},{"model":"gpt-5.4","turns":90}]}]}"#
        let result = try QuotaAPI.parseModelTurns(Data(json.utf8), topN: 4)
        XCTAssertEqual(result.dates.count, 2)
        // gpt-5.4 has the larger total (94) so it sorts first.
        XCTAssertEqual(result.series.first?.model, "gpt-5.4")
        XCTAssertEqual(result.series.first?.points, [4, 90])
    }

    func testParsesAndAggregatesSkills() throws {
        let json = #"{"data":[{"date":"2026-06-15","skill_usage_overviews":[{"skill_name":"a","display_name":"Alpha","invocation_counts":5},{"skill_name":"b","display_name":"Beta","invocation_counts":2}]},{"date":"2026-06-16","skill_usage_overviews":[{"skill_name":"a","display_name":"Alpha","invocation_counts":3}]}]}"#
        let skills = try QuotaAPI.parseSkills(Data(json.utf8), topN: 8)
        XCTAssertEqual(skills.first?.name, "Alpha")
        XCTAssertEqual(skills.first?.count, 8)
    }
}
