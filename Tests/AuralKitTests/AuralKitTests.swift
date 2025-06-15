import XCTest
@testable import AuralKit

final class AuralKitTests: XCTestCase {
    func testAuralKitInitialization() {
        let auralKit = AuralKit()
        XCTAssertNotNil(auralKit)
    }
}