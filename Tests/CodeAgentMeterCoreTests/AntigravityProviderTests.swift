import XCTest
@testable import CodeAgentMeterCore

final class AntigravityProviderTests: XCTestCase {
    private let groupsJSON = """
    {"groups":[
      {"displayName":"Gemini Models","buckets":[
        {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.75,"resetTime":"2026-09-21T08:12:50Z"},
        {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.4,"resetTime":"2026-09-14T13:12:50Z"}]},
      {"displayName":"Claude and GPT models","buckets":[
        {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.1,"resetTime":"2026-09-21T08:12:50Z"},
        {"bucketId":"3p-5h","window":"5h","remainingFraction":1,"resetTime":"2026-09-14T13:12:50Z"}]}
    ]}
    """

    func testParsesRemoteQuotaSummaryIntoGroups() throws {
        let snapshot = try AntigravityProvider.snapshot(fromQuotaSummary: Data(groupsJSON.utf8), detailLabel: "Pro")
        XCTAssertEqual(snapshot.groups.map(\.name), ["Gemini", "Claude + GPT"])
        XCTAssertEqual(snapshot.groups[0].snapshot.percentUsed!, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.groups[0].snapshot.weeklyPercentUsed!, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.groups[1].snapshot.weeklyPercentUsed!, 90, accuracy: 0.001)
        // Headline tracks the busiest group per window.
        XCTAssertEqual(snapshot.percentUsed!, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.weeklyPercentUsed!, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.groups[0].snapshot.resetsAt, ISO8601DateFormatter().date(from: "2026-09-14T13:12:50Z"))
    }

    func testParsesLocalServerEnvelope() throws {
        let wrapped = "{\"response\":\(groupsJSON)}"
        let snapshot = try AntigravityProvider.snapshot(fromQuotaSummary: Data(wrapped.utf8), detailLabel: nil)
        XCTAssertEqual(snapshot.groups.count, 2)
    }

    func testEmptyGroupsThrow() {
        XCTAssertThrowsError(try AntigravityProvider.snapshot(fromQuotaSummary: Data("{\"groups\":[]}".utf8), detailLabel: nil))
    }

    func testParseDateAcceptsGoNanoseconds() {
        XCTAssertEqual(
            AntigravityProvider.parseDate("2026-09-14T10:11:12.123456789+10:00"),
            ISO8601DateFormatter().date(from: "2026-09-14T00:11:12Z")
        )
    }

    func testParsesLanguageServerProcessesAndPorts() {
        let ps = """
          27197 /Applications/Antigravity IDE.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --app_data_dir antigravity-ide --csrf_token abc-123 --random_port
          27200 /usr/bin/some_other --csrf_token nope
        """
        XCTAssertEqual(AntigravityLocalServerClient.parseServers(psOutput: ps), [.init(pid: "27197", csrfToken: "abc-123")])

        let lsof = """
        COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        language_ 27197 nick   12u  IPv4 0x1      0t0  TCP 127.0.0.1:57787 (LISTEN)
        language_ 27197 nick   13u  IPv4 0x2      0t0  TCP 127.0.0.1:57788 (LISTEN)
        """
        XCTAssertEqual(AntigravityLocalServerClient.parsePorts(lsofOutput: lsof), [57787, 57788])
    }

    func testDecodesGoKeyringLogin() throws {
        let json = #"{"token":{"access_token":"at","refresh_token":"rt","expiry":"2026-09-14T10:11:12.5Z"}}"#
        let stored = Data(("go-keyring-base64:" + Data(json.utf8).base64EncodedString()).utf8)
        let login = try XCTUnwrap(AntigravityOAuthClient.decodeAgyLogin(stored))
        XCTAssertEqual(login.accessToken, "at")
        XCTAssertEqual(login.refreshToken, "rt")
        XCTAssertNotNil(login.expiry)
        XCTAssertEqual(AntigravityOAuthClient.decodeAgyLogin(Data(#"{"access_token":"flat"}"#.utf8))?.accessToken, "flat")
    }

    func testFindsOAuthClientInBinary() {
        let secret = "GOCSPX-" + String(repeating: "a", count: 28)
        let binary = Data("\0\0xx12345-abc9.apps.googleusercontent.com\0junk\(secret)\0GOCSPX-short\0".utf8)
        let candidates = AntigravityOAuthClient.oauthClientCandidates(in: binary)
        XCTAssertEqual(candidates.map(\.id), ["12345-abc9.apps.googleusercontent.com"])
        XCTAssertEqual(candidates.map(\.secret), [secret])
    }
}
