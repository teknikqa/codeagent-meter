import SwiftUI
import AIUsageMeterCore

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if appState.accounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts Yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Add a Claude account to start tracking usage.")
                )
            } else {
                List(appState.accounts) { account in
                    AccountDetailView(
                        account: account,
                        state: appState.accountStates[account.id] ?? .idle,
                        onRemove: { Task { try? await appState.removeAccount(id: account.id) } }
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle("ai-usage-meter")
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
