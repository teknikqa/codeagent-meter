import SwiftUI
import CodeAgentMeterCore

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

            Button("Open CodeAgent Meter") {
                openWindow(id: "main")
                activateAndFocusNewestWindow()
            }

            Button("Add Account…") {
                openWindow(id: "add-account")
                activateAndFocusNewestWindow()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 260)
    }

    /// `openWindow` schedules window creation asynchronously, so activating
    /// immediately can race the window not existing yet and being ordered
    /// behind other apps. Defer slightly, then explicitly order the new
    /// window front — activation alone isn't reliable for windows opened
    /// from a MenuBarExtra.
    private func activateAndFocusNewestWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.last { $0.isVisible && $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
        }
    }
}
