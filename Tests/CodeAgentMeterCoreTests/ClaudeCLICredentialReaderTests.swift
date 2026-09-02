import XCTest
@testable import CodeAgentMeterCore

final class ClaudeCLICredentialReaderTests: XCTestCase {
    func testDecodesVerifiedCredentialsFileShape() throws {
        // Shape confirmed against a real Claude Code CLI Keychain item: a
        // top-level `claudeAiOauth` object, alongside unrelated `mcpOAuth`
        // entries this app should ignore.
        let json = """
        {
            "mcpOAuth": {
                "someServer|abc123": {
                    "serverName": "some-server",
                    "accessToken": "unrelated-token"
                }
            },
            "claudeAiOauth": {
                "accessToken": "access-123",
                "refreshToken": "refresh-456",
                "expiresAt": 1000,
                "refreshTokenExpiresAt": 2000,
                "scopes": ["a", "b"],
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max"
            }
        }
        """
        let credentials = try ClaudeCLICredentialReader.decode(Data(json.utf8))

        XCTAssertEqual(credentials.accessToken, "access-123")
        XCTAssertEqual(credentials.refreshToken, "refresh-456")
        // expiresAt is epoch milliseconds on the wire.
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1))
    }

    func testDecodeToleratesMissingRefreshToken() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "access-only", "expiresAt": 5000 } }
        """
        let credentials = try ClaudeCLICredentialReader.decode(Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "access-only")
        XCTAssertNil(credentials.refreshToken)
    }

    func testDecodeThrowsMalformedDataForUnexpectedShape() {
        let json = "{ \"somethingElse\": true }"
        XCTAssertThrowsError(try ClaudeCLICredentialReader.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ClaudeCLICredentialError, .malformedData)
        }
    }

    func testDecodeThrowsMalformedDataForInvalidJSON() {
        XCTAssertThrowsError(try ClaudeCLICredentialReader.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ClaudeCLICredentialError, .malformedData)
        }
    }
}
