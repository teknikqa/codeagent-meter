import Foundation

public enum KiroError: Error {
    /// Neither Kiro nor kiro-cli has a usable login.
    case notSignedIn
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Kiro's monthly credit usage via the control-plane API the Kiro IDE's
/// own usage dashboard calls, authenticating with kiro-cli's login, or the Kiro
/// IDE's when kiro-cli isn't installed or signed in.
///
/// Tokens are never refreshed here, since a refresh could rotate the refresh
/// token out from under the IDE or CLI. When kiro-cli's token has expired,
/// kiro-cli is run once so it refreshes its own token.
public struct KiroProvider: UsageProvider {
    public static let vendorID = "kiro"
    public static let displayName = "Kiro"

    private static let cliTimeoutSeconds: UInt64 = 20
    /// A GUI app doesn't inherit the login shell's PATH, so common install
    /// locations are appended.
    private static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin"]
        .map { ($0 as NSString).expandingTildeInPath }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var ideTokenURL: URL { home.appendingPathComponent(".aws/sso/cache/kiro-auth-token.json") }
    private static var ideProfileURL: URL {
        home.appendingPathComponent("Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json")
    }
    private static var cliDatabasePath: String {
        home.appendingPathComponent("Library/Application Support/kiro-cli/data.sqlite3").path
    }
    /// kiro-cli keeps one token per login type in `auth_kv`, each paired with the
    /// `TokenType` header Kiro sends for it (none for Google/GitHub).
    private static let cliTokenKeys: [(key: String, tokenType: String?)] = [
        ("kirocli:odic:token", "SSO_OIDC"),
        ("kirocli:social:token", nil),
        ("kirocli:external-idp:token", "EXTERNAL_IDP"),
    ]
    private static let cliProfileKey = "api.codewhisperer.profile"
    static let builderIDStartURL = "https://view.awsapps.com/start"

    /// The fixed profiles Kiro uses for non-enterprise logins, from the IDE's
    /// `ListAvailableProfiles` fallback map. Enterprise logins (IAM Identity
    /// Center, external IdP) have no default, so they need the profile the IDE
    /// or CLI stored after sign-in.
    static let builderIDProfileArn = "arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX"
    static let socialProfileArn = "arn:aws:codewhisperer:us-east-1:699475941385:profile/EHGA3GRVQMUK"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        var cliValues = Self.readCLIValues()
        var credential = Self.cliCredential(cliValues)
        if credential == nil, Self.cliTokenKeys.contains(where: { cliValues[$0.key] != nil }) {
            // ponytail: a dead CLI refresh token costs one CLI run per refresh before
            // falling back to the IDE; remember the failure if that gets slow.
            await Self.runCLIToRefreshToken()
            cliValues = Self.readCLIValues()
            credential = Self.cliCredential(cliValues)
        }
        guard let credential = credential ?? Self.ideCredential(
            token: try? Data(contentsOf: Self.ideTokenURL),
            profile: try? Data(contentsOf: Self.ideProfileURL)
        ) else { throw KiroError.notSignedIn }

