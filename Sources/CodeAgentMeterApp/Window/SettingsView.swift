import SwiftUI
import CodeAgentMeterCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Picker("Refresh", selection: $appState.refreshMode) {
                ForEach(RefreshMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("Adaptive checks every minute, slows to 5 minutes once usage stops changing, and backs off while a provider is failing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Notify at 80% and 100% of a quota window", isOn: $appState.notificationsEnabled)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
