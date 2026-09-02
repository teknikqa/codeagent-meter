import AppKit

/// Builds a Dock/Cmd+Tab icon at runtime from the same gauge glyph used in
/// the menu bar. A bare `swift run` executable has no `Assets.xcassets` to
/// supply `NSApplication.shared.applicationIconImage`, so macOS falls back
/// to a generic placeholder ("exec") — this fills that gap until the app is
/// packaged as a proper `.app` bundle with its own icon asset (future work).
enum AppIcon {
    static func makeImage(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let backgroundRect = NSRect(x: 0, y: 0, width: size, height: size)
        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: size * 0.22, yRadius: size * 0.22)
        NSColor.systemIndigo.setFill()
        backgroundPath.fill()

        if let symbol = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: nil
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .medium)
            let tinted = symbol
                .withSymbolConfiguration(config)?
                .tinted(white)
            let symbolSize = tinted?.size ?? .zero
            let origin = NSPoint(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2)
            tinted?.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }

        image.unlockFocus()
        return image
    }

    private static var white: NSColor { .white }
}

private extension NSImage {
    /// Renders a template image (like an SF Symbol) tinted a solid color.
    func tinted(_ color: NSColor) -> NSImage {
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: size)
        imageRect.fill()
        draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        return tinted
    }
}
