import SwiftUI
import AIUsageMeterCore

@main
struct AIUsageMeterApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            Label(menuBarLabelText, systemImage: "gauge.with.dots.needle.67percent")
        }
        // Default (.menu) style renders content as a native NSMenu, which
        // doesn't support custom SwiftUI layouts like ProgressView — rows
        // show up dimmed/truncated. .window renders a real SwiftUI view.
        .menuBarExtraStyle(.window)

        WindowGroup(id: "main") {
            MainWindowView()
                .environmentObject(appState)
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
