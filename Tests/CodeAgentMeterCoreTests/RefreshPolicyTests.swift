import XCTest
@testable import CodeAgentMeterCore

final class RefreshPolicyTests: XCTestCase {
    func testAdaptiveIdlesAfterUnchangedStreak() {
        XCTAssertEqual(RefreshPolicy.interval(mode: .adaptive, failureStreak: 0, unchangedStreak: 0), 60)
        XCTAssertEqual(RefreshPolicy.interval(mode: .adaptive, failureStreak: 0, unchangedStreak: 5), 300)
    }

    func testFailuresBackOffInEveryModeUpToTheCap() {
        XCTAssertEqual(RefreshPolicy.interval(mode: .adaptive, failureStreak: 1, unchangedStreak: 0), 120)
        XCTAssertEqual(RefreshPolicy.interval(mode: .adaptive, failureStreak: 9, unchangedStreak: 0), 900)
        XCTAssertEqual(RefreshPolicy.interval(mode: .m30, failureStreak: 3, unchangedStreak: 0), 1800)
    }

    func testOldConfigWithoutNewFieldsStillLoadsAccounts() throws {
        let json = #"{"accounts":[],"refreshIntervalSeconds":60}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.refreshMode, .adaptive)
        XCTAssertTrue(config.notificationsEnabled)
    }
}
