import SwiftUI
import Charts
import CodeAgentMeterCore

/// Local spend estimate from the session logs on disk, at API list prices.
/// Subscriptions don't bill per token, so read it as "what this usage would
/// cost on the API".
struct SpendView: View {
    @EnvironmentObject var appState: AppState
    @State private var period: CostPeriod = .week
    @State private var buckets: [CostBucket] = []
    @State private var scanning = false

    private var visible: [CostBucket] {
        let start = period.start()
        return buckets.filter { $0.day >= start }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(CostPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    Text(cost(visible.compactMap(\.cost).reduce(0, +)))
                        .font(.largeTitle.bold())
                    Text("\(tokens(visible.reduce(0) { $0 + $1.totalTokens })) tokens at API rates")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if scanning { ProgressView().controlSize(.small) }
                }
                dailyChart
            }
            breakdown("By model", key: \.model)
            breakdown("By project", key: \.project)
            breakdown("By tool", key: \.tool)
        }
        .task { await scan() }
        .toolbar {
            ToolbarItem {
                Button { Task { await scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
            }
        }
    }

    @ViewBuilder private var dailyChart: some View {
        let days = Dictionary(grouping: visible, by: \.day).mapValues { $0.compactMap(\.cost).reduce(0, +) }
        if days.count > 1 {
            Chart(days.sorted { $0.key < $1.key }, id: \.key) { day in
                BarMark(x: .value("Day", day.key, unit: .day), y: .value("Cost", day.value))
            }
            .frame(height: 90)
        }
    }

    private func breakdown(_ title: String, key: KeyPath<CostBucket, String>) -> some View {
        let groups = Dictionary(grouping: visible, by: { $0[keyPath: key] })
            .map { (name: $0.key, cost: $0.value.compactMap(\.cost).reduce(0, +),
                    tokens: $0.value.reduce(0) { $0 + $1.totalTokens },
                    priced: $0.value.contains { $0.cost != nil }) }
            .sorted { ($0.cost, $0.tokens) > ($1.cost, $1.tokens) }
        return Section(title) {
            ForEach(groups.prefix(8), id: \.name) { group in
                HStack {
                    Text(group.name).lineLimit(1)
                    Spacer()
                    Text(tokens(group.tokens)).foregroundStyle(.secondary)
                    Text(group.priced ? cost(group.cost) : "unpriced")
                        .monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
            }
        }
    }

    private func scan() async {
        scanning = true
        buckets = await appState.scanCosts()
        scanning = false
    }

    private func cost(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }

    private func tokens(_ count: Int) -> String { count.formatted(.number.notation(.compactName)) }
}
