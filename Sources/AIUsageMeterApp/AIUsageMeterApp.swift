import SwiftUI
import AIUsageMeterCore

@main
struct AIUsageMeterApp: App {
    var body: some Scene {
        MenuBarExtra("ai-usage-meter", systemImage: "gauge.with.dots.needle.67percent") {
            Text("ai-usage-meter \(AIUsageMeterCore.version)")
                .padding()
        }
    }
}
