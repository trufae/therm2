import AppKit

final class PreferencesWindowController: NSWindowController {
    private let preferences: Preferences
    private let background = NSColorWell()
    private let separator = NSColorWell()
    private let fontFamily = NSPopUpButton()
    private let directory = NSPopUpButton()
    private let dimming = NSSlider(value: 30, minValue: 0, maxValue: 75, target: nil, action: nil)
    private let dimmingValue = NSTextField(labelWithString: "30%")
    private let notch = NSButton(checkboxWithTitle: "Ignore notch in fullscreen", target: nil, action: nil)
    private let emptyTitle = NSButton(checkboxWithTitle: "Use an empty window title", target: nil, action: nil)
    private let preview = NSTextField(labelWithString: "$ echo 'Hello, world'  0123456789")

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Preferences"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.center()

        background.target = self
        background.action = #selector(backgroundChanged)
        background.setAccessibilityLabel("Terminal background color")
        separator.target = self
        separator.action = #selector(separatorChanged)
        separator.setAccessibilityLabel("Split separator color")
        for well in [background, separator] {
            well.widthAnchor.constraint(equalToConstant: 54).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        fontFamily.target = self
        fontFamily.action = #selector(fontChanged)
        fontFamily.setAccessibilityLabel("Font family")
        fontFamily.addItem(withTitle: "System Monospace")
        let bundled = BundledFonts.families
        for family in bundled { addFont(family) }
        fontFamily.menu?.addItem(.separator())
        for family in NSFontManager.shared.availableFontFamilies.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
            where !bundled.contains(family) { addFont(family) }
        fontFamily.widthAnchor.constraint(equalToConstant: 220).isActive = true

        directory.addItems(withTitles: ["Active terminal's directory", "Home directory"])
        directory.target = self
        directory.action = #selector(directoryChanged)
        directory.setAccessibilityLabel("New tabs and splits start in")
        dimming.target = self
        dimming.action = #selector(dimmingChanged)
        dimming.isContinuous = true
        dimming.setAccessibilityLabel("Inactive text dimming percentage")
        dimmingValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dimmingValue.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let dimmingControls = NSStackView(views: [dimming, dimmingValue])
        dimmingControls.spacing = 8
        dimmingControls.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Background"), background],
            [NSTextField(labelWithString: "Split separator"), separator],
            [NSTextField(labelWithString: "Font family"), fontFamily],
            [NSTextField(labelWithString: "Inactive text dimming"), dimmingControls],
            [NSTextField(labelWithString: "New tabs and splits"), directory]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.yPlacement = .center
        notch.target = self
        notch.action = #selector(notchChanged)
        emptyTitle.target = self
        emptyTitle.action = #selector(emptyTitleChanged)
        let checkboxes = NSStackView(views: [notch, emptyTitle])
        checkboxes.orientation = .vertical
        checkboxes.alignment = .leading
        checkboxes.spacing = 8
        preview.lineBreakMode = .byTruncatingTail
        preview.setAccessibilityLabel("Font preview")

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(resetPreferences))
        reset.bezelStyle = .rounded
        let saved = NSTextField(labelWithString: "Changes are saved automatically.")
        saved.font = .systemFont(ofSize: 11)
        saved.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [saved, reset])
        footer.spacing = 24
        let stack = NSStackView(views: [grid, checkboxes, preview, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }

    func refresh() {
        background.color = preferences.backgroundColor
        separator.color = preferences.separatorColor
        let index = fontFamily.itemArray.firstIndex { ($0.representedObject as? String) == preferences.fontFamily } ?? 0
        fontFamily.selectItem(at: index)
        directory.selectItem(at: preferences.directoryMode == .inherit ? 0 : 1)
        dimming.doubleValue = preferences.inactiveTextDimming * 100
        dimmingValue.stringValue = "\(Int(dimming.doubleValue.rounded()))%"
        notch.state = preferences.ignoreNotch ? .on : .off
        emptyTitle.state = preferences.emptyWindowTitle ? .on : .off
        preview.font = preferences.font(size: 13)
    }

    private func addFont(_ family: String) {
        fontFamily.addItem(withTitle: family)
        fontFamily.lastItem?.representedObject = family
    }

    @objc private func backgroundChanged() { preferences.backgroundColor = background.color }
    @objc private func separatorChanged() { preferences.separatorColor = separator.color }
    @objc private func fontChanged() { preferences.fontFamily = fontFamily.selectedItem?.representedObject as? String }
    @objc private func directoryChanged() { preferences.directoryMode = directory.indexOfSelectedItem == 0 ? .inherit : .home }
    @objc private func dimmingChanged() { preferences.inactiveTextDimming = dimming.doubleValue.rounded() / 100 }
    @objc private func notchChanged() { preferences.ignoreNotch = notch.state == .on }
    @objc private func emptyTitleChanged() { preferences.emptyWindowTitle = emptyTitle.state == .on }
    @objc private func resetPreferences() { preferences.reset(); refresh() }
}
