import XCTest
@testable import CommitCore

final class InformativeThresholdsTests: XCTestCase {
    func testDefaultBoundariesKeepExistingMeaning() {
        let thresholds = InformativeThresholds()
        XCTAssertEqual(thresholds.category(forMissed: 0), .green)
        XCTAssertEqual(thresholds.category(forMissed: 1), .green)
        XCTAssertEqual(thresholds.category(forMissed: 2), .yellow)
        XCTAssertEqual(thresholds.category(forMissed: 3), .yellow)
        XCTAssertEqual(thresholds.category(forMissed: 4), .red)
    }

    func testCustomBoundaries() {
        let thresholds = InformativeThresholds(yellowStartsAt: 1, redStartsAt: 3)
        XCTAssertEqual(thresholds.category(forMissed: 0), .green)
        XCTAssertEqual(thresholds.category(forMissed: 1), .yellow)
        XCTAssertEqual(thresholds.category(forMissed: 2), .yellow)
        XCTAssertEqual(thresholds.category(forMissed: 3), .red)
    }

    func testInvalidStoredBoundariesAreNormalized() {
        let thresholds = InformativeThresholds(yellowStartsAt: 0, redStartsAt: 0)
        XCTAssertEqual(thresholds.yellowStartsAt, 1)
        XCTAssertEqual(thresholds.redStartsAt, 2)
    }
}
