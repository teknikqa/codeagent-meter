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
    private static let cliTokenKey = "kirocli:odic:token"

    /// The fixed profiles Kiro uses for non-enterprise logins, from the IDE's
    /// `ListAvailableProfiles` fallback map.
    static let builderIDProfileArn = "arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX"
    static let socialProfileArn = "arn:aws:codewhisperer:us-east-1:699475941385:profile/EHGA3GRVQMUK"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        var credential = Self.cliCredential(Self.readCLIToken())
        if credential == nil, Self.readCLIToken() != nil {
            // ponytail: a dead CLI refresh token costs one CLI run per refresh before
            // falling back to the IDE; remember the failure if that gets slow.
            await Self.runCLIToRefreshToken()
            credential = Self.cliCredential(Self.readCLIToken())
        }
        guard let credential = credential ?? Self.ideCredential(
            token: try? Data(contentsOf: Self.ideTokenURL),
            profile: try? Data(contentsOf: Self.ideProfileURL)
        ) else { throw KiroError.notSignedIn }

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
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 || status == 403 ? KiroError.notSignedIn : KiroError.requestFailed(status)
        }
        return try Self.snapshot(from: data)
    }

    // MARK: - Credentials

    struct Credential: Equatable {
        let accessToken: String
        let region: String
        let profileArn: String
    }

    private struct IDEToken: Decodable {
        let accessToken: String
        let expiresAt: String?
        let region: String?
        /// Present for Google/GitHub logins; Builder ID keeps it in `profile.json`.
        let profileArn: String?
        let provider: String?
    }

    private struct IDEProfile: Decodable { let arn: String }

    private struct CLIToken: Decodable {
        let access_token: String
        let expires_at: String?
        let region: String?
    }

    private static func readCLIToken() -> Data? {
        CursorProvider.readValues(keys: [cliTokenKey], table: "auth_kv", databasePath: cliDatabasePath)[cliTokenKey]
            .map { Data($0.utf8) }
    }

    // ponytail: CLI logins assume Builder ID's profile; IAM Identity Center users
    // need `ListAvailableProfiles` if one ever uses this.
    static func cliCredential(_ data: Data?, now: Date = Date()) -> Credential? {
        guard let token = data.flatMap({ try? JSONDecoder().decode(CLIToken.self, from: $0) }),
              isFresh(token.expires_at, now: now) else { return nil }
        return Credential(accessToken: token.access_token, region: token.region ?? "us-east-1", profileArn: builderIDProfileArn)
    }

    static func ideCredential(token data: Data?, profile: Data?, now: Date = Date()) -> Credential? {
        guard let token = data.flatMap({ try? JSONDecoder().decode(IDEToken.self, from: $0) }),
              isFresh(token.expiresAt, now: now) else { return nil }
        let storedArn = token.profileArn ?? profile.flatMap { try? JSONDecoder().decode(IDEProfile.self, from: $0) }?.arn
        let defaultArn = token.provider == "Google" || token.provider == "Github" ? socialProfileArn : builderIDProfileArn
        return Credential(accessToken: token.accessToken, region: token.region ?? "us-east-1", profileArn: storedArn ?? defaultArn)
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
