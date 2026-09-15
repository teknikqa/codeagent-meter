import Foundation

public enum OpenRouterError: Error {
    case missingKey
    case invalidKey
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches OpenRouter spend for a pasted API key, stored in this app's Keychain
/// service alongside Claude session cookies (so removing the account deletes it).
///
/// `/key` works with any key and reports its spending cap and spend. `/credits`
/// (the account balance) only answers management keys, so it's read when the
/// key is one.
public struct OpenRouterProvider: UsageProvider {
    public static let vendorID = "openrouter"
    public static let displayName = "OpenRouter"

    private static let baseURL = "https://openrouter.ai/api/v1"

    private let secretsStore: KeychainStore
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.secretsStore = KeychainStore(service: ClaudeCookieClient.secretsService)
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        guard let data = try? secretsStore.readData(account: account.keychainKey),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw OpenRouterError.missingKey
        }
        return try await fetchUsage(apiKey: apiKey)
    }

    /// Validates a pasted key by fetching with it, so onboarding fails before
    /// storing a bad key.
    public func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        let keyData = try await get("/key", apiKey: apiKey)
        let credits = Self.isManagementKey(keyData) ? try? await get("/credits", apiKey: apiKey) : nil
        return try Self.snapshot(key: keyData, credits: credits)
    }

    public func storeKey(_ apiKey: String, account: ClaudeAccount) throws {
        try secretsStore.write(data: Data(Self.normalizeKey(apiKey).utf8), account: account.keychainKey)
    }

    /// Accepts the bare key or a copied `Authorization: Bearer …` header.
    static func normalizeKey(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Authorization:", "Bearer "] where key.lowercased().hasPrefix(prefix.lowercased()) {
            key = String(key.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return key
    }

    private func get(_ path: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.baseURL + path)!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(Self.normalizeKey(apiKey))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 ? OpenRouterError.invalidKey : OpenRouterError.requestFailed(status)
        }
        return data
    }

    // MARK: - Response

    private struct KeyResponse: Decodable {
        struct Key: Decodable {
            let limit: Double?
            let limit_remaining: Double?
            let limit_reset: String?
            let usage_daily: Double?
            let usage_monthly: Double?
            let is_management_key: Bool?
        }
        let data: Key
    }

    private struct CreditsResponse: Decodable {
        struct Credits: Decodable {
            let total_credits: Double
            let total_usage: Double
        }
        let data: Credits
    }

    private static func isManagementKey(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(KeyResponse.self, from: data))?.data.is_management_key == true
    }

    /// The primary bar is the key's spending cap when it has one, else the
    /// account's credits (management keys only). The detail line carries the
    /// balance and today's and this month's spend. A key with neither shows spend only.
    static func snapshot(key: Data, credits: Data?) throws -> UsageSnapshot {
        guard let key = try? JSONDecoder().decode(KeyResponse.self, from: key).data else {
            throw OpenRouterError.decodingFailed
        }
        let credits = credits.flatMap { try? JSONDecoder().decode(CreditsResponse.self, from: $0).data }

        var percent: Double?
        var label = "Credits"
        if let limit = key.limit, limit > 0, let remaining = key.limit_remaining {
            percent = (limit - remaining) / limit * 100
            label = key.limit_reset.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Limit"
        } else if let credits, credits.total_credits > 0 {
            percent = credits.total_usage / credits.total_credits * 100
        }

        func dollars(_ value: Double) -> String { String(format: "$%.2f", value) }
        let detail = [
            credits.map { "\(dollars($0.total_credits - $0.total_usage)) balance" },
            key.usage_daily.map { "\(dollars($0)) today" },
            key.usage_monthly.map { "\(dollars($0)) this month" },
        ].compactMap { $0 }.joined(separator: " · ")

        return UsageSnapshot(
            percentUsed: percent,
            // OpenRouter doesn't report when a cap resets.
            resetsAt: nil,
            detailLabel: detail.isEmpty ? nil : detail,
            primaryLabel: label
        )
    }
}
