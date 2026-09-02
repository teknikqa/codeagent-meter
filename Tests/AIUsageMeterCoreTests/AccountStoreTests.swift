import XCTest
@testable import AIUsageMeterCore

private struct StubUsageProvider: UsageProvider {
    static let vendorID = "stub"
    static let displayName = "Stub"

    let result: Result<UsageSnapshot, Error>

    func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        try result.get()
    }
}

private enum StubError: Error {
    case boom
}

final class AccountStoreTests: XCTestCase {
    private func makeTempConfigStore() -> AppConfigStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("config.json")
        return AppConfigStore(fileURL: fileURL)
    }

    private func makeAccount(label: String = "Test") -> ClaudeAccount {
        ClaudeAccount(label: label, authKind: .cookie, keychainKey: UUID().uuidString)
    }

    func testAddAccountPersistsAcrossInstances() async throws {
        let configStore = makeTempConfigStore()
        let provider = StubUsageProvider(result: .success(UsageSnapshot(percentUsed: 42, resetsAt: nil, detailLabel: nil)))
        let account = makeAccount()

        let store = AccountStore(configStore: configStore, provider: provider)
        try await store.addAccount(account)

        let reloaded = AccountStore(configStore: configStore, provider: provider)
        let accounts = await reloaded.accounts
        XCTAssertEqual(accounts.map(\.id), [account.id])
    }

    func testRefreshAllUpdatesLastRefreshedOnSuccess() async throws {
        let configStore = makeTempConfigStore()
        let provider = StubUsageProvider(result: .success(UsageSnapshot(percentUsed: 10, resetsAt: nil, detailLabel: nil)))
        let account = makeAccount()

        let store = AccountStore(configStore: configStore, provider: provider)
        try await store.addAccount(account)

        let results = await store.refreshAll()
        guard case .success(let snapshot) = results[account.id] else {
            return XCTFail("expected a success result")
        }
        XCTAssertEqual(snapshot.percentUsed, 10)

        let accounts = await store.accounts
        XCTAssertNotNil(accounts.first?.lastRefreshedAt)
    }

    func testRefreshAllIsolatesOneAccountsFailureFromAnother() async throws {
        let configStore = makeTempConfigStore()
        let goodAccount = makeAccount(label: "Good")
        let badAccount = makeAccount(label: "Bad")

        actor RoutingProvider: UsageProvider {
            static let vendorID = "routing"
            static let displayName = "Routing"
            let goodID: UUID
            let badID: UUID

            init(goodID: UUID, badID: UUID) {
                self.goodID = goodID
                self.badID = badID
            }

            func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
                if account.id == badID { throw StubError.boom }
                return UsageSnapshot(percentUsed: 5, resetsAt: nil, detailLabel: nil)
            }
        }

        let provider = RoutingProvider(goodID: goodAccount.id, badID: badAccount.id)
        let store = AccountStore(configStore: configStore, provider: provider)
        try await store.addAccount(goodAccount)
        try await store.addAccount(badAccount)

        let results = await store.refreshAll()

        guard case .success = results[goodAccount.id] else {
            return XCTFail("expected the good account to succeed")
        }
        guard case .failure = results[badAccount.id] else {
            return XCTFail("expected the bad account to fail")
        }
    }

    func testRemoveAccount() async throws {
        let configStore = makeTempConfigStore()
        let provider = StubUsageProvider(result: .success(UsageSnapshot(percentUsed: 1, resetsAt: nil, detailLabel: nil)))
        let account = makeAccount()

        let store = AccountStore(configStore: configStore, provider: provider)
        try await store.addAccount(account)
        try await store.removeAccount(id: account.id)

        let accounts = await store.accounts
        XCTAssertTrue(accounts.isEmpty)
    }
}
