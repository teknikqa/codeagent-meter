import XCTest
@testable import CodeAgentMeterCore

final class UsageHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPaceCompareWithEvenBurn() throws {
        // 2.5h into a 5h session: even use is 50%.
        let window = UsageWindow(key: "primary", label: "Session", percent: 70, resetsAt: now.addingTimeInterval(2.5 * 3600), length: 5 * 3600)
        let pace = try XCTUnwrap(Pace(window: window, now: now))
        XCTAssertEqual(pace.expectedPercent, 50, accuracy: 0.001)
        XCTAssertEqual(pace.status, .ahead)
        XCTAssertEqual(pace.summary, "20 pts ahead of even use")
    }

    func testNoPaceWithoutKnownWindow() {
        let window = UsageWindow(key: "primary", label: "Monthly", percent: 10, resetsAt: now.addingTimeInterval(100), length: nil)
        XCTAssertNil(Pace(window: window, now: now))
    }

    func testRecordSkipsUnchangedSamplesAndPrunesOldOnes() {
        var history = UsageHistory()
        let account = UUID()
        let snapshot = UsageSnapshot(percentUsed: 10, resetsAt: nil, detailLabel: nil)
        history.record(account: account, snapshot: snapshot, now: now)
        history.record(account: account, snapshot: snapshot, now: now.addingTimeInterval(30))
        XCTAssertEqual(history.samples.count, 1)
        history.record(account: account, snapshot: snapshot, now: now.addingTimeInterval(UsageHistory.retention + 1))
        XCTAssertEqual(history.samples.count, 1)
    }
}
