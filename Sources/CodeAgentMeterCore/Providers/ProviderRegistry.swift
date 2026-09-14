import Foundation

/// Maps vendor IDs to their `UsageProvider`. Adding Gemini/Copilot later
/// means registering their providers here rather than changing any calling code.
public enum ProviderRegistry {
    public static let claude: any UsageProvider = ClaudeProvider()
    public static let codex: any UsageProvider = CodexProvider()

    /// Display order for vendor sections in the UI.
    public static let vendors: [(id: String, displayName: String)] = [
        (ClaudeProvider.vendorID, ClaudeProvider.displayName),
        (CodexProvider.vendorID, CodexProvider.displayName),
    ]

    public static func provider(for account: ClaudeAccount) -> any UsageProvider {
        account.vendorID == CodexProvider.vendorID ? codex : claude
    }
}
