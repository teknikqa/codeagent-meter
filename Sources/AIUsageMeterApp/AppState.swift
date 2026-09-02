import Foundation
import AIUsageMeterCore

/// Bridges `AccountStore` (an actor in Core) to SwiftUI's observation model.
/// This is the single source of truth the menu bar and the full window both
/// read from, so they can never disagree about current usage.
@MainActor
public final class AppState: ObservableObject {
    public enum RefreshState: Equatable {
        case idle
        case loading
        case success(UsageSnapshot)
        case failure(String)
    }

    @Published public private(set) var accounts: [ClaudeAccount] = []
    @Published public private(set) var accountStates: [UUID: RefreshState] = [:]

    private let store: AccountStore

    public init(store: AccountStore = AccountStore()) {
        self.store = store
    }

    /// Highest usage percentage across all accounts, for the menu bar's at-a-glance label.
    public var headlinePercent: Double? {
        accountStates.values.compactMap { state -> Double? in
            if case .success(let snapshot) = state { return snapshot.percentUsed }
            return nil
        }.max()
    }

    public func loadAccounts() async {
        accounts = await store.accounts
    }

    public func refreshAll() async {
        accounts = await store.accounts
        for account in accounts {
            accountStates[account.id] = .loading
        }

        let results = await store.refreshAll()
        accounts = await store.accounts

        for (id, result) in results {
            switch result {
            case .success(let snapshot):
                accountStates[id] = .success(snapshot)
            case .failure(let error):
                accountStates[id] = .failure(Self.describe(error))
            }
        }
    }

    public func addAccount(_ account: ClaudeAccount) async throws {
        try await store.addAccount(account)
        accounts = await store.accounts
    }

    public func removeAccount(id: UUID) async throws {
        try await store.removeAccount(id: id)
        accounts = await store.accounts
        accountStates[id] = nil
    }

    private static func describe(_ error: Error) -> String {
        if error is ClaudeCookieError { return "Needs re-auth" }
        if error is ClaudeOAuthError { return "Needs re-auth" }
        return "Refresh failed"
    }
}
