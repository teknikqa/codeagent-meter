import Foundation
import UserNotifications
import CodeAgentMeterCore

/// Thin wrapper over UNUserNotificationCenter. A bare `swift run` binary has
/// no bundle, and the center crashes without one, so everything no-ops there.
enum UsageNotifier {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ alert: ThresholdAlert, accountLabel: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.threshold >= 100 ? "\(accountLabel) is out of quota" : "\(accountLabel) is at \(alert.threshold)%"
        content.body = "\(alert.windowLabel) window: \(Int(alert.percent))% used."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
