import Foundation

public enum DevinError: Error {
    /// Neither the Devin CLI, Devin app nor Windsurf has a usable login.
    case notSignedIn
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Devin (formerly Windsurf, formerly Codeium) usage via the
/// `GetUserStatus` call the Devin app makes, authenticating with the API key
/// the Devin CLI stores, or the Devin app's (or a pre-rename Windsurf
/// install's) when the CLI isn't signed in.
///
/// Read-only: every source is re-read on each fetch, so signing in again needs
/// no change here.
public struct DevinProvider: UsageProvider {
    public static let vendorID = "devin"
    public static let displayName = "Devin"

    static let defaultServerURL = "https://server.codeium.com"

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var cliCredentialsURL: URL { home.appendingPathComponent(".local/share/devin/credentials.toml") }
    private static func appDatabasePath(_ app: String) -> String {
        home.appendingPathComponent("Library/Application Support/\(app)/User/globalStorage/state.vscdb").path
    }
    private static let authStatusKey = "windsurfAuthStatus"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        guard let credential = Self.credential(
            cliCredentials: try? String(contentsOf: Self.cliCredentialsURL, encoding: .utf8),
            // Windsurf was renamed Devin, which migrates the Windsurf folder; the
            // Windsurf database only matters for installs that haven't updated.
            appAuthStatus: ["Devin", "Windsurf"].lazy.compactMap {
                CursorProvider.readValues(keys: [Self.authStatusKey], databasePath: Self.appDatabasePath($0))[Self.authStatusKey]
            }.first
        ) else { throw DevinError.notSignedIn }

        let (data, response) = try await urlSession.data(for: Self.request(for: credential))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 || status == 403 ? DevinError.notSignedIn : DevinError.requestFailed(status)
        }
        return try Self.snapshot(from: data)
    }

    // MARK: - Credentials

    struct Credential: Equatable {
        let apiKey: String
        let serverURL: String
    }

    /// Picks the Devin CLI's key (with the server it signed in against), then the
    /// app's. `cliCredentials` is `credentials.toml`; `appAuthStatus` is the
    /// app's `windsurfAuthStatus` JSON.
    // ponytail: app logins assume the default server; enterprise and EU app-only
    // installs need their `api_server_url` setting read if one ever uses this.
    static func credential(cliCredentials: String?, appAuthStatus: String?) -> Credential? {
        if let toml = cliCredentials.map(tomlStrings), let apiKey = toml["windsurf_api_key"], !apiKey.isEmpty {
            return Credential(apiKey: apiKey, serverURL: toml["api_server_url"] ?? defaultServerURL)
        }
        struct AuthStatus: Decodable { let apiKey: String? }
        if let apiKey = appAuthStatus.flatMap({ try? JSONDecoder().decode(AuthStatus.self, from: Data($0.utf8)) })?.apiKey,
           !apiKey.isEmpty {
            return Credential(apiKey: apiKey, serverURL: defaultServerURL)
        }
        return nil
    }

    /// Reads top-level `key = "value"` lines, which is all `credentials.toml` holds.
    static func tomlStrings(_ toml: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in toml.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[1].count >= 2, parts[1].hasPrefix("\""), parts[1].hasSuffix("\"") else { continue }
            values[parts[0]] = String(parts[1].dropFirst().dropLast())
        }
        return values
    }

    static func request(for credential: Credential) -> URLRequest {
        let base = credential.serverURL.hasSuffix("/") ? String(credential.serverURL.dropLast()) : credential.serverURL
        var request = URLRequest(url: URL(string: base + "/exa.seat_management_pb.SeatManagementService/GetUserStatus")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        // The server rejects metadata without an IDE name and versions (HTTP 400).
        let metadata = [
            "apiKey": credential.apiKey, "ideName": "windsurf", "ideVersion": "1.110.1",
            "extensionName": "windsurf", "extensionVersion": "3.10.23", "locale": "en",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["metadata": metadata])
        return request
    }

    // MARK: - Response

    /// Connect's JSON encodes 64-bit integers as strings and smaller ones as numbers.
    private struct Number: Decodable {
        let value: Double
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let double = try? container.decode(Double.self) {
                value = double
            } else if let parsed = Double(try container.decode(String.self)) {
                value = parsed
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a number")
            }
        }
    }

    private struct UserStatusResponse: Decodable {
        struct UserStatus: Decodable {
            let email: String?
            let planStatus: PlanStatus?
        }
        struct PlanStatus: Decodable {
            struct PlanInfo: Decodable { let planName: String? }
            let planInfo: PlanInfo?
            let planEnd: String?
            let dailyQuotaRemainingPercent: Number?
            let weeklyQuotaRemainingPercent: Number?
            let dailyQuotaResetAtUnix: Number?
            let weeklyQuotaResetAtUnix: Number?
            let acuConsumed: Number?
            let acuLimit: Number?
            let usedPromptCredits: Number?
            let availablePromptCredits: Number?
        }
        let userStatus: UserStatus?
    }

    /// Current Devin plans meter daily and weekly quotas, mapped to the primary
    /// ("Daily") and weekly bars. Older plans meter a monthly ACU or prompt-credit
    /// pool instead, mapped to a "Monthly" bar ending at the plan period.
    // ponytail: only the quota plan was verified live; the ACU and credit mappings
    // follow the proto field names.
    static func snapshot(from data: Data) throws -> UsageSnapshot {
        guard let status = try? JSONDecoder().decode(UserStatusResponse.self, from: data).userStatus,
              let plan = status.planStatus else {
            throw DevinError.decodingFailed
        }
        let detail = [status.email, plan.planInfo?.planName].compactMap { $0 }.joined(separator: " · ")
        let detailLabel = detail.isEmpty ? nil : detail
        func date(_ unix: Number?) -> Date? { unix.map { Date(timeIntervalSince1970: $0.value) } }

        if plan.dailyQuotaRemainingPercent != nil || plan.weeklyQuotaRemainingPercent != nil {
            return UsageSnapshot(
                percentUsed: plan.dailyQuotaRemainingPercent.map { 100 - $0.value },
                resetsAt: date(plan.dailyQuotaResetAtUnix),
                weeklyPercentUsed: plan.weeklyQuotaRemainingPercent.map { 100 - $0.value },
                weeklyResetsAt: date(plan.weeklyQuotaResetAtUnix),
                detailLabel: detailLabel,
                primaryLabel: "Daily"
            )
        }
        let pool: (used: Double, limit: Double)? = if let limit = plan.acuLimit?.value, limit > 0 {
            (plan.acuConsumed?.value ?? 0, limit)
        } else if let limit = plan.availablePromptCredits?.value, limit > 0 {
            (plan.usedPromptCredits?.value ?? 0, limit)
        } else {
            nil
        }
        guard let pool else { throw DevinError.decodingFailed }
        let planEnd = plan.planEnd.flatMap { ISO8601DateFormatter().date(from: $0.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)) }
        return UsageSnapshot(
            percentUsed: pool.used / pool.limit * 100,
            resetsAt: planEnd,
            detailLabel: detailLabel,
            primaryLabel: "Monthly"
        )
    }
}
