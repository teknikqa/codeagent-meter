import Foundation

/// USD per million tokens. Cache writes are billed at 1.25x input (5-minute cache).
public struct ModelPrice: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double

    public func cost(input i: Int, output o: Int, cacheRead r: Int, cacheWrite w: Int) -> Double {
        (Double(i) * input + Double(o) * output + Double(r) * cacheRead + Double(w) * input * 1.25) / 1_000_000
    }
}

public enum ModelPricing {
    // shortcut: flat per-token rates, no long-prompt tier (Haiku 5.5 charges more past 100K tokens)
    // and no 1-hour cache write rate. Update when Anthropic's pricing changes.
    private static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-opus-5-5", ModelPrice(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", ModelPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", ModelPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5", ModelPrice(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", ModelPrice(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5", ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4", ModelPrice(input: 1, output: 5, cacheRead: 0.10)),
    ].sorted { $0.0.count > $1.0.count }

    /// Longest matching prefix wins, so "claude-opus-5-5" doesn't fall into "claude-opus-5".
    /// Unknown models (including all non-Claude ones) return nil rather than a guess.
    public static func price(for model: String) -> ModelPrice? {
        table.first { model.hasPrefix($0.prefix) }?.price
    }
}
