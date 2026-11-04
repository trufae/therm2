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
        preferences.backgroundColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.2)
        preferences.accentColor = .red
        preferences.fontFamily = "Menlo"
        preferences.defaultFontSize = 18
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
        preferences.reset()
        controller.refresh()
        #expect(nativeFullscreen.state == .off)
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
