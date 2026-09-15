import XCTest
@testable import CodeAgentMeterCore

final class KiroProviderTests: XCTestCase {
    func testMapsCreditsToMonthlySnapshotExcludingOverages() throws {
        let json = #"{"nextDateReset":1.7908128E9,"subscriptionInfo":{"subscriptionTitle":"KIRO PRO"},"usageBreakdownList":[{"resourceType":"CREDIT","currentUsageWithPrecision":1100.5,"currentOveragesWithPrecision":100.5,"usageLimitWithPrecision":1000.0}]}"#
        let snapshot = try KiroProvider.snapshot(from: Data(json.utf8))
        XCTAssertEqual(snapshot.percentUsed, 100)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: 1790812800))
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
        XCTAssertEqual(snapshot.detailLabel, "KIRO PRO · 1000 / 1000 credits")
    }

    func testMissingLimitThrows() {
        XCTAssertThrowsError(try KiroProvider.snapshot(from: Data(#"{"usageBreakdownList":[]}"#.utf8)))
    }
}
