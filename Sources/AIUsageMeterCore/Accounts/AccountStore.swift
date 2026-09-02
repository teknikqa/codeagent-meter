import Foundation

/// Owns the account list, its persistence, and fanning refreshes out across
/// accounts independently — one account's failure never blocks another's.
public actor AccountStore {
    private let configStore: AppConfigStore
    private let provider: any UsageProvider

    public private(set) var accounts: [ClaudeAccount]

    public init(
        configStore: AppConfigStore = AppConfigStore(),
        provider: any UsageProvider = ProviderRegistry.claude
    ) {
        self.configStore = configStore
        self.provider = provider
        self.accounts = configStore.load().accounts
    }

    public func addAccount(_ account: ClaudeAccount) throws {
        accounts.append(account)
        try persist()
    }

    public func removeAccount(id: UUID) throws {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        accounts.removeAll { $0.id == id }
        try persist()
        deleteCredentials(for: account)
    }

    /// Removes whatever secret this account has stored, regardless of which
    /// auth kind it is — both deletes are no-ops if nothing's there, so this
    /// doesn't need to branch on `account.authKind`.
    private func deleteCredentials(for account: ClaudeAccount) {
        try? KeychainStore(service: ClaudeCookieClient.secretsService).delete(account: account.keychainKey)
        try? KeychainStore(service: ClaudeOAuthClient.tokenCacheService).delete(account: account.keychainKey)
    }

    /// Refreshes every account concurrently. A failure for one account is
    /// captured in its own `Result` rather than thrown, so it can't prevent
    /// other accounts from refreshing or updating the UI.
    @discardableResult
    public func refreshAll() async -> [UUID: Result<UsageSnapshot, Error>] {
        let currentAccounts = accounts
        let results = await withTaskGroup(of: (UUID, Result<UsageSnapshot, Error>).self) { group in
            for account in currentAccounts {
                group.addTask {
                    do {
                        let snapshot = try await self.provider.fetchUsage(for: account)
                        return (account.id, .success(snapshot))
                    } catch {
                        return (account.id, .failure(error))
                    }
                }
            }
            var collected: [UUID: Result<UsageSnapshot, Error>] = [:]
            for await (id, result) in group {
                collected[id] = result
            }
            return collected
        }

        for index in accounts.indices {
            if case .success = results[accounts[index].id] {
                accounts[index].lastRefreshedAt = Date()
            }
        }
        try? persist()

        return results
    }

    private func persist() throws {
        var config = configStore.load()
        config.accounts = accounts
        try configStore.save(config)
    }
}
