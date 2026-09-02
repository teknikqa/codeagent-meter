import AppKit

/// `swift run` launches this app as a bare executable with no `Info.plist`,
/// so macOS doesn't register it as a normal foreground app — windows open
/// but never activate, and the app is invisible to Cmd+Tab. Explicitly
/// setting `.regular` fixes this for development; a packaged `.app` bundle
/// (future work — see README) would get this from its own Info.plist instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
