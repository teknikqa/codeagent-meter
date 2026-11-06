import SwiftUI
import CodeAgentMeterCore

struct AccountDetailView: View {
    let account: ClaudeAccount
    let state: AppState.RefreshState
    let history: UsageHistory
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
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            case .success(let snapshot):
                if snapshot.groups.isEmpty {
                    ForEach(snapshot.windows, id: \.key) { usageRow($0) }
                } else {
                    ForEach(snapshot.groups, id: \.name) { group in
                        Text(group.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        ForEach(snapshot.windows.filter { $0.key.hasPrefix("\(group.name)/") }, id: \.key) { window in
                            usageRow(window, title: window.key.hasSuffix("/weekly") ? "Weekly" : group.snapshot.primaryLabel)
                        }
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
            "Remove “\(shortLabel)”?",
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
        .alert("Re-authenticate “\(shortLabel)”", isPresented: $showReauthAlert) {
            SecureField(account.authKind == .cookie ? "sessionKey cookie value or full Cookie header" : "sk-or-v1-…", text: $reauthDraft)
            Button("Save") {
                let secret = reauthDraft
                reauthError = nil
                Task {
                    do {
                        try await onReauth(secret)
                    } catch ClaudeCookieError.wrongOrganization {
                        reauthError = "That cookie's login can't see this account's organization — check you copied it from the right claude.ai login."
                    } catch ClaudeCookieError.blockedByBotCheck {
                        reauthError = "claude.ai blocked the request with a bot check, so the cookie can't be verified. Add the account with “Claude Code (CLI login)” and its config dir instead."
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
    private func usageRow(_ window: UsageWindow, title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title ?? window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.percent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(window.percent, 0), 100), total: 100)
            HStack {
                if let resetsAt = window.resetsAt {
                    Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                PaceCaption(window: window)
            }
            if let length = window.length, let resetsAt = window.resetsAt {
                BurndownChart(
                    window: window,
                    samples: history.samples(account: account.id, key: window.key, since: resetsAt.addingTimeInterval(-length))
                )
            }
        }
    }

    /// A label can hold anything the user pasted into the field, so keep dialog
    /// titles short enough that their buttons stay on screen.
    private var shortLabel: String {
        account.label.count > 40 ? "\(account.label.prefix(40))…" : account.label
    }

    private var authKindLabel: String {
        switch account.authKind {
        case .cliKeychain: return "Claude Code CLI · \(account.claudeConfigDir ?? ClaudeCLICredentialReader.defaultConfigDir)"
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
