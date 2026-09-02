import SwiftUI
import AIUsageMeterCore

struct AccountRowView: View {
    let account: ClaudeAccount
    let state: AppState.RefreshState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(account.label)
                    .fontWeight(.medium)
                Spacer()
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if case .success(let snapshot) = state, let percent = snapshot.percentUsed {
                ProgressView(value: min(max(percent, 0), 100), total: 100)
            }
        }
    }

    private var statusText: String {
        switch state {
        case .idle:
            return "—"
        case .loading:
            return "Refreshing…"
        case .success(let snapshot):
            guard let percent = snapshot.percentUsed else { return "—" }
            let resets = snapshot.resetsAt.map { " · resets \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "\(Int(percent))%\(resets)"
        case .failure(let message):
            return message
        }
    }
}
