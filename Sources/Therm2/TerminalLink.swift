import Foundation

enum TerminalLink {
    /// Resolve existing paths before SwiftTerm applies its file-opening policy.
    static func fileURL(_ link: String, directory: String) -> URL? {
        guard !link.isEmpty, URL(string: link)?.scheme == nil else { return nil }
        let path = NSString(string: link).expandingTildeInPath
        var paths = [path]
        // Preserve literal filenames first, then try without a source location.
        if let location = path.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression) {
            paths.append(String(path[..<location.lowerBound]))
        }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        for path in paths {
            if path.hasPrefix("/") {
                let absolute = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: absolute.path) { return absolute }
                // A tilde names a home directory, never a project-relative path.
                if link.hasPrefix("~") { continue }
            }
            // Some terminal programs emit project-relative OSC 8 paths with a leading slash.
            let relative = String(path.drop(while: { $0 == "/" }))
            guard !relative.isEmpty else { continue }
            let candidate = base.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
