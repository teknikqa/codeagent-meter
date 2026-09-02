import SwiftUI
import AIUsageMeterCore

struct AccountDetailView: View {
    let account: ClaudeAccount
    let state: AppState.RefreshState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.label)
                    .font(.headline)
                Spacer()
                Text(authKindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch state {
            case .idle:
                Text("Not yet refreshed")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            case .success(let snapshot):
                if let percent = snapshot.percentUsed {
                    ProgressView(value: min(max(percent, 0), 100), total: 100)
                    Text("\(Int(percent))% used")
                }
                if let resetsAt = snapshot.resetsAt {
                    Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let planLabel = snapshot.planLabel {
                    Text(planLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if let lastRefreshedAt = account.lastRefreshedAt {
                Text("Last refreshed \(lastRefreshedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var authKindLabel: String {
        switch account.authKind {
        case .cliKeychain: return "Claude Code CLI"
        case .cookie: return "Session cookie"
        case .adminKey: return "Admin key"
        }
    }
}
