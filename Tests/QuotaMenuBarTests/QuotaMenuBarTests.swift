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
    func testDetailAndOrbUseIndependentWindowLevels() {
        let detail = makeTransparentPanel(size: NSSize(width: 100, height: 100), role: .detail)
        let orb = makeTransparentPanel(size: NSSize(width: 50, height: 50), role: .orb)

        XCTAssertEqual(detail.level, .normal)
        XCTAssertFalse(detail.isFloatingPanel)
        XCTAssertEqual(orb.level, .floating)
        XCTAssertTrue(orb.isFloatingPanel)
    }

    @MainActor
    func testDetailAndOrbVisibilityAreIndependent() {
        let delegate = AppDelegate()
        defer {
            delegate.hideDetail()
            delegate.hideOrb()
        }

        delegate.showOrb()
        delegate.showDetail()
        XCTAssertEqual(delegate.detailPanel?.isVisible, true)
        XCTAssertEqual(delegate.orbPanel?.isVisible, true)

        delegate.hideDetail()
        XCTAssertEqual(delegate.detailPanel?.isVisible, false)
        XCTAssertEqual(delegate.orbPanel?.isVisible, true)

        delegate.showDetail()
        delegate.hideOrb()
        XCTAssertEqual(delegate.detailPanel?.isVisible, true)
        XCTAssertEqual(delegate.orbPanel?.isVisible, false)
    }

    @MainActor
    func testDetailToggleClosesAndReopensTheDetailPanel() {
        let delegate = AppDelegate()
        defer { delegate.hideDetail() }

        delegate.showDetail()
        delegate.togglePanel()
        XCTAssertEqual(delegate.detailPanel?.isVisible, false)

        delegate.togglePanel()
        XCTAssertEqual(delegate.detailPanel?.isVisible, true)
    }

    @MainActor
    func testDetailPanelReopensAtItsLastHiddenPosition() {
        let delegate = AppDelegate()
        defer { delegate.hideDetail() }

        delegate.showDetail()
        let initialOrigin = try! XCTUnwrap(delegate.detailPanel?.frame.origin)
        let expectedOrigin = NSPoint(x: initialOrigin.x + 20, y: initialOrigin.y)
        delegate.detailPanel?.setFrameOrigin(expectedOrigin)
        delegate.hideDetail()
        delegate.showDetail()

        XCTAssertEqual(delegate.detailPanel?.frame.origin, expectedOrigin)
    }

    @MainActor
    func testInitialSurfacesShowOrbWithoutOpeningDetail() {
        let delegate = AppDelegate()
        defer { delegate.hideOrb() }

        delegate.showInitialSurfaces()

        XCTAssertEqual(delegate.orbPanel?.isVisible, true)
        XCTAssertNotEqual(delegate.detailPanel?.isVisible, true)
    }

    func testOrbCloseTargetDoesNotRouteToDetail() {
        XCTAssertEqual(orbAction(forCloseButton: false), .toggleDetail)
        XCTAssertEqual(orbAction(forCloseButton: true), .closeOrb)
    }

    func testOrbCanvasLeavesRoomAroundTheCircle() {
        XCTAssertEqual(orbDiameter, 68)
        XCTAssertEqual(orbCanvasInset, 4)
        XCTAssertEqual(orbCanvasSize, 76)
    }

    func testOrbResetTextUsesActualWindowPeriodAndRemainingTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let weekly = QuotaWindow(id: "weekly", remainingPercent: 73, resetsAt: now.addingTimeInterval(221_400), duration: 604_800)
        let fiveHour = QuotaWindow(id: "short", remainingPercent: 73, resetsAt: now.addingTimeInterval(4_800), duration: 18_000)
        let unknownReset = QuotaWindow(id: "weekly", remainingPercent: 73, resetsAt: nil, duration: 604_800)

        XCTAssertEqual(orbResetText(for: weekly, now: now), "2d 13h")
        XCTAssertEqual(orbResetText(for: fiveHour, now: now), "1h 20m")
        XCTAssertNil(orbResetText(for: unknownReset, now: now))
    }

    func testOrbDragStartsOnlyAfterMovementExceedsThreshold() {
        XCTAssertFalse(isOrbDragMovement(NSPoint(x: 4, y: 4)))
        XCTAssertFalse(isOrbDragMovement(NSPoint(x: orbDragThreshold, y: 0)))
        XCTAssertTrue(isOrbDragMovement(NSPoint(x: orbDragThreshold + 0.1, y: 0)))
    }

    func testOrbTapTogglesDetailsUnlessDragging() {
        XCTAssertNil(orbTapAction(isDragging: true))
        XCTAssertEqual(orbTapAction(isDragging: false), .toggleDetail)
    }

    @MainActor
    func testOrbMenuContainsOnlyOrbActionsInCurrentLanguage() {
        XCTAssertEqual(
            makeOrbMenu(isZh: true, isDetailVisible: false).items.map(\.title),
            ["立即刷新", "显示窗口", "隐藏悬浮球"]
        )
        XCTAssertEqual(
            makeOrbMenu(isZh: false, isDetailVisible: true).items.map(\.title),
            ["Refresh Now", "Hide Window", "Hide Orb"]
        )
    }

    func testStatusPanelUsesMouseUpAndKeepsRightMouseUpForContextMenu() {
        XCTAssertTrue(statusItemActionEvents.contains(.leftMouseUp))
        XCTAssertFalse(statusItemActionEvents.contains(.leftMouseDown))
        XCTAssertTrue(statusItemActionEvents.contains(.rightMouseUp))
    }

    @MainActor
    func testApplicationMenuRegistersCommandQQuitItem() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()
        let selector = NSSelectorFromString("installApplicationMenu")

        guard delegate.responds(to: selector) else {
            XCTFail("Application menu installer is missing")
            return
        }
        delegate.perform(selector)

        let quitItem = app.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.keyEquivalent == "q" }
        XCTAssertEqual(quitItem?.keyEquivalentModifierMask, [.command])
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
    func testPresentingDetailDoesNotRequestRefresh() async {
        let controller = QuotaFetchController()
        let model = QuotaModel(fetchQuota: { await controller.fetch() }, fetchAnalytics: { nil })

        model.refresh(trigger: .detailPresentation)
        for _ in 0..<20 { await Task.yield() }

        let requestCount = await controller.count()
        XCTAssertEqual(requestCount, 0)
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
