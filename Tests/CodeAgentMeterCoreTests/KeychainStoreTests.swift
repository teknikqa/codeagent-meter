import XCTest
@testable import CodeAgentMeterCore

final class KeychainStoreTests: XCTestCase {
    // Unique per test instance so tests never collide with each other or with
    // real app data in the Keychain.
    private let service = "com.nickmathew.codeagent-meter.tests.\(UUID().uuidString)"

    func testWriteAndReadRoundTrip() throws {
        let store = KeychainStore(service: service)
        let data = Data("hello".utf8)

        try store.write(data: data, account: "test-account")
        defer { try? store.delete(account: "test-account") }

        XCTAssertEqual(try store.readData(account: "test-account"), data)
    }

    func testReadMissingItemThrowsItemNotFound() {
        let store = KeychainStore(service: service)
        XCTAssertThrowsError(try store.readData(account: "does-not-exist")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testWriteOverwritesExistingValue() throws {
        let store = KeychainStore(service: service)
        try store.write(data: Data("first".utf8), account: "acct")
        try store.write(data: Data("second".utf8), account: "acct")
        defer { try? store.delete(account: "acct") }

        XCTAssertEqual(String(data: try store.readData(account: "acct"), encoding: .utf8), "second")
    }

    func testDeleteMissingItemDoesNotThrow() {
        let store = KeychainStore(service: service)
        XCTAssertNoThrow(try store.delete(account: "never-existed"))
    }

    func testReadFirstDataIgnoresAccountAttribute() throws {
        let store = KeychainStore(service: service)
        let data = Data("first-match".utf8)
        try store.write(data: data, account: "some-account-name-we-dont-know")
        defer { try? store.delete(account: "some-account-name-we-dont-know") }

        XCTAssertEqual(try KeychainStore.readFirstData(service: service), data)
    }
}
