import XCTest
@testable import CodeAgentMeterCore

final class CodexProviderTests: XCTestCase {
    func testWeeklyOnlyPrimaryWindowMapsToWeekly() throws {
        let json = """
        {"email":"a@b.c","plan_type":"plus","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_at":1789894270},"secondary_window":null}}
        """
        let snapshot = try CodexProvider.snapshot(from: Data(json.utf8))
        XCTAssertNil(snapshot.percentUsed)
        XCTAssertEqual(snapshot.weeklyPercentUsed, 4)
        XCTAssertEqual(snapshot.weeklyResetsAt, Date(timeIntervalSince1970: 1789894270))
        XCTAssertEqual(snapshot.detailLabel, "a@b.c · plus")
    }

    func testSessionAndWeeklyWindows() throws {
        let json = """
        {"rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000,"reset_at":100},"secondary_window":{"used_percent":12,"limit_window_seconds":604800,"reset_at":200}}}
        """
        let snapshot = try CodexProvider.snapshot(from: Data(json.utf8))
        XCTAssertEqual(snapshot.percentUsed, 30)
        XCTAssertEqual(snapshot.weeklyPercentUsed, 12)
        XCTAssertNil(snapshot.detailLabel)
    }
}
