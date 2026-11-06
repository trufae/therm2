import AppKit
import Testing
@testable import SwiftTerm
@testable import Therm2

@Suite(.serialized) @MainActor
struct LinkTests {
    init() { _ = NSApplication.shared }

    private final class Recorder: TerminalViewDelegate {
        var links: [String] = []
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { links.append(link) }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Therm2-Links-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ path: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: url)
        return url
    }

    /// Exercise the actual validation/dispatch path without launching another app or showing a modal.
    private func activate(_ link: String, in pane: TerminalPane, explicit: Bool = true,
                          response: NSApplication.ModalResponse = .alertFirstButtonReturn) async
        -> (links: [String], alerts: [String]) {
        let recorder = Recorder()
        pane.terminalDelegate = recorder
        var alerts: [String] = []
        pane.activateLink(link, params: [:], isExplicit: explicit) { alert, _, completion in
            alerts.append(alert.messageText)
            completion(response)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        return (recorder.links, alerts)
    }

    private func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
    }

    @Test(arguments: [false, true])
    func relativeAndLeadingSlashLinksUseThePaneDirectory(explicit: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let patch = try file("patches/swiftterm-cursor-color.patch", in: root)
        let spaced = try file("patches/a patch.patch", in: root)
        let literal = try file("patches/source.swift:42", in: root)
        let pane = TerminalPane(directory: root.path)
        for (link, expected) in [
            ("patches/swiftterm-cursor-color.patch", patch),
            ("/patches/swiftterm-cursor-color.patch", patch),
            ("./patches/swiftterm-cursor-color.patch", patch),
            ("/patches/swiftterm-cursor-color.patch:12:4", patch),
            ("patches/a patch.patch", spaced),
            ("patches/source.swift:42", literal),
            ("patches", patch.deletingLastPathComponent()),
        ] {
            let result = await activate(link, in: pane, explicit: explicit)
            #expect(result.links == [canonical(expected)])
            #expect(result.alerts.isEmpty)
        }
    }

    @Test func existingAbsoluteAndHomePathsTakePrecedence() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let absolute = try file("absolute.txt", in: root)
        let project = root.appendingPathComponent("project")
        _ = try file(String(absolute.path.dropFirst()), in: project)
        let pane = TerminalPane(directory: project.path)
        for link in [absolute.path, absolute.absoluteString, absolute.path + ":12:4"] {
            let result = await activate(link, in: pane)
            #expect(result.links == [canonical(absolute)])
            #expect(result.alerts.isEmpty)
        }
        let home = await activate("~", in: pane)
        #expect(home.links == [canonical(URL(fileURLWithPath: NSHomeDirectory()))])
        #expect(home.alerts.isEmpty)
    }

    @Test func panesResolveIndependentlyAndFollowDirectoryUpdates() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try file("first/patches/fix.patch", in: root)
        let second = try file("second/patches/fix.patch", in: root)
        let firstDirectory = root.appendingPathComponent("first")
        let secondDirectory = root.appendingPathComponent("second")
        let pane = TerminalPane(directory: firstDirectory.path)
        let sibling = TerminalPane(directory: secondDirectory.path)
        #expect(await activate("/patches/fix.patch", in: pane).links == [canonical(first)])
        #expect(await activate("/patches/fix.patch", in: sibling).links == [canonical(second)])
        pane.updateDirectory(secondDirectory.absoluteString)
        #expect(await activate("/patches/fix.patch", in: pane).links == [canonical(second)])
    }

    @Test(arguments: [false, true])
    func missingAndUnsafeFilesRemainBlocked(explicit: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try file("patches/run.command", in: root)
        let executable = try file("patches/executable", in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("patches/disguised.txt"),
                                                 withDestinationURL: command)
        _ = try file("patches/hidden\u{202E}.txt", in: root)
        let pane = TerminalPane(directory: root.path)
        for link in ["/patches/missing.patch", "patches/run.command", "/patches/executable",
                     "patches/disguised.txt", "patches/hidden\u{202E}.txt", ""] {
            let result = await activate(link, in: pane, explicit: explicit)
            #expect(result.links.isEmpty)
            #expect(result.alerts == ["Link blocked"])
        }
        // An unresolved implicit link must not accidentally use Therm2's own process cwd.
        #expect(FileManager.default.fileExists(atPath: "Package.swift"))
        let result = await activate("Package.swift", in: pane, explicit: explicit)
        #expect(result.links.isEmpty)
        #expect(result.alerts == ["Link blocked"])
    }

    @Test func webAndCustomSchemesKeepTheirUsualPolicy() async {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        for link in ["https://example.com/patches/fix.patch", "mailto:example@example.com"] {
            let result = await activate(link, in: pane)
            #expect(result.links == [link])
            #expect(result.alerts.isEmpty)
        }
        let cancelled = await activate("ssh://example.com", in: pane)
        #expect(cancelled.links.isEmpty)
        #expect(cancelled.alerts == ["Open link from terminal output?"])
        let confirmed = await activate("ssh://example.com", in: pane, response: .alertSecondButtonReturn)
        #expect(confirmed.links == ["ssh://example.com"])
    }
}
