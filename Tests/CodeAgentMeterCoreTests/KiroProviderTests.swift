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
    private let fresh = "2027-02-01T00:00:00Z"
    private let euProfile = #"{"arn":"arn:aws:codewhisperer:eu-central-1:111122223333:profile/ORG","profile_name":"Org"}"#

    // MARK: kiro-cli

    func testCLIBuilderIDUsesDefaultProfileAndSSOHeader() {
        let values = ["kirocli:odic:token": #"{"access_token":"b","expires_at":"\#(fresh)","start_url":"https://view.awsapps.com/start"}"#]
        XCTAssertEqual(KiroProvider.cliCredential(values, now: now),
                       .init(accessToken: "b", profileArn: KiroProvider.builderIDProfileArn, tokenType: "SSO_OIDC"))
    }

    func testCLIIdentityCenterUsesStoredProfileRegion() {
        let token = #"{"access_token":"i","expires_at":"\#(fresh)","start_url":"https://acme.awsapps.com/start"}"#
        let credential = KiroProvider.cliCredential(["kirocli:odic:token": token, "api.codewhisperer.profile": euProfile], now: now)
        XCTAssertEqual(credential?.tokenType, "SSO_OIDC")
        XCTAssertEqual(credential?.region, "eu-central-1")
        // No default profile exists for an organization, so no stored profile means no credential.
        XCTAssertNil(KiroProvider.cliCredential(["kirocli:odic:token": token], now: now))
    }

    func testCLISocialUsesTokenProfileWithoutHeader() {
        let values = ["kirocli:social:token": #"{"access_token":"s","expires_at":"\#(fresh)","profile_arn":"arn:aws:codewhisperer:us-east-1:1:profile/S"}"#]
        XCTAssertEqual(KiroProvider.cliCredential(values, now: now),
                       .init(accessToken: "s", profileArn: "arn:aws:codewhisperer:us-east-1:1:profile/S", tokenType: nil))
    }

    func testCLIExternalIdPUsesExternalHeader() {
        let values = ["kirocli:external-idp:token": #"{"access_token":"e","expires_at":"\#(fresh)"}"#, "api.codewhisperer.profile": euProfile]
        XCTAssertEqual(KiroProvider.cliCredential(values, now: now)?.tokenType, "EXTERNAL_IDP")
    }

    func testCLIExpiredTokenIsSkipped() {
        let values = ["kirocli:odic:token": #"{"access_token":"b","expires_at":"2020-01-01T00:00:00Z"}"#]
        XCTAssertNil(KiroProvider.cliCredential(values, now: now))
    }

    // MARK: Kiro IDE

    func testIDEBuilderIDPrefersStoredProfile() {
        let ide = Data(#"{"accessToken":"ide","expiresAt":"2027-02-01T00:00:00.000Z","authMethod":"IdC","provider":"BuilderId"}"#.utf8)
        XCTAssertEqual(KiroProvider.ideCredential(token: ide, profile: Data(euProfile.utf8), now: now)?.region, "eu-central-1")
        XCTAssertEqual(KiroProvider.ideCredential(token: ide, profile: nil, now: now),
                       .init(accessToken: "ide", profileArn: KiroProvider.builderIDProfileArn, tokenType: "SSO_OIDC"))
    }

    func testIDESocialLoginWithoutAuthMethodUsesSocialDefaults() {
        let ide = Data(#"{"accessToken":"ide","provider":"Github"}"#.utf8)
        XCTAssertEqual(KiroProvider.ideCredential(token: ide, profile: nil, now: now),
                       .init(accessToken: "ide", profileArn: KiroProvider.socialProfileArn, tokenType: nil))
    }

    func testIDEEnterpriseLoginsNeedStoredProfile() {
        let idc = Data(#"{"accessToken":"ide","authMethod":"IdC","provider":"Enterprise"}"#.utf8)
        let external = Data(#"{"accessToken":"ide","authMethod":"external_idp","provider":"ExternalIdp"}"#.utf8)
        XCTAssertNil(KiroProvider.ideCredential(token: idc, profile: nil, now: now))
        XCTAssertEqual(KiroProvider.ideCredential(token: external, profile: Data(euProfile.utf8), now: now)?.tokenType, "EXTERNAL_IDP")
    }

    func testExpiredIDETokenReturnsNil() {
        let ide = Data(#"{"accessToken":"ide","expiresAt":"2020-01-01T00:00:00.000Z"}"#.utf8)
        XCTAssertNil(KiroProvider.ideCredential(token: ide, profile: nil, now: now))
    }

    // MARK: Request

    func testRequestTargetsProfileRegionWithTokenType() {
        let credential = KiroProvider.Credential(accessToken: "t", profileArn: "arn:aws:codewhisperer:eu-central-1:1:profile/P", tokenType: "EXTERNAL_IDP")
        let request = KiroProvider.request(for: credential)
        XCTAssertEqual(request.url?.host, "management.eu-central-1.kiro.dev")
        XCTAssertEqual(request.value(forHTTPHeaderField: "TokenType"), "EXTERNAL_IDP")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertNil(KiroProvider.request(for: .init(accessToken: "t", profileArn: KiroProvider.socialProfileArn, tokenType: nil)).value(forHTTPHeaderField: "TokenType"))
    }
}
