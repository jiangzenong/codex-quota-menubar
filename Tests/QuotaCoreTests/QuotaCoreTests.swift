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
        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot), "5h 72% · W 54%")
    }

    func testRightClickRoutesToContextMenu() {
        XCTAssertEqual(StatusClickRoute.forRightMouseUp(true), .contextMenu)
        XCTAssertEqual(StatusClickRoute.forRightMouseUp(false), .detailWindow)
    }
}
