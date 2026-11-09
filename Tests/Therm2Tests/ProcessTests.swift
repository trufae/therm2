import AppKit
import Darwin
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct ProcessTests {
    init() { _ = NSApplication.shared }

    private func waitFor(_ text: String, in pane: TerminalPane) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !String(decoding: pane.getBufferAsData(), as: UTF8.self).contains(text) {
            // Check the buffer first: the main actor can resume after the deadline
            // even though the background PTY reader delivered the output in time.
            guard ContinuousClock.now < deadline else {
                Issue.record("PTY did not produce \(text)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func launchCommandRunsInPTYWithLiteralArgumentsAndClosesItsPane() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Therm2-Command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("cwd-marker"))
        let command = try #require(try LaunchCommand.parse(["-e", "sh", "-c", """
            test -t 0 && test -t 1 && printf 'PTY_OK\n'
            printf 'ARG:<%s>\n' "$@"
            test -f cwd-marker && printf 'CWD_OK\n'
            printf 'TERM:<%s>\n' "$TERM"
            printf 'READY\n'
            read -r line
            """, "sh", "two words", "", "$HOME; * | >", "-e"], directory: root.path, path: "/bin"))
        let controller = TerminalWindowController()
        defer { controller.window?.close() }
        controller.newTab(command: command)
        let pane = try #require(controller.selectedTab?.activePane)
        try await waitFor("READY", in: pane)
        let output = String(decoding: pane.getBufferAsData(), as: UTF8.self)
        #expect(output.contains("PTY_OK"))
        for argument in ["two words", "", "$HOME; * | >", "-e"] {
            #expect(output.contains("ARG:<\(argument)>"))
        }
        #expect(output.contains("CWD_OK"))
        #expect(output.contains("TERM:<xterm-256color>"))

        // A new split and tab must run the login shell, not repeat the command.
        let firstTab = try #require(controller.selectedTab)
        controller.split(vertical: true)
        let sibling = firstTab.activePane
        #expect(sibling !== pane)
        #expect(sibling.process.running)
        sibling.send(txt: "printf 'SHELL_%s\\n' 'SPLIT'\n")
        try await waitFor("SHELL_SPLIT", in: sibling)
        firstTab.close(sibling)
        controller.newTab()
        let newPane = try #require(controller.selectedTab?.activePane)
        #expect(newPane !== pane)
        #expect(newPane.process.running)
        newPane.send(txt: "printf 'SHELL_%s\\n' 'TAB'\n")
        try await waitFor("SHELL_TAB", in: newPane)

        pane.send(txt: "done\n")
        let deadline = ContinuousClock.now + .seconds(5)
        while controller.tabs.contains(where: { $0 === firstTab }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.tabs.count == 1)
        #expect(controller.selectedTab?.activePane === newPane)
        #expect(!pane.process.running)
    }

    @Test func splitInheritsActualShellDirectoryAndNotifiesItsProcessOfResize() async throws {
        let tab = TerminalTab(directory: NSHomeDirectory())
        tab.root.frame = NSRect(x: 0, y: 0, width: 960, height: 600)
        let pane = tab.activePane
        pane.startProcess(executable: "/bin/sh", args: ["-c", """
            trap 'printf "WINCH:"; stty size' WINCH
            printf 'READY\n'
            while :; do sleep 1; done
            """], currentDirectory: NSTemporaryDirectory())
        defer { pane.terminate() }
        try await waitFor("READY", in: pane)
        let original = pane.terminalDimensions
        let sibling = try #require(tab.split(vertical: true))
        #expect(URL(fileURLWithPath: sibling.directory).resolvingSymlinksInPath().path ==
                URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path)
        let resized = pane.terminalDimensions
        #expect(resized.cols < original.cols)
        var kernelSize = winsize()
        #expect(ioctl(pane.process.childfd, TIOCGWINSZ, &kernelSize) == 0)
        #expect(Int(kernelSize.ws_col) == resized.cols)
        #expect(Int(kernelSize.ws_row) == resized.rows)
        try await waitFor("WINCH:", in: pane)
    }

    @Test func missingProcessesAndDirectoriesFailCleanly() {
        #expect(WorkingDirectory.path(of: -1) == nil)
        #expect(!WorkingDirectory.valid("/this/directory/does/not/exist"))
        #expect(WorkingDirectory.path(of: getpid()) != nil)
    }

    @Test func linkResolutionFollowsShellCwdEvenWhenNewSessionsStartAtHome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Therm2-Cwd-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("patch.txt")
        try Data().write(to: file)
        let original = Preferences.shared.directoryMode
        Preferences.shared.directoryMode = .home
        defer { Preferences.shared.directoryMode = original }
        let pane = TerminalPane(directory: NSHomeDirectory())
        pane.startProcess(executable: "/bin/sh", args: ["-c", """
            cd "$1" || exit 1
            printf 'READY\n'
            while :; do sleep 1; done
            """, "sh", root.path], currentDirectory: NSHomeDirectory())
        defer { pane.terminate() }
        try await waitFor("READY", in: pane)
        #expect(pane.newSessionDirectory == NSHomeDirectory())
        let resolved = try #require(pane.localLinkResolver?("/patch.txt"))
        #expect(resolved.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
    }
}
