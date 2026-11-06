import XCTest
@testable import CodeAgentMeterCore

final class CostScannerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var cutoff: Date { Date(timeIntervalSince1970: 0) }

    func testPricesLongestPrefixAndLeavesUnknownModelsUnpriced() {
        XCTAssertEqual(ModelPricing.price(for: "claude-opus-5-5")?.input, 4)
        XCTAssertEqual(ModelPricing.price(for: "claude-opus-5")?.input, 5)
        XCTAssertNil(ModelPricing.price(for: "gpt-6.1-sol"))
    }

    func testClaudeParsingDedupesStreamedMessages() {
        let line = #"{"type":"assistant","timestamp":"2026-11-04T10:00:00.000Z","cwd":"/a/proj","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":1000000,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        let data = Data((line + "\n" + line + "\n").utf8)
        let buckets = CostScanner.merge(CostScanner.parseClaude(data, calendar: calendar, cutoff: cutoff))
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].input, 1_000_000)
        XCTAssertEqual(buckets[0].project, "proj")
        XCTAssertEqual(buckets[0].cost ?? 0, 2.0, accuracy: 0.0001)
    }

    func testCodexCountsOnlyGrownRunningTotalAndSplitsCachedInput() {
        let context = #"{"type":"turn_context","timestamp":"2026-11-04T10:00:00Z","payload":{"model":"gpt-x","cwd":"/a/web"}}"#
        let event = #"{"type":"event_msg","timestamp":"2026-11-04T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":150},"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":50}}}}"#
        let data = Data([context, event, event].joined(separator: "\n").utf8)
        let buckets = CostScanner.merge(CostScanner.parseCodex(data, calendar: calendar, cutoff: cutoff))
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual([buckets[0].input, buckets[0].cacheRead, buckets[0].output], [60, 40, 50])
        XCTAssertNil(buckets[0].cost)
    }
}
