import XCTest
@testable import CodeAgentMeterCore

final class ThresholdTrackerTests: XCTestCase {
    private func window(_ percent: Double) -> [UsageWindow] {
        [UsageWindow(key: "primary", label: "Session", percent: percent, resetsAt: nil, length: nil)]
    }

    func testFiresOncePerCrossingAndRearmsAfterReset() {
        var tracker = ThresholdTracker()
        let account = UUID()
        XCTAssertTrue(tracker.evaluate(account: account, windows: window(90)).isEmpty, "first reading only seeds")
        XCTAssertTrue(tracker.evaluate(account: account, windows: window(95)).isEmpty)
        XCTAssertEqual(tracker.evaluate(account: account, windows: window(100)).map(\.threshold), [100])
        XCTAssertTrue(tracker.evaluate(account: account, windows: window(100)).isEmpty)
        XCTAssertTrue(tracker.evaluate(account: account, windows: window(5)).isEmpty, "window reset")
        XCTAssertEqual(tracker.evaluate(account: account, windows: window(82)).map(\.threshold), [80])
    }
}
