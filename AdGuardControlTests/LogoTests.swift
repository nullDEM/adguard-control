import XCTest
import SwiftUI
@testable import AdGuardControl

final class LogoTests: XCTestCase {
    func testLogoGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let path = LogoShape().path(in: rect)
        // Siatka znaku: środek tarczy = (128, 129).
        XCTAssertTrue(path.contains(CGPoint(x: 128, y: 60), eoFill: true), "korpus tarczy jest pełny")
        XCTAssertFalse(path.contains(CGPoint(x: 110, y: 122), eoFill: true), "pigułka jest otworem")
        XCTAssertTrue(path.contains(CGPoint(x: 152, y: 122), eoFill: true), "gałka jest pełna")
        XCTAssertFalse(path.contains(CGPoint(x: 10, y: 10), eoFill: true))
        let box = path.boundingRect
        XCTAssertEqual(box.minX, 40, accuracy: 0.5)
        XCTAssertEqual(box.maxX, 216, accuracy: 0.5)
        XCTAssertEqual(box.midX, 128, accuracy: 0.5)
    }
}
