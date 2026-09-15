import XCTest
@testable import CodeAgentMeterCore

final class OpenRouterProviderTests: XCTestCase {
    func testKeyWithCapUsesCapForBar() throws {
        let key = #"{"data":{"limit":100,"limit_remaining":74.5,"limit_reset":"monthly","usage":25.5,"usage_daily":1.25,"usage_monthly":25.5,"is_management_key":false}}"#
        let snapshot = try OpenRouterProvider.snapshot(key: Data(key.utf8), credits: nil)
        XCTAssertEqual(snapshot.percentUsed, 25.5)
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
        XCTAssertEqual(snapshot.detailLabel, "$1.25 today · $25.50 this month")
    }

    func testManagementKeyWithoutCapUsesCredits() throws {
        let key = #"{"data":{"limit":null,"limit_remaining":null,"limit_reset":null,"usage_daily":0,"usage_monthly":3.1,"is_management_key":true}}"#
        let credits = #"{"data":{"total_credits":5,"total_usage":3.1}}"#
        let snapshot = try OpenRouterProvider.snapshot(key: Data(key.utf8), credits: Data(credits.utf8))
        XCTAssertEqual(snapshot.percentUsed ?? 0, 62, accuracy: 0.001)
        XCTAssertEqual(snapshot.primaryLabel, "Credits")
        XCTAssertEqual(snapshot.detailLabel, "$1.90 balance · $0.00 today · $3.10 this month")
    }

    func testKeyWithoutCapOrCreditsShowsSpendOnly() throws {
        let key = #"{"data":{"limit":null,"usage_daily":0.5,"usage_monthly":2}}"#
        let snapshot = try OpenRouterProvider.snapshot(key: Data(key.utf8), credits: nil)
        XCTAssertNil(snapshot.percentUsed)
        XCTAssertEqual(snapshot.detailLabel, "$0.50 today · $2.00 this month")
    }

    func testMalformedKeyResponseThrows() {
        XCTAssertThrowsError(try OpenRouterProvider.snapshot(key: Data("{}".utf8), credits: nil))
    }

    func testNormalizesPastedHeader() {
        XCTAssertEqual(OpenRouterProvider.normalizeKey("  Authorization: Bearer sk-or-v1-abc \n"), "sk-or-v1-abc")
        XCTAssertEqual(OpenRouterProvider.normalizeKey("sk-or-v1-abc"), "sk-or-v1-abc")
    }
}
