import XCTest
@testable import CodeAgentMeterCore

final class KiroProviderTests: XCTestCase {
    func testMapsCreditsToMonthlySnapshotExcludingOverages() throws {
        let json = #"{"nextDateReset":1.7908128E9,"subscriptionInfo":{"subscriptionTitle":"KIRO PRO"},"usageBreakdownList":[{"resourceType":"CREDIT","currentUsageWithPrecision":1100.5,"currentOveragesWithPrecision":100.5,"usageLimitWithPrecision":1000.0}]}"#
        let snapshot = try KiroProvider.snapshot(from: Data(json.utf8))
        XCTAssertEqual(snapshot.percentUsed, 100)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: 1790812800))
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
        XCTAssertEqual(snapshot.detailLabel, "KIRO PRO · 1000 / 1000 credits")
    }

    func testMissingLimitThrows() {
        XCTAssertThrowsError(try KiroProvider.snapshot(from: Data(#"{"usageBreakdownList":[]}"#.utf8)))
    }
}

final class KiroCredentialTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCLITokenUsesBuilderIDProfile() {
        let cli = Data(#"{"access_token":"cli","expires_at":"2027-02-01T00:00:00.000000Z","region":"us-east-1"}"#.utf8)
        XCTAssertEqual(KiroProvider.cliCredential(cli, now: now),
                       .init(accessToken: "cli", region: "us-east-1", profileArn: KiroProvider.builderIDProfileArn))
        XCTAssertNil(KiroProvider.cliCredential(cli, now: Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertNil(KiroProvider.cliCredential(nil, now: now))
    }

    func testIDETokenPrefersStoredProfile() {
        let ide = Data(#"{"accessToken":"ide","expiresAt":"2027-02-01T00:00:00.000Z","region":"eu-central-1","provider":"BuilderId"}"#.utf8)
        let profile = Data(#"{"arn":"arn:stored","name":"x"}"#.utf8)
        XCTAssertEqual(KiroProvider.ideCredential(token: ide, profile: profile, now: now),
                       .init(accessToken: "ide", region: "eu-central-1", profileArn: "arn:stored"))
    }

    func testSocialIDELoginWithoutProfileUsesSocialArn() {
        let ide = Data(#"{"accessToken":"ide","provider":"Github"}"#.utf8)
        XCTAssertEqual(KiroProvider.ideCredential(token: ide, profile: nil, now: now)?.profileArn, KiroProvider.socialProfileArn)
    }

    func testExpiredIDETokenReturnsNil() {
        let ide = Data(#"{"accessToken":"ide","expiresAt":"2020-01-01T00:00:00.000Z"}"#.utf8)
        XCTAssertNil(KiroProvider.ideCredential(token: ide, profile: nil, now: now))
    }
}
