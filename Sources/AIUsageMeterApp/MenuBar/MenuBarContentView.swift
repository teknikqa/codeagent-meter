import SwiftUI
import AIUsageMeterCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.accounts.isEmpty {
                Text("No accounts yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.accounts) { account in
                    AccountRowView(account: account, state: appState.accountStates[account.id] ?? .idle)
                }
            }

            Divider()

            Button("Refresh Now") {
                Task { await appState.refreshAll() }
            }

            Button("Open ai-usage-meter") {
                openWindow(id: "main")
            }

            Button("Add Account…") {
                openWindow(id: "add-account")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 260)
    }
}
