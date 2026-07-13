import XCTest
@testable import QuotaCore

final class QuotaCoreTests: XCTestCase {
    func testUnavailableSnapshotContainsNoQuotaValues() {
        let snapshot = QuotaSnapshot.unavailable(message: "Quota response contains no valid windows.")

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testParsesAndSortsHistoricalDualWindows() throws {
        let json = #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":26,"reset_at":1738300000,"limit_window_seconds":18000},"secondary_window":{"remaining_percent":0.6,"reset_at":1738900000,"limit_window_seconds":604800}}}"#

        let snapshot = try QuotaAPI.parseUsage(Data(json.utf8), now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshot.plan, "PRO")
        XCTAssertEqual(snapshot.windows.map(\.id), ["primary_window", "secondary_window"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [74, 0.6])
    }

    func testFormatsAndSortsDynamicQuotaWindows() {
        let snapshot = QuotaSnapshot(plan: nil, windows: [
            .init(id: "primary_window", remainingPercent: 34, resetsAt: nil, duration: 604_800),
            .init(id: "secondary_window", remainingPercent: 99, resetsAt: nil, duration: 18_000),
        ], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .ok, message: nil)

        XCTAssertEqual(QuotaFormatting.sortedWindows(snapshot.windows).map(\.id), ["secondary_window", "primary_window"])
        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot), "5h 99% · 7d 34%")
        XCTAssertEqual(QuotaFormatting.preferredWindow(for: snapshot)?.id, "secondary_window")
    }

