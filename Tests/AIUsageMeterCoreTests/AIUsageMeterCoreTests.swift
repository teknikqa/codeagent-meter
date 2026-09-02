import XCTest
@testable import AIUsageMeterCore

final class AIUsageMeterCoreTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(AIUsageMeterCore.version.isEmpty)
    }
}
