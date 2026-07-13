import XCTest
@testable import QuotaMenuBar
import QuotaCore

final class QuotaMenuBarTests: XCTestCase {
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
}