        let (data, response) = try await urlSession.data(for: Self.request(for: credential))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 || status == 403 ? KiroError.notSignedIn : KiroError.requestFailed(status)
        }
        return try Self.snapshot(from: data)
    }

    static func request(for credential: Credential) -> URLRequest {
        var components = URLComponents(string: "https://management.\(credential.region).kiro.dev/Get-Usage-Limits")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: "AI_EDITOR"),
            URLQueryItem(name: "resourceType", value: "AGENTIC_REQUEST"),
            URLQueryItem(name: "profileArn", value: credential.profileArn),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tokenType = credential.tokenType {
            request.setValue(tokenType, forHTTPHeaderField: "TokenType")
        }
        return request
    }

    // MARK: - Credentials

    struct Credential: Equatable {
        let accessToken: String
        let profileArn: String
        let tokenType: String?

        /// The API endpoint follows the profile's region, as in the IDE.
        var region: String {
            let parts = profileArn.split(separator: ":", omittingEmptySubsequences: false)
            return parts.count > 3 && !parts[3].isEmpty ? String(parts[3]) : "us-east-1"
        }
    }

    private struct Profile: Decodable { let arn: String }

    private struct CLIToken: Decodable {
        let access_token: String
        let expires_at: String?
        /// Builder ID and IAM Identity Center tokens only.
        let start_url: String?
        /// Google/GitHub tokens only.
        let profile_arn: String?
    }

    private struct IDEToken: Decodable {
        let accessToken: String
        let expiresAt: String?
        /// Present for Google/GitHub logins; others keep it in `profile.json`.
        let profileArn: String?
        /// `BuilderId`, `Enterprise`, `Internal`, `Google`, `Github` or `ExternalIdp`.
        let provider: String?
        /// `IdC`, `social` or `external_idp`; older files omit it.
        let authMethod: String?
    }

    private static func readCLIValues() -> [String: String] {
        CursorProvider.readValues(keys: cliTokenKeys.map(\.key), table: "auth_kv", databasePath: cliDatabasePath)
            .merging(CursorProvider.readValues(keys: [cliProfileKey], table: "state", databasePath: cliDatabasePath)) { $1 }
    }

    /// Picks kiro-cli's unexpired login. `values` holds its `auth_kv` tokens and
    /// the `api.codewhisperer.profile` state row.
    static func cliCredential(_ values: [String: String], now: Date = Date()) -> Credential? {
        let storedArn = values[cliProfileKey].flatMap { try? JSONDecoder().decode(Profile.self, from: Data($0.utf8)) }?.arn
        for (key, tokenType) in cliTokenKeys {
            guard let token = values[key].flatMap({ try? JSONDecoder().decode(CLIToken.self, from: Data($0.utf8)) }),
                  isFresh(token.expires_at, now: now) else { continue }
            let defaultArn: String? = switch tokenType {
            case "SSO_OIDC": token.start_url == nil || token.start_url == builderIDStartURL ? builderIDProfileArn : nil
            case nil: socialProfileArn
            default: nil
            }
            guard let arn = token.profile_arn ?? storedArn ?? defaultArn else { continue }
            return Credential(accessToken: token.access_token, profileArn: arn, tokenType: tokenType)
        }
        return nil
    }

    static func ideCredential(token data: Data?, profile: Data?, now: Date = Date()) -> Credential? {
        guard let token = data.flatMap({ try? JSONDecoder().decode(IDEToken.self, from: $0) }),
              isFresh(token.expiresAt, now: now) else { return nil }
        // Older token files lack `authMethod`; the IDE derives it from `provider` the same way.
        let authMethod = token.authMethod ?? (token.provider == "Google" || token.provider == "Github" ? "social" : "IdC")
        let tokenType = ["IdC": "SSO_OIDC", "external_idp": "EXTERNAL_IDP"][authMethod]
        let storedArn = profile.flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }?.arn
        let defaultArn = authMethod == "social" ? socialProfileArn
            : authMethod == "IdC" && (token.provider ?? "BuilderId") == "BuilderId" ? builderIDProfileArn : nil
        guard let arn = token.profileArn ?? storedArn ?? defaultArn else { return nil }
        return Credential(accessToken: token.accessToken, profileArn: arn, tokenType: tokenType)
    }

    private static func isFresh(_ expiresAt: String?, now: Date) -> Bool {
        expiresAt.flatMap(parseDate).map { $0 > now } ?? true
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Runs `/usage` in kiro-cli, which refreshes the CLI's token as a side
    /// effect. No-op (fails fast) when kiro-cli isn't installed.
    private static func runCLIToRefreshToken() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["kiro-cli", "chat", "--no-interactive", "/usage"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([environment["PATH"]].compactMap { $0 } + extraPaths).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
                return
            }
            Task {
                try? await Task.sleep(nanoseconds: cliTimeoutSeconds * 1_000_000_000)
                process.terminate()
            }
        }
    }

    // MARK: - Response

    private struct UsageLimits: Decodable {
        struct Subscription: Decodable { let subscriptionTitle: String? }
        struct Breakdown: Decodable {
            let resourceType: String?
            let currentUsageWithPrecision: Double?
            let currentOveragesWithPrecision: Double?
            let usageLimitWithPrecision: Double?
        }
        /// Epoch seconds.
        let nextDateReset: Double?
        let subscriptionInfo: Subscription?
        let usageBreakdownList: [Breakdown]?
    }

    /// Kiro meters one monthly credit pool, mapped to the primary bar with a
    /// "Monthly" label. `currentUsage` includes overage spend, so plan usage is
    /// usage minus overages (as CodexBar does) to keep the bar at or under 100%.
    static func snapshot(from data: Data) throws -> UsageSnapshot {
        guard let limits = try? JSONDecoder().decode(UsageLimits.self, from: data),
              let credits = limits.usageBreakdownList?.first(where: { $0.resourceType == "CREDIT" }) ?? limits.usageBreakdownList?.first,
              let limit = credits.usageLimitWithPrecision, limit > 0 else {
            throw KiroError.decodingFailed
        }
        let used = (credits.currentUsageWithPrecision ?? 0) - (credits.currentOveragesWithPrecision ?? 0)
        let plan = limits.subscriptionInfo?.subscriptionTitle
        return UsageSnapshot(
            percentUsed: used / limit * 100,
            resetsAt: limits.nextDateReset.map(Date.init(timeIntervalSince1970:)),
            detailLabel: [plan, String(format: "%g / %g credits", used, limit)].compactMap { $0 }.joined(separator: " · "),
            primaryLabel: "Monthly"
        )
    }
}
