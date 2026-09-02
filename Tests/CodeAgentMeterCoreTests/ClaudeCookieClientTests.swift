import XCTest
@testable import CodeAgentMeterCore

final class ClaudeCookieClientTests: XCTestCase {
    func testNormalizeAcceptsBareValue() {
        XCTAssertEqual(
            ClaudeCookieClient.normalizeSessionKey("sk-ant-sid01-abc123"),
            "sk-ant-sid01-abc123"
        )
    }

    func testNormalizeAcceptsBareValueWithWhitespace() {
        XCTAssertEqual(
            ClaudeCookieClient.normalizeSessionKey("  sk-ant-sid01-abc123  \n"),
            "sk-ant-sid01-abc123"
        )
    }

    func testNormalizeExtractsFromFullCookieHeader() {
        let header = "intercom-device-id=xyz; sessionKey=sk-ant-sid01-abc123; ajs_user_id=456"
        XCTAssertEqual(ClaudeCookieClient.normalizeSessionKey(header), "sk-ant-sid01-abc123")
    }

    func testNormalizeExtractsWhenSessionKeyIsLastCookie() {
        let header = "intercom-device-id=xyz; sessionKey=sk-ant-sid01-abc123"
        XCTAssertEqual(ClaudeCookieClient.normalizeSessionKey(header), "sk-ant-sid01-abc123")
    }
}
