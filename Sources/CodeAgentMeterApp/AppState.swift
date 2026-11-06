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

    @Published public var refreshMode: RefreshMode {
        didSet { updateConfig { $0.refreshMode = refreshMode } }
    }

    private let store: AccountStore
    private var refreshScheduler: RefreshScheduler?
    private var failureStreak = 0
    private var unchangedStreak = 0
    private var lastFingerprint = ""

    public init(store: AccountStore = AccountStore()) {
        self.store = store
        self.refreshMode = AppConfigStore().load().refreshMode
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

    private func updateConfig(_ change: (inout AppConfig) -> Void) {
        let configStore = AppConfigStore()
        var config = configStore.load()
        change(&config)
        try? configStore.save(config)
    }

    public func startAutoRefresh() {
        guard refreshScheduler == nil else { return }
        let scheduler = RefreshScheduler(nextInterval: { [weak self] in
            guard let self else { return RefreshPolicy.activeSeconds }
            return RefreshPolicy.interval(
                mode: self.refreshMode, failureStreak: self.failureStreak, unchangedStreak: self.unchangedStreak)
        }) { [weak self] in
            await self?.refreshAll()
        }
        scheduler.start()
        refreshScheduler = scheduler
    }

    /// Highest usage percentage across all accounts, for the menu bar's at-a-glance label.
    public var headlinePercent: Double? {
        accountStates.values.compactMap { state -> Double? in
            if case .success(let snapshot) = state { return snapshot.percentUsed ?? snapshot.weeklyPercentUsed }
            return nil
        }.max()
    }

    /// Accounts grouped under their vendor, in `ProviderRegistry.vendors` order, empty vendors omitted.
    public var accountsByVendor: [(displayName: String, accounts: [ClaudeAccount])] {
        ProviderRegistry.vendors.compactMap { vendor in
            let matching = accounts.filter { $0.vendorID == vendor.id }
            return matching.isEmpty ? nil : (vendor.displayName, matching)
        }
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
        updateStreaks(results)
    }

    /// Feeds `RefreshPolicy`: back off while any account fails, idle once no percentage moves.
    private func updateStreaks(_ results: [UUID: Result<UsageSnapshot, Error>]) {
        let anyFailed = results.values.contains { if case .failure = $0 { return true } else { return false } }
        failureStreak = anyFailed ? failureStreak + 1 : 0
        let fingerprint = results.keys.sorted { $0.uuidString < $1.uuidString }.map { id -> String in
            guard case .success(let snapshot) = results[id] else { return "x" }
            return snapshot.windows.map { "\($0.percent)" }.joined(separator: ",")
        }.joined(separator: "|")
        unchangedStreak = fingerprint == lastFingerprint ? unchangedStreak + 1 : 0
        lastFingerprint = fingerprint
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

    /// Swaps in a fresh secret for an account whose pasted credential expired
    /// or was revoked. Only auth kinds that store a pasted secret can do this;
    /// the rest re-authenticate in their vendor's CLI or app.
    public func reauthenticate(_ account: ClaudeAccount, secret: String) async throws {
        switch account.authKind {
        case .cookie:
            try await ClaudeCookieClient().replaceSessionKey(secret, account: account)
        case .openRouter:
            let provider = OpenRouterProvider()
            _ = try await provider.fetchUsage(apiKey: secret)
            try provider.storeKey(secret, account: account)
        case .cliKeychain, .adminKey, .codexCLI, .antigravity, .cursor, .kiro, .devin:
            return
        }
        await refreshAll()
    }

    private static func describe(_ error: Error) -> String {
        if case ClaudeCookieError.blockedByBotCheck = error { return "Blocked by claude.ai's bot check" }
        if case ClaudeCookieError.decodingFailed = error { return "Unexpected reply from claude.ai" }
        if case ClaudeCookieError.requestFailed(let status) = error { return "claude.ai returned \(status)" }
        if error is ClaudeCookieError { return "Needs re-auth" }
        if error is ClaudeOAuthError { return "Needs re-auth" }
        if case CodexError.cliUnavailable = error { return "Codex CLI unavailable" }
        if error is CodexError { return "Needs re-auth — run codex login" }
        if case AntigravityError.notSignedIn = error { return "Open Antigravity or sign in to agy" }
        if case CursorError.notSignedIn = error { return "Sign in to Cursor" }
        if case KiroError.notSignedIn = error { return "Run kiro-cli login or open Kiro" }
        if case DevinError.notSignedIn = error { return "Run devin auth login or sign in to Devin" }
        if case OpenRouterError.invalidKey = error { return "OpenRouter key revoked" }
        if case OpenRouterError.missingKey = error { return "OpenRouter key missing" }
        return "Refresh failed"
    }
}
