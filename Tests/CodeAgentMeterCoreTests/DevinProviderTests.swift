import XCTest
@testable import CodeAgentMeterCore

final class DevinProviderTests: XCTestCase {
    func testMapsQuotaPlanToDailyAndWeekly() throws {
        let json = #"{"userStatus":{"email":"a@b.c","planStatus":{"planInfo":{"planName":"Free"},"dailyQuotaRemainingPercent":75,"weeklyQuotaRemainingPercent":40,"dailyQuotaResetAtUnix":"1789545600","weeklyQuotaResetAtUnix":"1789891200"}}}"#
        let snapshot = try DevinProvider.snapshot(from: Data(json.utf8))
        XCTAssertEqual(snapshot.percentUsed, 25)
        XCTAssertEqual(snapshot.weeklyPercentUsed, 60)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: 1789545600))
        XCTAssertEqual(snapshot.weeklyResetsAt, Date(timeIntervalSince1970: 1789891200))
        XCTAssertEqual(snapshot.primaryLabel, "Daily")
        XCTAssertEqual(snapshot.detailLabel, "a@b.c · Free")
    }

    func testMapsCreditPlanToMonthly() throws {
        let json = #"{"userStatus":{"planStatus":{"planInfo":{"planName":"Pro"},"planEnd":"2026-10-01T00:00:00.123Z","usedPromptCredits":12500,"availablePromptCredits":50000}}}"#
        let snapshot = try DevinProvider.snapshot(from: Data(json.utf8))
        XCTAssertEqual(snapshot.percentUsed, 25)
        XCTAssertEqual(snapshot.resetsAt, ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
        XCTAssertNil(snapshot.weeklyPercentUsed)
    }

    func testPlanWithoutUsageThrows() {
        XCTAssertThrowsError(try DevinProvider.snapshot(from: Data(#"{"userStatus":{"planStatus":{}}}"#.utf8)))
    }

    func testPrefersCLICredentialsWithTheirServer() {
        let toml = """
        windsurf_api_key = "devin-cli"
        api_server_url = "https://eu.windsurf.com/_route/api_server"
        devin_webapp_host = "app.devin.ai"
        """
        XCTAssertEqual(DevinProvider.credential(cliCredentials: toml, appAuthStatus: #"{"apiKey":"devin-app"}"#),
                       .init(apiKey: "devin-cli", serverURL: "https://eu.windsurf.com/_route/api_server"))
    }

    func testFallsBackToAppKeyWhenCLISignedOut() {
        XCTAssertEqual(DevinProvider.credential(cliCredentials: nil, appAuthStatus: #"{"apiKey":"devin-app"}"#),
                       .init(apiKey: "devin-app", serverURL: DevinProvider.defaultServerURL))
        XCTAssertEqual(DevinProvider.credential(cliCredentials: "devin_webapp_host = \"app.devin.ai\"", appAuthStatus: #"{"apiKey":"devin-app"}"#)?.apiKey, "devin-app")
        XCTAssertNil(DevinProvider.credential(cliCredentials: nil, appAuthStatus: #"{"apiKey":""}"#))
    }

    func testRequestTargetsServerWithMetadata() throws {
        let request = DevinProvider.request(for: .init(apiKey: "k", serverURL: "https://eu.windsurf.com/_route/api_server/"))
        XCTAssertEqual(request.url?.absoluteString, "https://eu.windsurf.com/_route/api_server/exa.seat_management_pb.SeatManagementService/GetUserStatus")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: [String: String]]
        XCTAssertEqual(body?["metadata"]?["apiKey"], "k")
        XCTAssertEqual(body?["metadata"]?["ideName"], "windsurf")
    }
}
