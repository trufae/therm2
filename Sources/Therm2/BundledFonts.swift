import AppKit
import CoreText

@MainActor
enum BundledFonts {
    private(set) static var families: [String] = []

    static func register(directory: URL? = nil) {
        guard let directory = directory ?? Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var names = Set(families)
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            // Process scope makes these available only inside Therm2, without installing fonts.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
                    names.insert(family)
                }
            }
        }
        families = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
