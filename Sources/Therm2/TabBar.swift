import AppKit

/// A single line of terminal titles, sharing the entire window width.
final class TabBar: NSView {
    static let height: CGFloat = 14
    private static let backgroundColor = NSColor(white: 0.09, alpha: 1)
    private static let borderColor = NSColor(white: 0.22, alpha: 1)
    private var buttons: [NSButton] = []
    private var selectedIndex = 0
    var onSelect: ((Int) -> Void)?

    override var isOpaque: Bool { !Preferences.shared.glassyWindow }

    func update(titles: [String], selected: Int) {
        if buttons.count != titles.count {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = titles.indices.map { index in
                let button = NSButton(title: "", target: self, action: #selector(selectTab(_:)))
                button.tag = index
                button.isBordered = false
                button.controlSize = .mini
                button.font = .systemFont(ofSize: 10)
                button.lineBreakMode = .byTruncatingTail
                button.focusRingType = .none
                button.setAccessibilityRole(.radioButton)
                addSubview(button)
                return button
            }
        }
        selectedIndex = selected
        for (index, button) in buttons.enumerated() {
            button.title = titles[index]
            button.setAccessibilityLabel(titles[index].isEmpty ? "Tab \(index + 1)" : titles[index])
            button.contentTintColor = index == selected ? .white : .secondaryLabelColor
            button.setAccessibilityValue(index == selected ? 1 : 0)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let count = CGFloat(max(1, buttons.count))
        for (index, button) in buttons.enumerated() {
            let left = (bounds.width * CGFloat(index) / count).rounded(.down)
            let right = (bounds.width * CGFloat(index + 1) / count).rounded(.down)
            button.frame = NSRect(x: left, y: 0, width: right - left, height: bounds.height)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.backgroundColor.withAlphaComponent(Preferences.shared.glassyWindow ? 0.18 : 1).setFill()
        bounds.fill()
        if buttons.indices.contains(selectedIndex) {
            Preferences.shared.accentColor.withAlphaComponent(Preferences.shared.glassyWindow ? 0.45 : 1).setFill()
            buttons[selectedIndex].frame.fill()
        }
        Self.borderColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        for button in buttons.dropFirst() {
            NSRect(x: button.frame.minX, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    @objc private func selectTab(_ sender: NSButton) { onSelect?(sender.tag) }
}
