import SwiftUI
import AIUsageMeterCore

@main
struct AIUsageMeterApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
                .task {
                    await appState.loadAccounts()
                    await appState.refreshAll()
                }
        } label: {
            Label(menuBarLabelText, systemImage: "gauge.with.dots.needle.67percent")
        }

        WindowGroup(id: "add-account") {
            AddAccountView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
    }

    private var menuBarLabelText: String {
        guard let percent = appState.headlinePercent else { return "ai-usage-meter" }
        return "\(Int(percent))%"
    }
}
