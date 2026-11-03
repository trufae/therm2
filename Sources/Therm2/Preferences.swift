import AppKit

@MainActor
final class Preferences {
    static let shared = Preferences()
    enum Change { case background, separator, font, dimming, notch, directory, title }
    enum DirectoryMode: String { case inherit, home }
    private let defaults: UserDefaults
    var onChange: ((Change) -> Void)?

    var backgroundColor: NSColor {
        didSet {
            backgroundColor = Self.opaque(backgroundColor) ?? oldValue
            guard backgroundColor != oldValue else { return }
            save(backgroundColor, key: "backgroundColor", change: .background)
        }
    }
    var separatorColor: NSColor {
        didSet {
            separatorColor = Self.opaque(separatorColor) ?? oldValue
            guard separatorColor != oldValue else { return }
            save(separatorColor, key: "separatorColor", change: .separator)
        }
    }
    var fontFamily: String? {
        didSet {
            guard fontFamily != oldValue else { return }
            defaults.set(fontFamily, forKey: "fontFamily")
            onChange?(.font)
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
    var ignoreNotch: Bool {
        didSet {
            guard ignoreNotch != oldValue else { return }
            defaults.set(ignoreNotch, forKey: "ignoreNotch")
            onChange?(.notch)
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
        backgroundColor = Self.color(defaults, key: "backgroundColor") ?? .black
        separatorColor = Self.color(defaults, key: "separatorColor") ?? NSColor(white: 0.22, alpha: 1)
        fontFamily = defaults.string(forKey: "fontFamily").flatMap { $0.isEmpty ? nil : $0 }
        let dimming = defaults.object(forKey: "inactiveTextDimming") as? Double ?? 0.3
        inactiveTextDimming = dimming.isFinite && (0...0.75).contains(dimming) ? dimming : 0.3
        ignoreNotch = defaults.bool(forKey: "ignoreNotch")
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
        backgroundColor = .black
        separatorColor = NSColor(white: 0.22, alpha: 1)
        fontFamily = nil
        inactiveTextDimming = 0.3
        ignoreNotch = false
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
