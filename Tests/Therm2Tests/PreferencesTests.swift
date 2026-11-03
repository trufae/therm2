import AppKit
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct PreferencesTests {
    init() { _ = NSApplication.shared }

    @Test func settingsPersistColorsFamilyDimmingNotchAndDirectoryMode() throws {
        let domain = "Therm2Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.backgroundColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.2)
        preferences.separatorColor = .red
        preferences.fontFamily = "Menlo"
        preferences.inactiveTextDimming = 0.5
        preferences.ignoreNotch = true
        preferences.directoryMode = .home
        preferences.emptyWindowTitle = true
        let loaded = Preferences(defaults: defaults)
        #expect(loaded.backgroundColor.alphaComponent == 1)
        #expect(abs(loaded.backgroundColor.redComponent - 0.1) < 0.0001)
        #expect(loaded.separatorColor.redComponent > 0.99)
        #expect(loaded.fontFamily == "Menlo")
        #expect(loaded.font(size: 24).pointSize == 24)
        #expect(loaded.inactiveTextDimming == 0.5)
        #expect(loaded.ignoreNotch)
        #expect(loaded.directoryMode == .home)
        #expect(loaded.emptyWindowTitle)
        loaded.reset()
        let reset = Preferences(defaults: defaults)
        #expect(reset.fontFamily == nil)
        #expect(reset.inactiveTextDimming == 0.3)
        #expect(!reset.ignoreNotch)
        #expect(reset.directoryMode == .inherit)
        #expect(!reset.emptyWindowTitle)
        #expect(reset.backgroundColor.redComponent == 0)
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
        #expect(BundledFonts.families.count == 5)
        #expect(BundledFonts.families.contains { $0.lowercased().contains("agave") })
        for family in BundledFonts.families {
            #expect(NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13) != nil)
        }
    }
}
