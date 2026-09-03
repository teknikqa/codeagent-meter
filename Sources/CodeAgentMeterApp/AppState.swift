import Foundation
import CodeAgentMeterCore

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
    private var refreshScheduler: RefreshScheduler?

    public init(store: AccountStore = AccountStore()) {
        self.store = store
        // AppState is created once at launch via @StateObject, regardless of
        // which scenes (menu bar, windows) are actually visible — so this is
        // the one reliable place to kick off the initial load and the
        // recurring background refresh.
        Task { [weak self] in
            await self?.loadAccounts()
            await self?.refreshAll()
            self?.startAutoRefresh()
        }
    }

    public func startAutoRefresh(intervalSeconds: TimeInterval? = nil) {
        guard refreshScheduler == nil else { return }
        let interval = intervalSeconds ?? AppConfigStore().load().refreshIntervalSeconds
        let scheduler = RefreshScheduler(intervalSeconds: interval) { [weak self] in
            await self?.refreshAll()
        }
        scheduler.start()
        refreshScheduler = scheduler
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

    public func renameAccount(id: UUID, label: String) async throws {
        try await store.renameAccount(id: id, label: label)
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
