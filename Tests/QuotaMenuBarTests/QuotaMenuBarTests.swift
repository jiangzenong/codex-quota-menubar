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

    private func snapshot(plan: String) -> QuotaSnapshot {
        .init(plan: plan, windows: [], resetCredits: nil, resetCreditExpirations: [],
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
    func testLatestRefreshWinsAndFailedAnalyticsClearsOldData() async {
        let controller = QuotaFetchController()
        let oldAnalytics = UsageAnalytics(desktopCredits: [], turnDates: [], modelTurns: [], skills: [])
        let model = QuotaModel(fetchQuota: { await controller.fetch() }, fetchAnalytics: { nil })
        model.analytics = oldAnalytics

        model.refresh()
        while await controller.count() < 1 { await Task.yield() }
        model.refresh()
        while await controller.count() < 2 { await Task.yield() }

        await controller.resume(1, with: snapshot(plan: "NEW"))
        await model.waitForRefreshForTesting()
        await controller.resume(0, with: snapshot(plan: "OLD"))
        await Task.yield()

        XCTAssertEqual(model.snapshot?.plan, "NEW")
        XCTAssertNil(model.analytics)
        XCTAssertFalse(model.isRefreshing)
    }
}
