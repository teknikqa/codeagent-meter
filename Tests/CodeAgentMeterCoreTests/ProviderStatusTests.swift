import XCTest
@testable import CodeAgentMeterCore

final class ProviderStatusTests: XCTestCase {
    func testParsesStatuspageSummary() {
        let json = #"{"page":{"name":"Claude"},"status":{"indicator":"minor","description":"Partially Degraded Service"}}"#
        let status = ProviderStatusClient.parse(Data(json.utf8))
        XCTAssertEqual(status, ProviderStatus(indicator: .minor, description: "Partially Degraded Service"))
        XCTAssertEqual(status?.isIncident, true)
    }

    func testRejectsUnexpectedShape() {
        XCTAssertNil(ProviderStatusClient.parse(Data("<html>".utf8)))
    }
}
