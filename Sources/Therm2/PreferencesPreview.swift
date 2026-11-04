import AppKit

/// A small, noninteractive split preview drawn at the terminal's actual default size.
final class PreferencesPreview: NSView {
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Terminal preview with active and dimmed panes at the default font size")
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        preferences.accentColor.setFill()
        bounds.fill()
        let interior = bounds.insetBy(dx: 1, dy: 1)
        let leftWidth = floor(interior.width * 0.6)
        let left = NSRect(x: interior.minX, y: interior.minY, width: leftWidth, height: interior.height)
        let right = NSRect(x: left.maxX + 1, y: interior.minY,
                           width: max(0, interior.width - leftWidth - 1), height: interior.height)
        drawPane(left, lines: ["$ echo 'Hello, world!'", "Hello, world!", "$ _"], brightness: 1)
        drawPane(right, lines: ["$ pwd", "~/projects", "$ _"], brightness: 1 - preferences.inactiveTextDimming)
    }

    private func drawPane(_ rect: NSRect, lines: [String], brightness: Double) {
        preferences.backgroundColor.setFill()
        rect.fill()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let margin = preferences.borderMargin
        let textRect = rect.insetBy(dx: margin, dy: margin)
        guard textRect.width > 0, textRect.height > 0 else { return }
        NSBezierPath(rect: textRect).addClip()
        let font = preferences.font(size: preferences.defaultFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.86 * brightness, alpha: 1)
        ]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: textRect.minX, y: textRect.minY + CGFloat(index) * lineHeight),
                                   withAttributes: attributes)
        }
    }
}
