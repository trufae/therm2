import AppKit
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct PreferencesTests {
    init() { _ = NSApplication.shared }

    @Test func settingsPersistColorsFontDimmingNotchAndDirectoryMode() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.useNativeFullscreen)
        #expect(!preferences.glassyWindow)
        #expect(!preferences.unlimitedScrollback)
        #expect(preferences.scrollbackLimit == 1_000)
        #expect(preferences.borderMargin == 0)
        preferences.backgroundColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.2)
        preferences.accentColor = .red
        preferences.fontFamily = "Menlo"
        preferences.defaultFontSize = 18
        preferences.borderMargin = 12
        preferences.glassyWindow = true
        preferences.scrollbackLimit = 25_000
        preferences.unlimitedScrollback = true
        preferences.inactiveTextDimming = 0.5
        preferences.ignoreNotch = true
        preferences.useNativeFullscreen = true
        preferences.directoryMode = .home
        preferences.emptyWindowTitle = true
        let loaded = Preferences(defaults: defaults)
        #expect(loaded.backgroundColor.alphaComponent == 1)
        #expect(abs(loaded.backgroundColor.redComponent - 0.1) < 0.0001)
        #expect(loaded.accentColor.redComponent > 0.99)
        #expect(loaded.fontFamily == "Menlo")
        #expect(loaded.defaultFontSize == 18)
        #expect(loaded.borderMargin == 12)
        #expect(loaded.glassyWindow)
        #expect(loaded.unlimitedScrollback)
        #expect(loaded.scrollbackLimit == 25_000)
        #expect(loaded.scrollbackSize == -1)
        #expect(loaded.font(size: 24).pointSize == 24)
        #expect(loaded.inactiveTextDimming == 0.5)
        #expect(loaded.ignoreNotch)
        #expect(loaded.useNativeFullscreen)
        #expect(loaded.directoryMode == .home)
        #expect(loaded.emptyWindowTitle)
        loaded.reset()
        let reset = Preferences(defaults: defaults)
        #expect(reset.fontFamily == nil)
        #expect(reset.defaultFontSize == 13)
        #expect(reset.borderMargin == 0)
        #expect(!reset.glassyWindow)
        #expect(!reset.unlimitedScrollback)
        #expect(reset.scrollbackSize == 1_000)
        #expect(reset.inactiveTextDimming == 0.3)
        #expect(!reset.ignoreNotch)
        #expect(!reset.useNativeFullscreen)
        #expect(reset.directoryMode == .inherit)
        #expect(!reset.emptyWindowTitle)
        #expect(reset.backgroundColor.redComponent == 0)
    }

    @Test func defaultFontSizeRejectsInvalidValuesAndUsesZoomBounds() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for invalid in [0.0, -10, 1025, Double.infinity, Double.nan] {
            defaults.set(invalid, forKey: "defaultFontSize")
            #expect(Preferences(defaults: defaults).defaultFontSize == 13)
        }
        let preferences = Preferences(defaults: defaults)
        var fontSizeChanges = 0
        preferences.onChange = { if case .fontSize = $0 { fontSizeChanges += 1 } }
        preferences.defaultFontSize = 18.6
        #expect(preferences.defaultFontSize == 19)
        preferences.defaultFontSize = .nan
        #expect(preferences.defaultFontSize == 19)
        #expect(fontSizeChanges == 1)
        preferences.defaultFontSize = 10_000
        #expect(preferences.defaultFontSize == TerminalPane.maximumFontSize)
        preferences.defaultFontSize = -1
        #expect(preferences.defaultFontSize == TerminalPane.minimumFontSize)
        #expect(Preferences(defaults: defaults).defaultFontSize == TerminalPane.minimumFontSize)
    }

    @Test func borderMarginRejectsInvalidValuesAndNotifiesChanges() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for invalid in [-1.0, 101, Double.infinity, Double.nan] {
            defaults.set(invalid, forKey: "borderMargin")
            #expect(Preferences(defaults: defaults).borderMargin == 0)
        }
        let preferences = Preferences(defaults: defaults)
        var changes = 0
        preferences.onChange = { if case .margin = $0 { changes += 1 } }
        preferences.borderMargin = 12.6
        #expect(preferences.borderMargin == 13)
        preferences.borderMargin = .nan
        #expect(preferences.borderMargin == 13)
        #expect(changes == 1)
        preferences.borderMargin = 1_000
        #expect(preferences.borderMargin == Preferences.maximumBorderMargin)
        preferences.borderMargin = -1
        #expect(preferences.borderMargin == 0)
    }

    @Test func scrollbackLimitValidatesStoredValuesAndPreservesLimitInUnlimitedMode() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for invalid in [-1, Preferences.maximumScrollbackLimit + 1] {
            defaults.set(invalid, forKey: "scrollbackLimit")
            #expect(Preferences(defaults: defaults).scrollbackLimit == 1_000)
        }
        let preferences = Preferences(defaults: defaults)
        var changes = 0
        preferences.onChange = { if case .scrollback = $0 { changes += 1 } }
        preferences.scrollbackLimit = 500
        preferences.unlimitedScrollback = true
        #expect(preferences.scrollbackSize == -1)
        #expect(preferences.scrollbackLimit == 500)
        preferences.unlimitedScrollback = false
        #expect(preferences.scrollbackSize == 500)
        #expect(changes == 3)
        preferences.scrollbackLimit = -1
        #expect(preferences.scrollbackSize == 0)
        preferences.scrollbackLimit = Int.max
        #expect(preferences.scrollbackLimit == Preferences.maximumScrollbackLimit)
    }

    @Test func newPanesAndFontResetUseTheSavedDefaultSize() {
        let preferences = Preferences.shared
        let original = preferences.defaultFontSize
        defer { preferences.defaultFontSize = original }
        preferences.defaultFontSize = 21
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        #expect(pane.font.pointSize == 21)
        pane.setFontSize(30)
        pane.setFontSize(TerminalPane.defaultFontSize)
        #expect(pane.font.pointSize == 21)
    }

    @Test func preferencesPanelFitsControlsAndCompactPreview() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let controller = PreferencesWindowController(preferences: preferences)
        let content = try #require(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let stack = try #require(content.subviews.first as? NSStackView)
        #expect(content.bounds.contains(stack.frame))
        for view in stack.arrangedSubviews {
            #expect(stack.bounds.contains(view.frame))
        }
        let checkboxes = stack.arrangedSubviews.compactMap { $0 as? NSStackView }
            .flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        let nativeFullscreen = try #require(checkboxes.first { $0.title == "Use native fullscreen" })
        #expect(nativeFullscreen.state == .off)
        nativeFullscreen.performClick(nil)
        #expect(preferences.useNativeFullscreen)
        #expect(Preferences(defaults: defaults).useNativeFullscreen)
        let glass = try #require(checkboxes.first { $0.title == "Glassy window" })
        #expect(glass.state == .off)
        glass.performClick(nil)
        #expect(preferences.glassyWindow)
        #expect(Preferences(defaults: defaults).glassyWindow)
        preferences.reset()
        controller.refresh()
        #expect(nativeFullscreen.state == .off)
        #expect(glass.state == .off)
        let grid = try #require(stack.arrangedSubviews.first as? NSGridView)
        let historyRow = try #require((0..<grid.numberOfRows).first {
            (grid.cell(atColumnIndex: 0, rowIndex: $0).contentView as? NSTextField)?.stringValue == "Scrollback history"
        })
        let history = try #require(grid.cell(atColumnIndex: 1, rowIndex: historyRow).contentView as? NSStackView)
        let mode = try #require(history.arrangedSubviews.first as? NSPopUpButton)
        let limit = try #require(history.arrangedSubviews[1] as? NSTextField)
        #expect(limit.isEnabled)
        limit.integerValue = 5_000
        limit.sendAction(limit.action, to: limit.target)
        #expect(preferences.scrollbackLimit == 5_000)
        mode.selectItem(at: 1)
        mode.sendAction(mode.action, to: mode.target)
        #expect(preferences.unlimitedScrollback)
        #expect(!limit.isEnabled)
        mode.selectItem(at: 0)
        mode.sendAction(mode.action, to: mode.target)
        #expect(limit.isEnabled)
        #expect(preferences.scrollbackSize == 5_000)
        preferences.reset()
        controller.refresh()
        #expect(mode.indexOfSelectedItem == 0)
        #expect(limit.integerValue == 1_000)
        let previewStack = try #require(stack.arrangedSubviews.compactMap { $0 as? NSStackView }
            .first { $0.arrangedSubviews.contains { $0 is PreferencesPreview } })
        let preview = try #require(previewStack.arrangedSubviews.first { $0 is PreferencesPreview })
        #expect(preview.frame.width == 440)
        #expect(preview.frame.height == 100)
    }

    @Test func invalidStoredColorsAndDimmingFallBackSafely() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set([1, 2], forKey: "backgroundColor")
        defaults.set(-10, forKey: "inactiveTextDimming")
        defaults.set("unknown", forKey: "directoryMode")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.backgroundColor == .black)
        #expect(preferences.inactiveTextDimming == 0.3)
        #expect(preferences.directoryMode == .inherit)
        preferences.inactiveTextDimming = .nan
        #expect(preferences.inactiveTextDimming == 0.3)
        preferences.inactiveTextDimming = 10
        #expect(preferences.inactiveTextDimming == 0.75)
    }

    @Test func originalThermFontsRegisterInsideTheProcess() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        BundledFonts.register(directory: root.appendingPathComponent("Resources/Fonts"))
        #expect(BundledFonts.families.count == 6)
        #expect(BundledFonts.families.contains { $0.lowercased().contains("agave") })
        #expect(BundledFonts.families.contains { $0.lowercased().contains("plex mono") })
        for family in BundledFonts.families {
            #expect(NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13) != nil)
        }
    }
}
