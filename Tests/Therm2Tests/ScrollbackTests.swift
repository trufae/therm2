import AppKit
import Testing
@testable import SwiftTerm
@testable import Therm2

@Suite(.serialized) @MainActor
struct ScrollbackTests {
    init() { _ = NSApplication.shared }

    private func contents(_ pane: TerminalPane) -> String {
        String(decoding: pane.getBufferAsData(), as: UTF8.self)
    }

    @Test func limitedHistoryTrimsOldLinesAndUnlimitedHistoryGrowsAcrossResizes() {
        let preferences = Preferences.shared
        let originalLimit = preferences.scrollbackLimit
        let originalUnlimited = preferences.unlimitedScrollback
        defer {
            preferences.scrollbackLimit = originalLimit
            preferences.unlimitedScrollback = originalUnlimited
        }
        preferences.unlimitedScrollback = false
        preferences.scrollbackLimit = 20
        let limited = TerminalPane(directory: NSTemporaryDirectory())
        limited.feed(text: "DISCARDED\r\n" + String(repeating: "line\r\n", count: 200))
        #expect(!contents(limited).contains("DISCARDED"))
        limited.withTerminal { terminal in
            #expect(terminal.normalBuffer.yBase == 20)
        }

        preferences.unlimitedScrollback = true
        let unlimited = TerminalPane(directory: NSTemporaryDirectory())
        let line = String(repeating: "x", count: 75) + "\r\n"
        unlimited.feed(text: "RETAINED\r\n" + String(repeating: line, count: 3_000))
        #expect(contents(unlimited).contains("RETAINED"))
        unlimited.withTerminal { terminal in
            #expect(terminal.normalBuffer.yBase > 2_900)
            #expect(terminal.normalBuffer.lines.maxLength < 10_000)
        }
        unlimited.frame.size = NSSize(width: 160, height: 700)
        #expect(contents(unlimited).contains("RETAINED"))
        unlimited.withTerminal { terminal in
            #expect(terminal.normalBuffer.yBase > 6_000)
        }
        unlimited.frame.size = NSSize(width: 900, height: 400)
        #expect(contents(unlimited).contains("RETAINED"))
        unlimited.changeScrollback(10)
        #expect(!contents(unlimited).contains("RETAINED"))
        unlimited.withTerminal { terminal in
            #expect(terminal.normalBuffer.yBase == 10)
        }
        unlimited.changeScrollback(0)
        unlimited.withTerminal { terminal in
            #expect(terminal.normalBuffer.yBase == 0)
        }
    }

    @Test func changingHistoryUpdatesHiddenTabsAndSplitPanes() throws {
        let preferences = Preferences.shared
        let originalLimit = preferences.scrollbackLimit
        let originalUnlimited = preferences.unlimitedScrollback
        preferences.unlimitedScrollback = false
        preferences.scrollbackLimit = 100
        let controller = TerminalWindowController()
        defer {
            controller.window?.close()
            preferences.scrollbackLimit = originalLimit
            preferences.unlimitedScrollback = originalUnlimited
        }
        controller.newTab()
        controller.newTab()
        let tab = try #require(controller.selectedTab)
        _ = try #require(tab.split(vertical: true))
        preferences.unlimitedScrollback = true
        controller.applyPreferences(.scrollback)
        for pane in controller.tabs.flatMap(\.panes) {
            pane.feed(text: "HISTORY\r\n" + String(repeating: "line\r\n", count: 2_000))
            #expect(contents(pane).contains("HISTORY"))
        }
        preferences.scrollbackLimit = 15
        preferences.unlimitedScrollback = false
        controller.applyPreferences(.scrollback)
        for pane in controller.tabs.flatMap(\.panes) {
            #expect(!contents(pane).contains("HISTORY"))
            pane.withTerminal { terminal in
                #expect(terminal.normalBuffer.yBase == 15)
            }
        }
    }

    @Test func alternateScreenStaysBoundedAndFullResetKeepsUnlimitedMode() {
        let preferences = Preferences.shared
        let original = preferences.unlimitedScrollback
        preferences.unlimitedScrollback = true
        defer { preferences.unlimitedScrollback = original }
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        pane.feed(text: "NORMAL\r\n\u{1b}[?1049h" + String(repeating: "alternate\r\n", count: 2_000))
        pane.withTerminal { terminal in
            #expect(terminal.altBuffer.yBase == 0)
            #expect(terminal.altBuffer.lines.count == terminal.rows)
        }
        pane.feed(text: "\u{1b}[?1049l")
        #expect(contents(pane).contains("NORMAL"))
        pane.feed(text: "\u{1b}cAFTER_RESET\r\n" + String(repeating: "line\r\n", count: 2_000))
        #expect(contents(pane).contains("AFTER_RESET"))
    }
}
