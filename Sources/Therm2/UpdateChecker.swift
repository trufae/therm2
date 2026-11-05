import AppKit

@MainActor
enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/trufae/therm2/releases")!
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/trufae/therm2/releases/latest")!

    private struct Release: Decodable {
        let tag_name: String
    }

    static func checkOnStartup() {
        guard Preferences.shared.checkForUpdatesOnStartup,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !current.isEmpty else { return }
        Task {
            guard let upstream = await availableVersion(currentVersion: current),
                  Preferences.shared.checkForUpdatesOnStartup,
                  let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: {
                      $0.isVisible && $0.windowController is TerminalWindowController
                  }) else { return }
            let alert = makeAlert(currentVersion: current, upstreamVersion: upstream)
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesURL) }
            }
        }
    }

    static func availableVersion(currentVersion: String, session: URLSession = .shared) async -> String? {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Therm2/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        let version = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Release tags match the bundle version; any different tag is worth showing.
        return !version.isEmpty && version != currentVersion ? version : nil
    }

    static func makeAlert(currentVersion: String, upstreamVersion: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Therm2 release available"
        alert.informativeText = "Current version: \(currentVersion)\nLatest release: \(upstreamVersion)"
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Cancel")
        return alert
    }
}
