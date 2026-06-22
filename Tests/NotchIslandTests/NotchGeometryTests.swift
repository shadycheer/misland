@testable import NotchIsland
import XCTest

final class NotchGeometryTests: XCTestCase {

    func test_notchDisplay_computesCenteredFrameUnderNotch() {
        // screen 1512 wide; notch 200 wide centered; notch 38 tall.
        let g = NotchGeometry.layout(
            screenWidth: 1512, screenTop: 982,
            notchWidth: 200, notchHeight: 38,
            collapsedSize: CGSize(width: 220, height: 32)
        )
        XCTAssertTrue(g.hasNotch)
        // collapsed pill centered horizontally
        XCTAssertEqual(g.collapsedFrame.midX, 756, accuracy: 0.5)
        // sits just under the notch top edge
        XCTAssertEqual(g.collapsedFrame.maxY, 982, accuracy: 0.5)
    }

    func test_noNotch_fallsBackToFloatingCenteredPill() {
        let g = NotchGeometry.layout(
            screenWidth: 1920, screenTop: 1080,
            notchWidth: 0, notchHeight: 0,
            collapsedSize: CGSize(width: 220, height: 32)
        )
        XCTAssertFalse(g.hasNotch)
        XCTAssertEqual(g.collapsedFrame.midX, 960, accuracy: 0.5)
        XCTAssertEqual(g.collapsedFrame.maxY, 1080, accuracy: 0.5)
    }
}
