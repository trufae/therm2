import AppKit

final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    private let preferences: Preferences
    private let background = NSColorWell()
    private let accent = NSColorWell()
    private let fontFamily = NSPopUpButton()
    private let fontSize = NSTextField(string: "13")
    private let fontSizeStepper = NSStepper()
    private let borderMargin = NSTextField(string: "0")
    private let borderMarginStepper = NSStepper()
    private let scrollbackMode = NSPopUpButton()
    private let scrollbackLimit = NSTextField(string: "1000")
    private let directory = NSPopUpButton()
    private let dimming = NSSlider(value: 45, minValue: 0, maxValue: 75, target: nil, action: nil)
    private let dimmingValue = NSTextField(labelWithString: "30%")
    private let notch = NSButton(checkboxWithTitle: "Ignore notch in fullscreen", target: nil, action: nil)
    private let nativeFullscreen = NSButton(checkboxWithTitle: "Use native fullscreen", target: nil, action: nil)
    private let emptyTitle = NSButton(checkboxWithTitle: "Use an empty window title", target: nil, action: nil)
    private let glassyWindow = NSButton(checkboxWithTitle: "Glassy window", target: nil, action: nil)
    private let preview: PreferencesPreview

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        preview = PreferencesPreview(preferences: preferences)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Preferences"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        background.target = self
        background.action = #selector(backgroundChanged)
        background.setAccessibilityLabel("Terminal background color")
        accent.target = self
        accent.action = #selector(accentChanged)
        accent.setAccessibilityLabel("Accent color")
        accent.toolTip = "Color of split separators and the active tab."
        for well in [background, accent] {
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

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: Double(TerminalPane.minimumFontSize))
        formatter.maximum = NSNumber(value: Double(TerminalPane.maximumFontSize))
        fontSize.formatter = formatter
        fontSize.alignment = .right
        fontSize.delegate = self
        fontSize.target = self
        fontSize.action = #selector(fontSizeChanged)
        fontSize.setAccessibilityLabel("Default font size in points")
        fontSize.widthAnchor.constraint(equalToConstant: 58).isActive = true
        fontSizeStepper.minValue = Double(TerminalPane.minimumFontSize)
        fontSizeStepper.maxValue = Double(TerminalPane.maximumFontSize)
        fontSizeStepper.increment = 1
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepped)
        fontSizeStepper.setAccessibilityLabel("Adjust default font size")
        let sizeControls = NSStackView(views: [fontSize, fontSizeStepper, NSTextField(labelWithString: "pt · ⌘0")])
        sizeControls.spacing = 6

        let marginFormatter = NumberFormatter()
        marginFormatter.numberStyle = .decimal
        marginFormatter.allowsFloats = false
        marginFormatter.minimum = 0
        marginFormatter.maximum = NSNumber(value: Double(Preferences.maximumBorderMargin))
        borderMargin.formatter = marginFormatter
        borderMargin.alignment = .right
        borderMargin.delegate = self
        borderMargin.target = self
        borderMargin.action = #selector(borderMarginChanged)
        borderMargin.setAccessibilityLabel("Border margin in points")
        borderMargin.toolTip = "Space between each terminal pane's edges and its text."
        borderMargin.widthAnchor.constraint(equalToConstant: 58).isActive = true
        borderMarginStepper.minValue = 0
        borderMarginStepper.maxValue = Double(Preferences.maximumBorderMargin)
        borderMarginStepper.increment = 1
        borderMarginStepper.target = self
        borderMarginStepper.action = #selector(borderMarginStepped)
        borderMarginStepper.setAccessibilityLabel("Adjust border margin")
        let marginControls = NSStackView(views: [borderMargin, borderMarginStepper, NSTextField(labelWithString: "pt")])
        marginControls.spacing = 6

        scrollbackMode.addItems(withTitles: ["Limited to", "Unlimited"])
        scrollbackMode.target = self
        scrollbackMode.action = #selector(scrollbackModeChanged)
        scrollbackMode.setAccessibilityLabel("Scrollback history mode")
        let historyFormatter = NumberFormatter()
        historyFormatter.numberStyle = .decimal
        historyFormatter.allowsFloats = false
        historyFormatter.minimum = 0
        historyFormatter.maximum = NSNumber(value: Preferences.maximumScrollbackLimit)
        scrollbackLimit.formatter = historyFormatter
        scrollbackLimit.alignment = .right
        scrollbackLimit.delegate = self
        scrollbackLimit.target = self
        scrollbackLimit.action = #selector(scrollbackLimitChanged)
        scrollbackLimit.setAccessibilityLabel("Scrollback line limit")
        scrollbackLimit.toolTip = "Lines kept above the visible screen. Zero disables history. Lowering the limit discards the oldest excess lines."
        scrollbackLimit.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let historyControls = NSStackView(views: [scrollbackMode, scrollbackLimit, NSTextField(labelWithString: "lines")])
        historyControls.spacing = 6

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
            [NSTextField(labelWithString: "Accent"), accent],
            [NSTextField(labelWithString: "Font family"), fontFamily],
            [NSTextField(labelWithString: "Default font size"), sizeControls],
            [NSTextField(labelWithString: "Border margin"), marginControls],
            [NSTextField(labelWithString: "Scrollback history"), historyControls],
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
        nativeFullscreen.target = self
        nativeFullscreen.action = #selector(nativeFullscreenChanged)
        nativeFullscreen.toolTip = "Use a macOS fullscreen Space. Uncheck for instant fullscreen. Applies the next time you enter fullscreen."
        emptyTitle.target = self
        emptyTitle.action = #selector(emptyTitleChanged)
        glassyWindow.target = self
        glassyWindow.action = #selector(glassyWindowChanged)
        glassyWindow.toolTip = "Translucent glass behind terminal text. Uses Liquid Glass on macOS 26 or later."
        let checkboxes = NSStackView(views: [glassyWindow, nativeFullscreen, notch, emptyTitle])
        checkboxes.orientation = .vertical
        checkboxes.alignment = .leading
        checkboxes.spacing = 8
        let previewLabel = NSTextField(labelWithString: "Preview · Default size (⌘0)")
        previewLabel.font = .systemFont(ofSize: 11)
        previewLabel.textColor = .secondaryLabelColor
        let previewStack = NSStackView(views: [previewLabel, preview])
        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = 6
        preview.widthAnchor.constraint(equalTo: previewStack.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(resetPreferences))
        reset.bezelStyle = .rounded
        let saved = NSTextField(labelWithString: "Changes are saved automatically.")
        saved.font = .systemFont(ofSize: 11)
        saved.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [saved, reset])
        footer.spacing = 24
        let stack = NSStackView(views: [grid, checkboxes, previewStack, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            previewStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refresh()
        panel.setContentSize(NSSize(width: 480, height: stack.fittingSize.height + 40))
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }

    func refresh() {
        background.color = preferences.backgroundColor
        accent.color = preferences.accentColor
        let index = fontFamily.itemArray.firstIndex { ($0.representedObject as? String) == preferences.fontFamily } ?? 0
        fontFamily.selectItem(at: index)
        fontSize.integerValue = Int(preferences.defaultFontSize)
        fontSizeStepper.doubleValue = Double(preferences.defaultFontSize)
        borderMargin.integerValue = Int(preferences.borderMargin)
        borderMarginStepper.doubleValue = Double(preferences.borderMargin)
        scrollbackMode.selectItem(at: preferences.unlimitedScrollback ? 1 : 0)
        scrollbackLimit.integerValue = preferences.scrollbackLimit
        scrollbackLimit.isEnabled = !preferences.unlimitedScrollback
        directory.selectItem(at: preferences.directoryMode == .inherit ? 0 : 1)
        dimming.doubleValue = dimming.maxValue - preferences.inactiveTextDimming * 100
        dimmingValue.stringValue = "\(Int((preferences.inactiveTextDimming * 100).rounded()))%"
        notch.state = preferences.ignoreNotch ? .on : .off
        nativeFullscreen.state = preferences.useNativeFullscreen ? .on : .off
        emptyTitle.state = preferences.emptyWindowTitle ? .on : .off
        glassyWindow.state = preferences.glassyWindow ? .on : .off
        preview.needsDisplay = true
    }

    private func addFont(_ family: String) {
        fontFamily.addItem(withTitle: family)
        fontFamily.lastItem?.representedObject = family
    }

    @objc private func backgroundChanged() { preferences.backgroundColor = background.color; preview.needsDisplay = true }
    @objc private func accentChanged() { preferences.accentColor = accent.color; preview.needsDisplay = true }
    @objc private func fontChanged() {
        preferences.fontFamily = fontFamily.selectedItem?.representedObject as? String
        preview.needsDisplay = true
    }
    @objc private func fontSizeChanged() {
        preferences.defaultFontSize = CGFloat(fontSize.doubleValue)
        refresh()
    }
    @objc private func fontSizeStepped() {
        preferences.defaultFontSize = CGFloat(fontSizeStepper.doubleValue)
        refresh()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if notification.object as? NSTextField === fontSize { fontSizeChanged() }
        if notification.object as? NSTextField === borderMargin { borderMarginChanged() }
        if notification.object as? NSTextField === scrollbackLimit { scrollbackLimitChanged() }
    }
    @objc private func scrollbackModeChanged() {
        preferences.unlimitedScrollback = scrollbackMode.indexOfSelectedItem == 1
        refresh()
    }
    @objc private func scrollbackLimitChanged() {
        preferences.scrollbackLimit = scrollbackLimit.integerValue
        refresh()
    }
    @objc private func borderMarginChanged() {
        preferences.borderMargin = CGFloat(borderMargin.doubleValue)
        refresh()
    }
    @objc private func borderMarginStepped() {
        preferences.borderMargin = CGFloat(borderMarginStepper.doubleValue)
        refresh()
    }
    @objc private func directoryChanged() { preferences.directoryMode = directory.indexOfSelectedItem == 0 ? .inherit : .home }
    @objc private func dimmingChanged() {
        preferences.inactiveTextDimming = (dimming.maxValue - dimming.doubleValue).rounded() / 100
        dimmingValue.stringValue = "\(Int((preferences.inactiveTextDimming * 100).rounded()))%"
        preview.needsDisplay = true
    }
    @objc private func notchChanged() { preferences.ignoreNotch = notch.state == .on }
    @objc private func nativeFullscreenChanged() { preferences.useNativeFullscreen = nativeFullscreen.state == .on }
    @objc private func emptyTitleChanged() { preferences.emptyWindowTitle = emptyTitle.state == .on }
    @objc private func glassyWindowChanged() { preferences.glassyWindow = glassyWindow.state == .on }
    @objc private func resetPreferences() { preferences.reset(); refresh() }
}
