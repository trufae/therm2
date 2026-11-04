import AppKit
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct LayoutTests {
    init() { _ = NSApplication.shared }

    private func tab() -> TerminalTab {
        let tab = TerminalTab(directory: NSTemporaryDirectory())
        tab.root.frame = NSRect(x: 0, y: 0, width: 960, height: 600)
        return tab
    }

    @Test func fullscreenCoversMenuBarWithBlackBackingAndRestoresWindow() throws {
        let preferences = Preferences.shared
        let originalNativeFullscreen = preferences.useNativeFullscreen
        preferences.useNativeFullscreen = false
        defer { preferences.useNativeFullscreen = originalNativeFullscreen }
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        let screen = try #require(window.screen ?? NSScreen.main)
        let originalBackground = preferences.backgroundColor
        defer {
            if controller.isFullscreen { controller.toggleFullscreen() }
            window.close()
            preferences.backgroundColor = originalBackground
        }
        preferences.backgroundColor = .blue
        controller.applyPreferences(.background)
        let originalFrame = window.frame
        let originalStyle = window.styleMask
        controller.toggleFullscreen()
        #expect(controller.isFullscreen)
        #expect(window.frame == screen.frame)
        #expect(window.backgroundColor == .black)
        #expect(window.constrainFrameRect(screen.frame, to: screen) == screen.frame)
        preferences.backgroundColor = .red
        controller.applyPreferences(.background)
        #expect(window.backgroundColor == .black)
        controller.toggleFullscreen()
        #expect(!controller.isFullscreen)
        #expect(window.styleMask == originalStyle)
        #expect(window.frame == originalFrame)
        #expect(window.backgroundColor == .red)
    }

    @Test func changingFullscreenModeWhileFastFullscreenRestoresWindowBeforeUsingNativeMode() throws {
        let preferences = Preferences.shared
        let original = preferences.useNativeFullscreen
        preferences.useNativeFullscreen = false
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer {
            if controller.isFastFullscreen { controller.toggleFullscreen() }
            window.close()
            preferences.useNativeFullscreen = original
        }
        let frame = window.frame
        let style = window.styleMask
        #expect(window.collectionBehavior.contains(.fullScreenNone))
        controller.toggleFullscreen()
        #expect(controller.isFastFullscreen)
        preferences.useNativeFullscreen = true
        controller.applyPreferences(.fullscreen)
        #expect(controller.isFastFullscreen)
        controller.toggleFullscreen()
        #expect(!controller.isFullscreen)
        #expect(window.frame == frame)
        #expect(window.styleMask == style)
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        preferences.useNativeFullscreen = false
        controller.applyPreferences(.fullscreen)
        #expect(window.collectionBehavior.contains(.fullScreenNone))
        controller.toggleFullscreen()
        #expect(controller.isFastFullscreen)
    }

    @Test func mixedSplitsPreserveSessionsAndCollapseToOriginalPane() throws {
        let tab = tab()
        let original = tab.activePane
        let right = try #require(tab.split(vertical: true))
        let topRight = try #require(tab.split(vertical: false))
        #expect(tab.panes.count == 3)
        #expect((tab.root as? SplitView)?.isVertical == true)
        #expect((topRight.layoutView.superview as? SplitView)?.isVertical == false)
        #expect(tab.panes[0] === original)
        #expect(right.directory == NSTemporaryDirectory())

        tab.close(right)
        #expect(tab.panes.count == 2)
        #expect(tab.activePane === topRight)
        #expect(topRight.layoutView.superview === tab.root)

        tab.close(topRight)
        #expect(tab.root === original.layoutView)
        #expect(tab.activePane === original)
        #expect(tab.panes.count == 1)
        #expect(original.bounds.size == NSSize(width: 960, height: 600))
    }

    @Test func closingInactivePanePreservesFocusAndReleasesView() throws {
        weak var removed: TerminalPane?
        try autoreleasepool {
            let tab = tab()
            removed = tab.activePane
            let right = try #require(tab.split(vertical: true))
            tab.close(try #require(removed))
            #expect(tab.activePane === right)
            #expect(tab.root === right.layoutView)
        }
        #expect(removed == nil)
    }

    @Test func closingNestedBranchKeepsOtherSplitRatios() throws {
        let tab = tab()
        let left = tab.activePane
        let right = try #require(tab.split(vertical: true))
        let outer = try #require(tab.root as? SplitView)
        outer.setPosition(350, ofDividerAt: 0)
        let width = left.frame.width
        let upperRight = try #require(tab.split(vertical: false))
        tab.close(right)
        #expect(tab.root === outer)
        #expect(left.frame.width == width)
        #expect(outer.subviews[1] === upperRight.layoutView)
    }

    @Test func borderMarginInsetsSplitPanesAndSurvivesMaximizationAndResize() throws {
        let preferences = Preferences.shared
        let original = preferences.borderMargin
        preferences.borderMargin = 12
        defer { preferences.borderMargin = original }
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let third = try #require(tab.split(vertical: false))

        func expectMargins() {
            for pane in tab.panes {
                #expect(pane.frame == pane.layoutView.bounds.insetBy(dx: 12, dy: 12))
            }
        }
        expectMargins()
        tab.root.frame.size = NSSize(width: 1_200, height: 800)
        expectMargins()
        let frames = tab.panes.map { $0.layoutView.frame }
        tab.togglePaneMaximized()
        #expect(third.frame == tab.displayedView.bounds.insetBy(dx: 12, dy: 12))
        tab.togglePaneMaximized()
        #expect(tab.panes.map { $0.layoutView.frame } == frames)
        expectMargins()
        tab.close(second)
        tab.close(third)
        #expect(tab.root === first.layoutView)
        #expect(first.frame == tab.root.bounds.insetBy(dx: 12, dy: 12))
        #expect(SplitView.minimumSize(of: tab.root) == NSSize(width: 184, height: 114))
    }

    @Test func panesCannotBeSplitBelowMinimumSize() {
        let tab = tab()
        tab.root.frame.size = NSSize(width: 320, height: 180)
        #expect(tab.split(vertical: true) == nil)
        #expect(tab.split(vertical: false) == nil)
        #expect(tab.panes.count == 1)
    }

    @Test func dividerMovementRespectsNestedMinimumSizes() throws {
        let tab = tab()
        _ = try #require(tab.split(vertical: true))
        let split = try #require(tab.root as? SplitView)
        tab.resizeSplit(vertical: true, by: -10_000)
        #expect(split.subviews[0].frame.width >= 160)
        tab.resizeSplit(vertical: true, by: 10_000)
        #expect(split.subviews[1].frame.width >= 160)
        #expect(SplitView.minimumSize(of: split) == NSSize(width: 321, height: 90))
    }

    @Test func focusCyclesInBothDirections() throws {
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let third = try #require(tab.split(vertical: false))
        tab.cyclePane(by: 1)
        #expect(tab.activePane === first)
        tab.cyclePane(by: -1)
        #expect(tab.activePane === third)
        tab.cyclePane(by: -1)
        #expect(tab.activePane === second)
    }

    @Test func releasingTabReleasesWholeSplitTree() throws {
        weak var first: TerminalPane?
        weak var second: TerminalPane?
        weak var branch: NSView?
        try autoreleasepool {
            let owner = tab()
            first = owner.activePane
            let pane = try #require(owner.split(vertical: true))
            second = pane
            branch = owner.root
        }
        #expect(first == nil)
        #expect(second == nil)
        #expect(branch == nil)
    }

    @Test func terminalTitlesAreBoundedAndSanitized() {
        let pane = tab().activePane
        pane.updateTitle("\u{1B}\n" + String(repeating: "x", count: 1_000))
        #expect(pane.title == String(repeating: "x", count: 256))
        pane.updateTitle("")
        #expect(pane.title.isEmpty)
    }

    @Test func ansiTitlesCombineAcrossPanesAndSurviveFocusAndMaximization() async throws {
        let tab = tab()
        let first = tab.activePane
        #expect(tab.title.isEmpty)
        let second = try #require(tab.split(vertical: true))
        let third = try #require(tab.split(vertical: false))
        first.feed(text: "\u{1b}]0;build\u{7}")
        third.feed(text: "\u{1b}]2;logs\u{1b}\\")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(first.title == "build")
        #expect(second.title.isEmpty)
        #expect(third.title == "logs")
        #expect(tab.title == "build · logs")
        tab.cyclePane(by: 1)
        tab.togglePaneMaximized()
        #expect(tab.title == "build · logs")
        third.feed(text: "\u{1b}]2;\u{7}")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(tab.title == "build")
        tab.close(first)
        #expect(tab.title.isEmpty)
    }

    @Test func directoryUpdatesAcceptOnlyExistingLocalDirectories() {
        let pane = tab().activePane
        let initial = pane.directory
        pane.updateDirectory("file://remote.invalid/etc")
        #expect(pane.directory == initial)
        pane.updateDirectory("file:///this/path/does/not/exist")
        #expect(pane.directory == initial)
        pane.updateDirectory("file:///etc")
        #expect(pane.directory == "/etc")
    }

    @Test func mousePositionSelectsNestedPanesWithoutClicking() throws {
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let third = try #require(tab.split(vertical: false))
        let window = TerminalWindow(contentRect: tab.root.frame, styleMask: [.titled],
                                    backing: .buffered, defer: false)
        let host = NSView(frame: tab.root.frame)
        window.contentView = host
        host.addSubview(tab.root)
        for pane in [first, third, second] {
            let center = NSPoint(x: pane.bounds.midX, y: pane.bounds.midY)
            window.focusPane(at: pane.convert(center, to: nil))
            #expect(tab.activePane === pane)
            #expect(window.firstResponder === pane)
        }
        // Chrome outside the terminal must not change the selected pane.
        window.focusPane(at: NSPoint(x: -20, y: -20))
        #expect(tab.activePane === second)
    }

    @Test func movingInsideActivePanePreservesTextFieldFocus() throws {
        let tab = tab()
        let pane = try #require(tab.split(vertical: true))
        let window = TerminalWindow(contentRect: tab.root.frame, styleMask: [.titled],
                                    backing: .buffered, defer: false)
        let host = NSView(frame: tab.root.frame)
        window.contentView = host
        host.addSubview(tab.root)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        pane.addSubview(field)
        window.makeFirstResponder(field)
        let responder = window.firstResponder
        window.focusPane(at: pane.convert(NSPoint(x: 200, y: 50), to: nil))
        #expect(window.firstResponder === responder)
    }

    @Test func pinchAccumulatesSmallDeltasAndChangesOnlyItsPane() throws {
        let tab = tab()
        let first = tab.activePane
        let zoomed = try #require(tab.split(vertical: true))
        let initialFont = zoomed.font
        zoomed.applyMagnification(0.001, phase: .began)
        #expect(zoomed.font === initialFont)
        for _ in 0..<50 { zoomed.applyMagnification(0.001, phase: .changed) }
        #expect(zoomed.font.pointSize == 14)
        #expect(first.font.pointSize == TerminalPane.defaultFontSize)
        zoomed.applyMagnification(0, phase: .ended)
    }

    @Test func pinchAndKeyboardShareBoundsAndNewGesturesStartAtCurrentSize() {
        let pane = tab().activePane
        pane.applyMagnification(100, phase: .began)
        #expect(pane.font.pointSize == 1024)
        pane.applyMagnification(-0.5, phase: .changed)
        #expect(pane.font.pointSize == 512)
        pane.applyMagnification(0, phase: .ended)
        pane.setFontSize(20)
        pane.applyMagnification(0.1, phase: .began)
        #expect(pane.font.pointSize == 22)
        pane.applyMagnification(0, phase: .cancelled)
        pane.setFontSize(10_000)
        #expect(pane.font.pointSize == 1024)
        pane.setFontSize(-100)
        #expect(pane.font.pointSize == 4)
        pane.applyMagnification(-0.9, phase: .began)
        #expect(pane.font.pointSize == 4)
        pane.applyMagnification(0.5, phase: .changed)
        #expect(pane.font.pointSize == 6)
        pane.setFontSize(.nan)
        #expect(pane.font.pointSize == 6)
    }

    @Test func maximizingPaneRestoresNestedFramesAndSessionOrder() throws {
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let outer = try #require(tab.root as? SplitView)
        outer.setPosition(350, ofDividerAt: 0)
        let third = try #require(tab.split(vertical: false))
        let frames = tab.panes.map(\.frame)
        tab.togglePaneMaximized()
        #expect(tab.isPaneMaximized)
        #expect(tab.displayedView === third.layoutView)
        #expect(third.layoutView.frame == outer.bounds)
        #expect(tab.panes.elementsEqual([first, second, third], by: { $0 === $1 }))
        tab.togglePaneMaximized()
        #expect(!tab.isPaneMaximized)
        #expect(tab.displayedView === outer)
        #expect(tab.panes.map(\.frame) == frames)
    }

    @Test func cyclingAndClosingPanesWhileMaximizedKeepsValidTree() throws {
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let third = try #require(tab.split(vertical: false))
        tab.togglePaneMaximized()
        tab.cyclePane(by: 1)
        #expect(tab.displayedView === first.layoutView)
        #expect(tab.isPaneMaximized)
        // A background process exiting must not discard the maximized state.
        tab.close(second)
        #expect(tab.isPaneMaximized)
        #expect(tab.displayedView === first.layoutView)
        tab.close(first)
        #expect(tab.activePane === third)
        #expect(tab.root === third.layoutView)
        #expect(!tab.isPaneMaximized)
        #expect(tab.panes.count == 1)
    }

    @Test func splittingRestoresMaximizedLayoutAndReleaseDoesNotRetainPanes() throws {
        weak var first: TerminalPane?
        weak var second: TerminalPane?
        try autoreleasepool {
            let tab = tab()
            first = tab.activePane
            let pane = try #require(tab.split(vertical: true))
            second = pane
            tab.togglePaneMaximized()
            _ = try #require(tab.split(vertical: false))
            #expect(!tab.isPaneMaximized)
            #expect(tab.panes.count == 3)
            tab.togglePaneMaximized()
        }
        #expect(first == nil)
        #expect(second == nil)
    }
}
