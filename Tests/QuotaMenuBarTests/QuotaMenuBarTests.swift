import XCTest
@testable import QuotaMenuBar
import QuotaCore

final class QuotaMenuBarTests: XCTestCase {
    actor QuotaFetchController {
        private var continuations: [CheckedContinuation<QuotaSnapshot, Never>] = []

        func fetch() async -> QuotaSnapshot {
            await withCheckedContinuation { continuations.append($0) }
        }

        func count() -> Int { continuations.count }

        func resume(_ index: Int, with snapshot: QuotaSnapshot) {
            continuations[index].resume(returning: snapshot)
        }
    }

    actor AnalyticsFetchController {
        private var continuations: [CheckedContinuation<UsageAnalytics?, Never>] = []

        func fetch() async -> UsageAnalytics? {
            await withCheckedContinuation { continuations.append($0) }
        }

        func count() -> Int { continuations.count }

        func resume(_ index: Int, with analytics: UsageAnalytics?) {
            continuations[index].resume(returning: analytics)
        }
    }

    private func snapshot(plan: String) -> QuotaSnapshot {
        .init(plan: plan, windows: [
            .init(id: "primary_window", remainingPercent: 75, resetsAt: nil, duration: 18_000),
        ], resetCredits: nil, resetCreditExpirations: [],
              refreshedAt: .now, status: .ok, message: nil)
    }

    func testModelChartHoverIndexRequiresAtLeastTwoPoints() {
        XCTAssertNil(modelChartHoverIndex(pointCount: 0, hoverX: 10, width: 100))
        XCTAssertNil(modelChartHoverIndex(pointCount: 1, hoverX: 10, width: 100))
    }

    func testModelChartHoverIndexClampsToValidRange() {
        XCTAssertEqual(modelChartHoverIndex(pointCount: 3, hoverX: -10, width: 100), 0)
        XCTAssertEqual(modelChartHoverIndex(pointCount: 3, hoverX: 110, width: 100), 2)
    }

    func testMissingPlanUsesNeutralLocalizedText() {
        XCTAssertEqual(displayPlanName(nil, locale: .zh), "套餐 —")
        XCTAssertEqual(displayPlanName("", locale: .en), "Plan —")
        XCTAssertEqual(displayPlanName("TEAM", locale: .en), "TEAM")
    }

    @MainActor
    func testEnsureDetailPanelCreatesPanelIdempotently() {
        let delegate = AppDelegate()
        XCTAssertNil(delegate.detailPanel)

        delegate.ensureDetailPanel()
        let first = delegate.detailPanel
        delegate.ensureDetailPanel()

        XCTAssertNotNil(first)
        XCTAssertTrue(first === delegate.detailPanel)
    }

    @MainActor
    func testFailedAnalyticsKeepsOldData() async {
        let oldAnalytics = UsageAnalytics(desktopCredits: [], turnDates: [], modelTurns: [], skills: [])
        let model = QuotaModel(fetchQuota: { self.snapshot(plan: "PRO") }, fetchAnalytics: { nil })
        model.analytics = oldAnalytics

        model.refresh()
        await model.waitForRefreshForTesting()

        XCTAssertEqual(model.analytics, oldAnalytics)
    }

    @MainActor
    func testRepeatedRefreshWhileInFlightUsesSingleRequest() async {
        let controller = QuotaFetchController()
        let model = QuotaModel(fetchQuota: { await controller.fetch() }, fetchAnalytics: { nil })

        model.refresh()
        while await controller.count() < 1 { await Task.yield() }
        model.refresh()
        for _ in 0..<100 { await Task.yield() }

        let requestCount = await controller.count()
        XCTAssertEqual(requestCount, 1)
        for index in 0..<requestCount {
            await controller.resume(index, with: snapshot(plan: "PRO"))
        }
        await model.waitForRefreshForTesting()

        XCTAssertEqual(model.snapshot?.plan, "PRO")
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testQuotaPublishesBeforeAnalyticsCompletes() async {
        let quota = QuotaFetchController()
        let analytics = AnalyticsFetchController()
        let model = QuotaModel(fetchQuota: { await quota.fetch() }, fetchAnalytics: { await analytics.fetch() })

        model.refresh()
        while true {
            let quotaCount = await quota.count()
            let analyticsCount = await analytics.count()
            if quotaCount >= 1, analyticsCount >= 1 { break }
            await Task.yield()
        }
        await quota.resume(0, with: snapshot(plan: "PRO"))
        for _ in 0..<100 where model.snapshot == nil { await Task.yield() }

        XCTAssertEqual(model.snapshot?.plan, "PRO")
        XCTAssertTrue(model.isRefreshing)

        await analytics.resume(0, with: nil)
        await model.waitForRefreshForTesting()
    }

    @MainActor
    func testUnavailableRefreshRetainsLastSuccessfulQuotaAsStale() async {
        let quota = QuotaFetchController()
        let model = QuotaModel(fetchQuota: { await quota.fetch() }, fetchAnalytics: { nil })

        model.refresh()
        while await quota.count() < 1 { await Task.yield() }
        await quota.resume(0, with: snapshot(plan: "PRO"))
        await model.waitForRefreshForTesting()

        model.refresh()
        while await quota.count() < 2 { await Task.yield() }
        await quota.resume(1, with: .unavailable(message: "Network unavailable"))
        await model.waitForRefreshForTesting()

        XCTAssertEqual(model.snapshot?.plan, "PRO")
        XCTAssertEqual(model.snapshot?.status, .stale)
        XCTAssertEqual(model.snapshot?.message, "Network unavailable")
    }
}
