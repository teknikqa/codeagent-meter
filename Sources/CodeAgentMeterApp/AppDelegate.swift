import AppKit

/// Menu-bar-first lifecycle, like 1Password/Docker: the app runs as an
/// `.accessory` (no Dock icon, no Cmd+Tab) and only becomes `.regular` while
/// one of its windows is open. Closing the last window drops back to
/// `.accessory`. Quitting is reserved for the menu bar's Quit button (plus
/// logout/restart/shutdown, which must never be blocked).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the menu bar's Quit button right before calling `terminate`.
    static var allowTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIcon.makeImage()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            let closing = note.object as? NSWindow
            // The MenuBarExtra panel and status item windows aren't titled,
            // so this counts only real app windows.
            let stillOpen = NSApp.windows.contains {
                $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
            }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Makes the Dock icon appear; call before showing a window.
    static func showInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.makeImage()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isSystemQuit = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: kAEQuitReason) != nil
        if Self.allowTermination || isSystemQuit { return .terminateNow }

        // Cmd+Q or Dock > Quit: close windows and stay in the menu bar.
        NSApp.windows.filter { $0.styleMask.contains(.titled) }.forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }
}