    func testStaleMenuTitleUsesQuotaWithoutSuffix() {
        let snapshot = QuotaSnapshot(plan: nil, windows: [
            .init(id: "primary_window", remainingPercent: 75, resetsAt: nil, duration: 18_000),
        ], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .stale, message: "Offline")

        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot), "5h 75%")
    }

    func testMenuTitleDistinguishesLoadingUnavailableAndSignedOut() {
        let signedOut = QuotaSnapshot(plan: nil, windows: [], resetCredits: nil, resetCreditExpirations: [],
                                      refreshedAt: .now, status: .signedOut, message: nil)

        XCTAssertEqual(QuotaFormatting.menuTitle(for: nil), "数据加载中...")
        XCTAssertEqual(QuotaFormatting.menuTitle(for: .unavailable(message: "Offline")), "数据暂不可用")
        XCTAssertEqual(QuotaFormatting.menuTitle(for: signedOut), "请登录 Codex")
    }

    func testFormatsFractionalPercentWithoutScaling() {
        XCTAssertEqual(QuotaFormatting.percentText(0.6), "0.6%")
        XCTAssertEqual(QuotaFormatting.percentText(81.25), "81.25%")
    }

    func testFormatsCompositeWindowDurationWithoutRounding() {
        XCTAssertEqual(QuotaFormatting.periodLabel(for: .init(id: "a", remainingPercent: 50, resetsAt: nil, duration: 90)), "1m30s")
        XCTAssertEqual(QuotaFormatting.periodLabel(for: .init(id: "b", remainingPercent: 50, resetsAt: nil, duration: 90_000)), "1d1h")
    }

    func testUnknownDurationDoesNotInventAWindowLabel() {
        let window = QuotaWindow(id: "custom_window", remainingPercent: 81.25, resetsAt: nil, duration: nil)
        let snapshot = QuotaSnapshot(plan: nil, windows: [window], resetCredits: nil, resetCreditExpirations: [], refreshedAt: .now, status: .ok, message: nil)

        XCTAssertNil(QuotaFormatting.periodLabel(for: window))
        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot), "额度 81.25%")
        XCTAssertEqual(QuotaFormatting.menuTitle(for: snapshot, quotaLabel: "Quota"), "Quota 81.25%")
        XCTAssertEqual(QuotaFormatting.menuTitle(for: nil), "数据加载中...")
    }

    func testParsesSingleWeeklyWindowFromPrimarySlot() throws {
        let json = #"{"plan_type":"pro","rate_limit":{"allowed":true,"primary_window":{"used_percent":2,"limit_window_seconds":604800,"reset_at":1784525128},"secondary_window":null}}"#
        let snapshot = try QuotaAPI.parseUsage(Data(json.utf8), now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.windows, [
            .init(id: "primary_window", remainingPercent: 98, resetsAt: Date(timeIntervalSince1970: 1_784_525_128), duration: 604_800),
        ])
    }

    func testParsesSecondaryOnlyWindow() throws {
        let json = #"{"rate_limit":{"primary_window":null,"secondary_window":{"remaining_percent":70,"limit_window_seconds":604800,"reset_at":1738900000}}}"#
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(json.utf8)).windows.map(\.id), ["secondary_window"])
    }

    func testDiscoversRenamedAndThirdWindows() throws {
        let json = #"{"rate_limit":{"tertiary_window":{"remaining_percent":44,"limit_window_seconds":86400,"reset_at":1738300000},"secondary_window":{"remaining_percent":70,"limit_window_seconds":604800,"reset_at":1738900000}}}"#
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(json.utf8)).windows.map(\.id), ["tertiary_window", "secondary_window"])
    }

    func testUsesResetAfterSecondsWhenAbsoluteResetIsInvalid() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let json = #"{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000,"reset_at":"invalid","reset_after_seconds":300}}}"#
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(json.utf8), now: now).windows[0].resetsAt, Date(timeIntervalSince1970: 1_300))
    }

    func testParsesMillisecondAndISOResetTimes() throws {
        let milliseconds = #"{"rate_limit":{"a":{"used_percent":10,"limit_window_seconds":60,"reset_at":1738300000000}}}"#
        let iso = #"{"rate_limit":{"b":{"used_percent":10,"limit_window_seconds":60,"reset_at":"2026-07-20T05:00:00Z"}}}"#

        XCTAssertEqual(try QuotaAPI.parseUsage(Data(milliseconds.utf8)).windows[0].resetsAt, Date(timeIntervalSince1970: 1_738_300_000))
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(iso.utf8)).windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-07-20T05:00:00Z"))
    }

    func testRejectsOutOfRangeWindowWithoutClamping() throws {
        let json = #"{"rate_limit":{"primary_window":{"remaining_percent":101,"limit_window_seconds":18000,"reset_at":1738300000}}}"#
        let snapshot = try QuotaAPI.parseUsage(Data(json.utf8))

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testRejectsBooleanQuotaNumbers() throws {
        let json = #"{"rate_limit":{"primary_window":{"remaining_percent":true,"limit_window_seconds":18000}}}"#
        let snapshot = try QuotaAPI.parseUsage(Data(json.utf8))

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testPrefersRemainingPercentAndAcceptsBoundaryValues() throws {
        let json = #"{"rate_limit":{"empty":{"remaining_percent":0,"used_percent":1,"limit_window_seconds":60},"full":{"remaining_percent":100,"used_percent":99,"limit_window_seconds":120}}}"#
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(json.utf8)).windows.map(\.remainingPercent), [0, 100])
    }

    func testKeepsValidWindowWhenResetTimeIsUnknown() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000}}}"#
        let window = try QuotaAPI.parseUsage(Data(json.utf8)).windows[0]

        XCTAssertEqual(window.remainingPercent, 75)
        XCTAssertNil(window.resetsAt)
    }

    func testNewParseDoesNotRetainAWindowMissingFromNewResponse() throws {
        let first = #"{"rate_limit":{"short":{"used_percent":10,"limit_window_seconds":18000},"long":{"used_percent":20,"limit_window_seconds":604800}}}"#
        let second = #"{"rate_limit":{"long":{"used_percent":30,"limit_window_seconds":604800}}}"#

        XCTAssertEqual(try QuotaAPI.parseUsage(Data(first.utf8)).windows.count, 2)
        XCTAssertEqual(try QuotaAPI.parseUsage(Data(second.utf8)).windows.map(\.id), ["long"])
    }

    func testStatusClicksRouteToPanelAndContextMenu() {
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
