import AppKit

@MainActor
final class Preferences {
    static let shared = Preferences()
    enum Change { case background, glass, accent, font, fontSize, margin, scrollback, dimming, notch, fullscreen, directory, title }
    enum DirectoryMode: String { case inherit, home }
    static let maximumBorderMargin: CGFloat = 100
    static let maximumScrollbackLimit = 1_000_000
    private let defaults: UserDefaults
    var onChange: ((Change) -> Void)?

    var scrollbackSize: Int { unlimitedScrollback ? -1 : scrollbackLimit }
    var unlimitedScrollback: Bool {
        didSet {
            guard unlimitedScrollback != oldValue else { return }
            defaults.set(unlimitedScrollback, forKey: "unlimitedScrollback")
            onChange?(.scrollback)
        }
    }
    var scrollbackLimit: Int {
        didSet {
            scrollbackLimit = min(Self.maximumScrollbackLimit, max(0, scrollbackLimit))
            guard scrollbackLimit != oldValue else { return }
            defaults.set(scrollbackLimit, forKey: "scrollbackLimit")
            onChange?(.scrollback)
        }
    }

    var terminalBackgroundColor: NSColor {
        backgroundColor.withAlphaComponent(glassyWindow ? 0.18 : 1)
    }

    func backgroundColor(brightness: CGFloat) -> NSColor {
        guard brightness < 1 else { return backgroundColor }
        return NSColor(srgbRed: backgroundColor.redComponent * brightness,
                       green: backgroundColor.greenComponent * brightness,
                       blue: backgroundColor.blueComponent * brightness, alpha: 1)
    }

    var glassyWindow: Bool {
        didSet {
            guard glassyWindow != oldValue else { return }
            defaults.set(glassyWindow, forKey: "glassyWindow")
            onChange?(.glass)
        }
    }

    var backgroundColor: NSColor {
        didSet {
            backgroundColor = Self.opaque(backgroundColor) ?? oldValue
            guard backgroundColor != oldValue else { return }
            save(backgroundColor, key: "backgroundColor", change: .background)
        }
    }
    var accentColor: NSColor {
        didSet {
            accentColor = Self.opaque(accentColor) ?? oldValue
            guard accentColor != oldValue else { return }
            // Keep the stored key to preserve existing split separator preferences.
            save(accentColor, key: "separatorColor", change: .accent)
        }
    }
    var fontFamily: String? {
        didSet {
            guard fontFamily != oldValue else { return }
            defaults.set(fontFamily, forKey: "fontFamily")
            onChange?(.font)
        }
    }
    var defaultFontSize: CGFloat {
        didSet {
            defaultFontSize = defaultFontSize.isFinite
                ? min(TerminalPane.maximumFontSize, max(TerminalPane.minimumFontSize, defaultFontSize.rounded())) : oldValue
            guard defaultFontSize != oldValue else { return }
            defaults.set(Double(defaultFontSize), forKey: "defaultFontSize")
            onChange?(.fontSize)
        }
    }
    var inactiveTextDimming: Double {
        didSet {
            inactiveTextDimming = inactiveTextDimming.isFinite ? min(0.75, max(0, inactiveTextDimming)) : oldValue
            guard inactiveTextDimming != oldValue else { return }
            defaults.set(inactiveTextDimming, forKey: "inactiveTextDimming")
            onChange?(.dimming)
        }
    }
    var borderMargin: CGFloat {
        didSet {
            borderMargin = borderMargin.isFinite
                ? min(Self.maximumBorderMargin, max(0, borderMargin.rounded())) : oldValue
            guard borderMargin != oldValue else { return }
            defaults.set(Double(borderMargin), forKey: "borderMargin")
            onChange?(.margin)
        }
    }
    var ignoreNotch: Bool {
        didSet {
            guard ignoreNotch != oldValue else { return }
            defaults.set(ignoreNotch, forKey: "ignoreNotch")
            onChange?(.notch)
        }
    }
    var useNativeFullscreen: Bool {
        didSet {
            guard useNativeFullscreen != oldValue else { return }
            defaults.set(useNativeFullscreen, forKey: "useNativeFullscreen")
            onChange?(.fullscreen)
        }
    }
    var directoryMode: DirectoryMode {
        didSet {
            guard directoryMode != oldValue else { return }
            defaults.set(directoryMode.rawValue, forKey: "directoryMode")
            onChange?(.directory)
        }
    }
    var emptyWindowTitle: Bool {
        didSet {
            guard emptyWindowTitle != oldValue else { return }
            defaults.set(emptyWindowTitle, forKey: "emptyWindowTitle")
            onChange?(.title)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unlimitedScrollback = defaults.bool(forKey: "unlimitedScrollback")
        let limit = defaults.object(forKey: "scrollbackLimit") as? Int ?? 1_000
        scrollbackLimit = (0...Self.maximumScrollbackLimit).contains(limit) ? limit : 1_000
        glassyWindow = defaults.bool(forKey: "glassyWindow")
        backgroundColor = Self.color(defaults, key: "backgroundColor") ?? .black
        accentColor = Self.color(defaults, key: "separatorColor") ?? NSColor(white: 0.22, alpha: 1)
        fontFamily = defaults.string(forKey: "fontFamily").flatMap { $0.isEmpty ? nil : $0 }
        let size = defaults.object(forKey: "defaultFontSize") as? Double ?? 13
        defaultFontSize = size.isFinite && (TerminalPane.minimumFontSize...TerminalPane.maximumFontSize).contains(CGFloat(size))
            ? CGFloat(size.rounded()) : 13
        let dimming = defaults.object(forKey: "inactiveTextDimming") as? Double ?? 0.3
        inactiveTextDimming = dimming.isFinite && (0...0.75).contains(dimming) ? dimming : 0.3
        let margin = defaults.object(forKey: "borderMargin") as? Double ?? 0
        borderMargin = margin.isFinite && (0...Double(Self.maximumBorderMargin)).contains(margin)
            ? CGFloat(margin.rounded()) : 0
        ignoreNotch = defaults.bool(forKey: "ignoreNotch")
        useNativeFullscreen = defaults.bool(forKey: "useNativeFullscreen")
        directoryMode = DirectoryMode(rawValue: defaults.string(forKey: "directoryMode") ?? "") ?? .inherit
        emptyWindowTitle = defaults.bool(forKey: "emptyWindowTitle")
    }

    func font(size: CGFloat) -> NSFont {
        if let fontFamily, let font = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func reset() {
        unlimitedScrollback = false
        scrollbackLimit = 1_000
        glassyWindow = false
        backgroundColor = .black
        accentColor = NSColor(white: 0.22, alpha: 1)
        fontFamily = nil
        defaultFontSize = 13
        inactiveTextDimming = 0.3
        borderMargin = 0
        ignoreNotch = false
        useNativeFullscreen = false
        directoryMode = .inherit
        emptyWindowTitle = false
    }

    private func save(_ color: NSColor, key: String, change: Change) {
        defaults.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: key)
        onChange?(change)
    }

    private static func opaque(_ color: NSColor) -> NSColor? {
        color.usingColorSpace(.sRGB)?.withAlphaComponent(1)
    }

    private static func color(_ defaults: UserDefaults, key: String) -> NSColor? {
        guard let rgb = defaults.array(forKey: key) as? [Double], rgb.count == 3,
              rgb.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }
}
