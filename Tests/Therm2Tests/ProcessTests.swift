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
}
