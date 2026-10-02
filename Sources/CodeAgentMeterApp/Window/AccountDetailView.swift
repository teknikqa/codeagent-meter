import SwiftUI
import CodeAgentMeterCore

struct AccountDetailView: View {
    let account: ClaudeAccount
    let state: AppState.RefreshState
    let onRename: (String) -> Void
    let onReauth: (String) async throws -> Void
    let onRemove: () -> Void

    @State private var showRemoveConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameDraft = ""
    @State private var showReauthAlert = false
    @State private var reauthDraft = ""
    @State private var reauthError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.label)
                    .font(.headline)
                Button {
                    renameDraft = account.label
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename Account")
                Spacer()
                Text(authKindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showRemoveConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove Account")
            }

            switch state {
            case .idle:
                Text("Not yet refreshed")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            case .success(let snapshot) where !snapshot.groups.isEmpty:
                ForEach(snapshot.groups, id: \.name) { group in
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let percent = group.snapshot.percentUsed {
                        usageRow(title: group.snapshot.primaryLabel, percent: percent, resetsAt: group.snapshot.resetsAt)
                    }
                    if let weeklyPercent = group.snapshot.weeklyPercentUsed {
                        usageRow(title: "Weekly", percent: weeklyPercent, resetsAt: group.snapshot.weeklyResetsAt)
                    }
                }
                if let detailLabel = snapshot.detailLabel {
                    Text(detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .success(let snapshot):
                if snapshot.percentUsed != nil || snapshot.weeklyPercentUsed != nil {
                    if let percent = snapshot.percentUsed {
                        usageRow(title: snapshot.primaryLabel, percent: percent, resetsAt: snapshot.resetsAt)
                    }
                    if let weeklyPercent = snapshot.weeklyPercentUsed {
                        usageRow(title: "Weekly", percent: weeklyPercent, resetsAt: snapshot.weeklyResetsAt)
                    }
                }
                if let detailLabel = snapshot.detailLabel {
                    Text(detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if account.authKind == .cookie || account.authKind == .openRouter {
                    Button("Re-authenticate…") {
                        reauthDraft = ""
                        showReauthAlert = true
                    }
                    if let reauthError {
                        Text(reauthError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let lastRefreshedAt = account.lastRefreshedAt {
                Text("Last refreshed \(lastRefreshedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Remove “\(account.label)”?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to re-add it to track its usage again.")
        }
        .alert("Rename Account", isPresented: $showRenameAlert) {
            TextField("Label", text: $renameDraft)
            Button("Save") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onRename(trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Re-authenticate “\(account.label)”", isPresented: $showReauthAlert) {
            SecureField(account.authKind == .cookie ? "sessionKey cookie value or full Cookie header" : "sk-or-v1-…", text: $reauthDraft)
            Button("Save") {
                let secret = reauthDraft
                reauthError = nil
                Task {
                    do {
                        try await onReauth(secret)
                    } catch ClaudeCookieError.wrongOrganization {
                        reauthError = "That cookie's login can't see this account's organization — check you copied it from the right claude.ai login."
                    } catch {
                        reauthError = "That didn't work: \(error)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.authKind == .cookie
                ? "Paste a fresh sessionKey cookie from a browser logged into claude.ai."
                : "Paste a new API key from openrouter.ai/settings/keys.")
        }
    }

    @ViewBuilder
    private func usageRow(title: String, percent: Double, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(percent, 0), 100), total: 100)
            if let resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var authKindLabel: String {
        switch account.authKind {
        case .cliKeychain: return "Claude Code CLI"
        case .cookie: return "Session cookie"
        case .adminKey: return "Admin key"
        case .codexCLI: return "Codex CLI · \(account.codexHome ?? CodexProvider.defaultHome)"
        case .antigravity: return "Antigravity app or agy login"
        case .cursor: return "Cursor app login"
        case .kiro: return "kiro-cli or Kiro app login"
        case .devin: return "Devin CLI or Devin app login"
        case .openRouter: return "OpenRouter API key"
        }
    }
}
