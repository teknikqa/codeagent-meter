import Foundation

/// Fetches Antigravity quota from Google's Code Assist API using the Google
/// login `agy` CLI stores in the Keychain.
///
/// Never writes to `agy`'s Keychain item. Google refresh tokens don't rotate on
/// use, so refreshing here leaves `agy`'s login intact; refreshed access tokens
/// are cached under this app's own Keychain service.
struct AntigravityOAuthClient: Sendable {
    /// Internal (not private) so `AccountStore` can clean up cached tokens on account removal.
    static let tokenCacheService = "com.nickmathew.codeagent-meter.antigravity-cache"
    /// `agy` stores its login via go-keyring under this service/account pair.
    private static let agyKeychainService = "gemini"
    private static let agyKeychainAccount = "antigravity"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let codeAssistBaseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
    private static let agyPaths = ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", "~/.local/bin/agy"]

    private let urlSession: URLSession
    private let tokenCache = KeychainStore(service: tokenCacheService)

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        do {
            return try await fetchQuota(accessToken: validAccessToken(for: account, forceRefresh: false))
        } catch AntigravityError.requestFailed(let status) where status == 401 || status == 403 {
            return try await fetchQuota(accessToken: validAccessToken(for: account, forceRefresh: true))
        }
    }

    // MARK: - Quota

    private func fetchQuota(accessToken: String) async throws -> UsageSnapshot {
        struct LoadCodeAssist: Decodable {
            struct Tier: Decodable { let name: String? }
            let cloudaicompanionProject: String?
            let paidTier: Tier?
            let currentTier: Tier?
        }
        let loadData = try await post("loadCodeAssist", body: ["metadata": ["ideType": "ANTIGRAVITY"]], accessToken: accessToken)
        guard let load = try? JSONDecoder().decode(LoadCodeAssist.self, from: loadData),
              let project = load.cloudaicompanionProject else {
            throw AntigravityError.decodingFailed
        }
        let summary = try await post("retrieveUserQuotaSummary", body: ["project": project], accessToken: accessToken)
        let plan = load.paidTier?.name ?? load.currentTier?.name
        return try AntigravityProvider.snapshot(
            fromQuotaSummary: summary,
            detailLabel: [plan, "via agy login"].compactMap { $0 }.joined(separator: " · ")
        )
    }

    private func post(_ method: String, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(Self.codeAssistBaseURL):\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("antigravity/cli", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw AntigravityError.requestFailed(status) }
        return data
    }

    // MARK: - Tokens

    struct Token: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiry: Date?
    }

    private func validAccessToken(for account: ClaudeAccount, forceRefresh: Bool) async throws -> String {
        let soon = Date().addingTimeInterval(60)
        if !forceRefresh {
            if let cached = cachedToken(for: account), let expiry = cached.expiry, expiry > soon {
                return cached.accessToken
            }
        }

        guard let data = try? KeychainStore.readData(service: Self.agyKeychainService, account: Self.agyKeychainAccount),
              let login = Self.decodeAgyLogin(data) else {
            throw AntigravityError.notSignedIn
        }
        // No expiry recorded: try the token as-is; a 401 comes back here with forceRefresh.
        if !forceRefresh, login.expiry.map({ $0 > soon }) ?? true {
            return login.accessToken
        }
        guard let refreshToken = login.refreshToken else { throw AntigravityError.notSignedIn }

        let refreshed = try await refresh(refreshToken: refreshToken)
        if let encoded = try? JSONEncoder().encode(refreshed) {
            try? tokenCache.write(data: encoded, account: account.keychainKey)
        }
        return refreshed.accessToken
    }

    private func cachedToken(for account: ClaudeAccount) -> Token? {
        guard let data = try? tokenCache.readData(account: account.keychainKey) else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    private func refresh(refreshToken: String) async throws -> Token {
        struct RefreshResponse: Decodable {
            let access_token: String
            let expires_in: Double?
        }
        guard let binary = Self.agyPaths.lazy
            .map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).resolvingSymlinksInPath() })
            .compactMap({ try? Data(contentsOf: $0, options: .alwaysMapped) })
            .first else {
            throw AntigravityError.clientMetadataNotFound
        }
        let candidates = Self.oauthClientCandidates(in: binary)
        guard !candidates.isEmpty else { throw AntigravityError.clientMetadataNotFound }

        // ponytail: rescans the agy binary on every refresh (~hourly); cache the working client if it shows up in profiles.
        var lastStatus = -1
        for client in candidates {
            var request = URLRequest(url: Self.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [
                URLQueryItem(name: "client_id", value: client.id),
                URLQueryItem(name: "client_secret", value: client.secret),
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
            ]
            request.httpBody = form.percentEncodedQuery.map { Data($0.utf8) }
            let (data, response) = try await urlSession.data(for: request)
            lastStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
            if lastStatus == 200, let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data) {
                return Token(
                    accessToken: decoded.access_token,
                    refreshToken: nil,
                    expiry: Date().addingTimeInterval(decoded.expires_in ?? 3600)
                )
            }
            // 400/401 means the wrong client for this token; try the next pair.
            guard lastStatus == 400 || lastStatus == 401 else { break }
        }
        throw AntigravityError.requestFailed(lastStatus)
    }

    /// go-keyring on macOS stores values as `go-keyring-base64:<base64>`. The
    /// payload is a Go `oauth2.Token`, either flat or nested under `token`.
    static func decodeAgyLogin(_ data: Data) -> Token? {
        var payload = data
        let prefix = "go-keyring-base64:"
        if let string = String(data: data, encoding: .utf8), string.hasPrefix(prefix),
           let decoded = Data(base64Encoded: String(string.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)) {
            payload = decoded
        }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        let token = object["token"] as? [String: Any] ?? object
        guard let accessToken = token["access_token"] as? String else { return nil }
        return Token(
            accessToken: accessToken,
            refreshToken: token["refresh_token"] as? String,
            expiry: (token["expiry"] as? String).flatMap(AntigravityProvider.parseDate)
        )
    }

    /// `agy` embeds its Google OAuth client; reading it from the installed
    /// binary keeps this working across `agy` updates. Returns every
    /// client ID × secret pair, since the binary can hold more than one.
    static func oauthClientCandidates(in binary: Data) -> [(id: String, secret: String)] {
        let idSuffix = Data(".apps.googleusercontent.com".utf8)
        let secretPrefix = Data("GOCSPX-".utf8)
        let bytes = binary

        var ids: [String] = []
        for range in occurrences(of: idSuffix, in: binary) {
            // Walk back over `<digits>-<lowercase alphanumerics>`.
            var start = range.lowerBound
            while start > 0, isLowerAlnum(bytes[start - 1]) { start -= 1 }
            guard start > 0, bytes[start - 1] == UInt8(ascii: "-") else { continue }
            var digitsStart = start - 1
            while digitsStart > 0, isDigit(bytes[digitsStart - 1]) { digitsStart -= 1 }
            guard digitsStart < start - 1 else { continue }
            let id = String(decoding: bytes[digitsStart..<range.upperBound], as: UTF8.self)
            if !ids.contains(id) { ids.append(id) }
        }

        var secrets: [String] = []
        for range in occurrences(of: secretPrefix, in: binary) {
            let end = range.upperBound + 28
            guard end <= bytes.count, bytes[range.upperBound..<end].allSatisfy(isSecretByte) else { continue }
            let secret = String(decoding: bytes[range.lowerBound..<end], as: UTF8.self)
            if !secrets.contains(secret) { secrets.append(secret) }
        }

        return ids.reversed().flatMap { id in secrets.map { (id: id, secret: $0) } }
    }

    private static func occurrences(of needle: Data, in data: Data) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var searchStart = data.startIndex
        while let range = data.range(of: needle, in: searchStart..<data.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private static func isLowerAlnum(_ byte: UInt8) -> Bool { isDigit(byte) || (97...122).contains(byte) }
    private static func isSecretByte(_ byte: UInt8) -> Bool {
        isDigit(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
    }
}
