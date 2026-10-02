import SwiftUI
import CodeAgentMeterCore

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if appState.accounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts Yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Add a Claude, Codex, Antigravity, Cursor, Kiro, Devin, or OpenRouter account to start tracking usage.")
                )
            } else {
                List {
                    ForEach(appState.accountsByVendor, id: \.displayName) { group in
                    Section(group.displayName) {
                        ForEach(group.accounts) { account in
                            AccountDetailView(
                                account: account,
                                state: appState.accountStates[account.id] ?? .idle,
                                onRename: { newLabel in Task { try? await appState.renameAccount(id: account.id, label: newLabel) } },
                                onReauth: { secret in try await appState.reauthenticate(account, secret: secret) },
                                onRemove: { Task { try? await appState.removeAccount(id: account.id) } }
                            )
                        }
                    }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle("CodeAgent Meter")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button {
                    openWindow(id: "add-account")
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
    }
}
