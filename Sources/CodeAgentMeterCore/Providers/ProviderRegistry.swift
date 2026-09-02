import Foundation

/// Maps vendor IDs to their `UsageProvider`. Holds one entry for MVP; adding
/// Codex/Gemini/Copilot later means registering their providers here rather
/// than changing any calling code.
public enum ProviderRegistry {
    public static let claude: any UsageProvider = ClaudeProvider()
}
