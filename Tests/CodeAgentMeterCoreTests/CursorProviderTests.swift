import XCTest
@testable import CodeAgentMeterCore

final class CursorProviderTests: XCTestCase {
    func testMapsPeriodUsageToMonthlySnapshot() throws {
        let usage = #"{"billingCycleEnd":"1789438349108","planUsage":{"autoPercentUsed":10,"apiPercentUsed":50,"totalPercentUsed":37.5}}"#
        let plan = #"{"planInfo":{"planName":"Pro"}}"#
        let snapshot = try CursorProvider.snapshot(usage: Data(usage.utf8), planInfo: Data(plan.utf8), email: "a@b.c")
        XCTAssertEqual(snapshot.percentUsed, 37.5)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: 1789438349.108))
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
        XCTAssertEqual(snapshot.detailLabel, "a@b.c · Pro")
    }

    func testMissingPercentThrows() {
        XCTAssertThrowsError(try CursorProvider.snapshot(usage: Data("{}".utf8), planInfo: nil, email: nil))
    }

    func testReadsValuesFromItemTable() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-\(UUID().uuidString).vscdb").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, "CREATE TABLE ItemTable (key TEXT UNIQUE, value BLOB); INSERT INTO ItemTable VALUES ('cursorAuth/cachedEmail', 'a@b.c');"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(CursorProvider.readValues(keys: ["cursorAuth/cachedEmail", "missing"], databasePath: path), ["cursorAuth/cachedEmail": "a@b.c"])
        XCTAssertEqual(CursorProvider.readValues(keys: ["x"], databasePath: path + ".nope"), [:])
    }
}
