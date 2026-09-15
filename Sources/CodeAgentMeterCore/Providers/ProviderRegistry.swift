import Foundation

/// Maps vendor IDs to their `UsageProvider`. Adding Gemini/Copilot later
/// means registering their providers here rather than changing any calling code.
public enum ProviderRegistry {
    public static let claude: any UsageProvider = ClaudeProvider()
    public static let codex: any UsageProvider = CodexProvider()
    public static let antigravity: any UsageProvider = AntigravityProvider()
    public static let cursor: any UsageProvider = CursorProvider()
    public static let kiro: any UsageProvider = KiroProvider()

    /// Display order for vendor sections in the UI.
    public static let vendors: [(id: String, displayName: String)] = [
        (ClaudeProvider.vendorID, ClaudeProvider.displayName),
        (CodexProvider.vendorID, CodexProvider.displayName),
        (AntigravityProvider.vendorID, AntigravityProvider.displayName),
        (CursorProvider.vendorID, CursorProvider.displayName),
        (KiroProvider.vendorID, KiroProvider.displayName),
    ]

    public static func provider(for account: ClaudeAccount) -> any UsageProvider {
        switch account.vendorID {
        case CodexProvider.vendorID: return codex
        case AntigravityProvider.vendorID: return antigravity
        case CursorProvider.vendorID: return cursor
        case KiroProvider.vendorID: return kiro
        default: return claude
        }
    }
}
