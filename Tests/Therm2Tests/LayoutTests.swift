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

    @Test func backgroundAndDimmingSettingsKeepInactivePanesDarker() throws {
        let preferences = Preferences.shared
        let originalBackground = preferences.backgroundColor
        let originalGlass = preferences.glassyWindow
        let originalDimming = preferences.inactiveTextDimming
        preferences.backgroundColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        preferences.glassyWindow = false
        preferences.inactiveTextDimming = 0.3
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer {
            window.close()
            preferences.backgroundColor = originalBackground
            preferences.glassyWindow = originalGlass
            preferences.inactiveTextDimming = originalDimming
        }
        controller.newTab()
        let tab = try #require(controller.selectedTab)
        let inactive = tab.activePane
        let active = try #require(tab.split(vertical: true))

        func expectBackgrounds(brightness: CGFloat, alpha: CGFloat = 1) throws {
            let color = try #require(inactive.nativeBackgroundColor.usingColorSpace(.sRGB))
            #expect(abs(color.redComponent - preferences.backgroundColor.redComponent * brightness) < 0.000_001)
            #expect(abs(color.greenComponent - preferences.backgroundColor.greenComponent * brightness) < 0.000_001)
            #expect(abs(color.blueComponent - preferences.backgroundColor.blueComponent * brightness) < 0.000_001)
            #expect(color.alphaComponent == alpha)
            #expect(active.nativeBackgroundColor == preferences.terminalBackgroundColor)
        }

        try expectBackgrounds(brightness: 0.7)
        preferences.backgroundColor = NSColor(srgbRed: 0.6, green: 0.3, blue: 0.1, alpha: 1)
        controller.applyPreferences(.background)
        try expectBackgrounds(brightness: 0.7)
        preferences.inactiveTextDimming = 0.5
        controller.applyPreferences(.dimming)
        try expectBackgrounds(brightness: 0.5)
        preferences.glassyWindow = true
        controller.applyPreferences(.glass)
        try expectBackgrounds(brightness: 0.5, alpha: 0.18)
        preferences.backgroundColor = .black
        controller.applyPreferences(.background)
        try expectBackgrounds(brightness: 0.5, alpha: 0.18)
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

    @Test func glassTogglesLiveAcrossTabsAndFullscreenWithoutChangingFocusOrGeometry() throws {
        let preferences = Preferences.shared
        let originalGlass = preferences.glassyWindow
        let originalFullscreen = preferences.useNativeFullscreen
        preferences.glassyWindow = false
        preferences.useNativeFullscreen = false
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer {
            if controller.isFastFullscreen { controller.toggleFullscreen() }
            window.close()
            preferences.glassyWindow = originalGlass
            preferences.useNativeFullscreen = originalFullscreen
        }
        controller.newTab()
        controller.newTab()
        let tab = try #require(controller.selectedTab)
        _ = try #require(tab.split(vertical: true))
        tab.togglePaneMaximized()
        let responder = window.firstResponder
        let frame = window.frame
        let paneFrames = controller.tabs.flatMap(\.panes).map(\.frame)
        let content = try #require(window.contentView)

        preferences.glassyWindow = true
        controller.applyPreferences(.glass)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.hasShadow)
        #expect(window.frame == frame)
        #expect(window.firstResponder === responder)
        #expect(controller.tabs.flatMap(\.panes).map(\.frame) == paneFrames)
        if #available(macOS 26.0, *) {
            let glass = try #require(window.contentView as? NSGlassEffectView)
            #expect(glass.contentView === content)
            #expect(glass.style == .clear)
        } else {
            #expect(window.contentView is NSVisualEffectView)
        }
        for pane in controller.tabs.flatMap(\.panes) {
            #expect(pane.backgroundOpacity == 0.18)
            #expect(pane.nativeForegroundColor.alphaComponent == 1)
            #expect(!pane.layoutView.isOpaque)
        }
        controller.toggleFullscreen()
        #expect(window.backgroundColor == .clear)
        #expect(!window.isOpaque)
        controller.toggleFullscreen()
        #expect(window.backgroundColor == .clear)

        preferences.glassyWindow = false
        controller.applyPreferences(.glass)
        #expect(window.contentView === content)
        #expect(window.isOpaque)
        #expect(window.backgroundColor == preferences.backgroundColor)
        #expect(!window.hasShadow)
        #expect(window.firstResponder === responder)
        for pane in controller.tabs.flatMap(\.panes) {
            #expect(pane.backgroundOpacity == 1)
            #expect(pane.layoutView.isOpaque)
        }
        tab.togglePaneMaximized()
        #expect(tab.panes.count == 2)
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

    @Test func movingMaximizedPaneBetweenTabsPreservesNestedTreesAndFocus() throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        let source = try #require(controller.selectedTab)
        let left = source.activePane
        let right = try #require(source.split(vertical: true))
        let outer = try #require(source.root as? SplitView)
        outer.setPosition(350, ofDividerAt: 0)
        let width = left.layoutView.frame.width
        let moved = try #require(source.split(vertical: false))
        let movedView = moved.layoutView
        moved.updateTitle("moving")
        moved.feed(text: "\r\npreserved output\r\n")
        source.togglePaneMaximized()

        controller.newTab()
        let destination = try #require(controller.selectedTab)
        let existing = destination.activePane
        let neighbor = try #require(destination.split(vertical: false))
        destination.togglePaneMaximized()
        controller.selectTab(at: 0)
        controller.moveActivePane(toTabAt: 1)

        #expect(controller.tabs.count == 2)
        #expect(controller.selectedTab === destination)
        #expect(window.firstResponder === moved)
        #expect(source.root === outer)
        #expect(source.panes.elementsEqual([left, right], by: { $0 === $1 }))
        #expect(source.activePane === right)
        #expect(source.isPaneMaximized)
        #expect(source.displayedView === right.layoutView)
        #expect(!destination.isPaneMaximized)
        #expect(destination.panes.elementsEqual([existing, neighbor, moved], by: { $0 === $1 }))
        #expect(destination.activePane === moved)
        #expect(moved.layoutView === movedView)
        #expect(moved.tab === destination)
        #expect(moved.processDelegate === destination)
        #expect(destination.title == "moving")
        #expect(String(decoding: moved.getBufferAsData(), as: UTF8.self).contains("preserved output"))
        source.togglePaneMaximized()
        #expect(left.layoutView.frame.width == width)
        // Exit callbacks must now remove the pane from its destination.
        destination.processTerminated(source: moved, exitCode: 0)
        #expect(destination.panes.count == 2)
        #expect(source.panes.count == 2)
    }

    @Test(arguments: [0, 1]) func movingOnlyPaneClosesSourceAndKeepsSession(destinationIndex: Int) throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        controller.newTab()
        let destination = controller.tabs[destinationIndex]
        controller.selectTab(at: 1 - destinationIndex)
        let moved = try #require(controller.selectedTab?.activePane)
        let pid = moved.process.shellPid
        #expect(moved.process.running)

        controller.moveActivePane(toTabAt: destinationIndex)

        #expect(controller.tabs.count == 1)
        #expect(controller.selectedIndex == 0)
        #expect(controller.selectedTab === destination)
        #expect(destination.panes.count == 2)
        #expect(destination.activePane === moved)
        #expect(window.firstResponder === moved)
        #expect(moved.process.shellPid == pid)
        #expect(moved.process.running)
        #expect(moved.tab === destination)
        #expect(moved.processDelegate === destination)
        destination.close(moved)
        #expect(destination.panes.count == 1)
        #expect(controller.tabs.count == 1)
    }

    @Test(arguments: [1, 8], [false, true])
    func movingToMissingTabCreatesOneTabAndKeepsSession(destinationIndex: Int, splitSource: Bool) throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        let source = try #require(controller.selectedTab)
        let original = source.activePane
        if splitSource {
            controller.split(vertical: true)
            source.togglePaneMaximized()
        }
        let moved = source.activePane
        let view = moved.layoutView
        let pid = moved.process.shellPid
        // Keep the marker on its own line so a shell prompt cannot overwrite it.
        moved.feed(text: "\r\npreserved output\r\n")
        #expect(moved.process.running)

        controller.moveActivePane(toTabAt: destinationIndex)

        let destination = try #require(controller.selectedTab)
        #expect(destination !== source)
        #expect(controller.tabs.count == (splitSource ? 2 : 1))
        #expect(controller.selectedIndex == controller.tabs.count - 1)
        #expect(destination.controller === controller)
        #expect(destination.panes.count == 1)
        #expect(destination.root === view)
        #expect(destination.activePane === moved)
        #expect(!destination.isPaneMaximized)
        #expect(window.firstResponder === moved)
        #expect(moved.process.shellPid == pid)
        #expect(moved.process.running)
        #expect(moved.tab === destination)
        #expect(moved.processDelegate === destination)
        #expect(moved.foregroundBrightness == 1)
        #expect(String(decoding: moved.getBufferAsData(), as: UTF8.self).contains("preserved output"))
        if splitSource {
            #expect(controller.tabs[0] === source)
            #expect(source.panes.count == 1)
            #expect(source.activePane === original)
        }
        destination.processTerminated(source: moved, exitCode: 0)
        #expect(controller.tabs.count == (splitSource ? 1 : 0))
    }

    @Test func movingToCurrentOrInvalidTabLeavesMaximizedPaneUnchanged() throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        let source = try #require(controller.selectedTab)
        let pane = try #require(source.split(vertical: true))
        source.togglePaneMaximized()
        let view = source.displayedView
        for index in [-1, 0] { controller.moveActivePane(toTabAt: index) }
        #expect(controller.tabs.count == 1)
        #expect(source.panes.count == 2)
        #expect(source.isPaneMaximized)
        #expect(source.displayedView === view)
        #expect(source.activePane === pane)
        #expect(window.firstResponder === pane)
    }

    @Test(arguments: ["@", "\""]) func shiftedNumberShortcutMovesPane(shiftedCharacter: String) throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        let source = try #require(controller.selectedTab)
        let moved = try #require(source.split(vertical: true))
        controller.newTab()
        let destination = try #require(controller.selectedTab)
        controller.selectTab(at: 0)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: shiftedCharacter,
            charactersIgnoringModifiers: shiftedCharacter, isARepeat: false, keyCode: 19))

        #expect(window.performKeyEquivalent(with: event))
        #expect(controller.selectedTab === destination)
        #expect(destination.activePane === moved)
        #expect(source.panes.count == 1)
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

    @Test func swappingSiblingPanesKeepsSessionsFocusAndSplitSizes() throws {
        let controller = TerminalWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.newTab()
        let tab = try #require(controller.selectedTab)
        let first = tab.activePane
        controller.split(vertical: true)
        let second = tab.activePane
        let split = try #require(tab.root as? SplitView)
        split.setPosition(350, ofDividerAt: 0)
        let frames = tab.panes.map { $0.layoutView.frame }
        let pids = [first, second].map { $0.process.shellPid }
        first.updateTitle("first")
        second.updateTitle("second")
        // The login shell may print its first prompt while this test is running.
        first.feed(text: "\r\npreserved output\r\n")
        window.makeFirstResponder(first)

        tab.swapPane(by: 1)

        #expect(tab.panes.elementsEqual([second, first], by: { $0 === $1 }))
        #expect(tab.activePane === first)
        #expect(window.firstResponder === first)
        #expect(tab.root === split)
        #expect(tab.panes.map { $0.layoutView.frame } == frames)
        #expect(tab.title == "second · first")
        #expect([first, second].map { $0.process.shellPid } == pids)
        #expect(first.process.running && second.process.running)
        #expect(String(decoding: first.getBufferAsData(), as: UTF8.self).contains("preserved output"))
        for pane in tab.panes {
            #expect(pane.tab === tab)
            #expect(pane.processDelegate === tab)
        }
        tab.swapPane(by: -1)
        #expect(tab.panes.elementsEqual([first, second], by: { $0 === $1 }))
        #expect(tab.panes.map { $0.layoutView.frame } == frames)
        #expect(window.firstResponder === first)
    }

    @Test(arguments: [1, -1], [false, true])
    func swappingAcrossNestedSplitsWrapsAndPreservesMaximization(direction: Int, maximized: Bool) throws {
        let tab = tab()
        let first = tab.activePane
        let second = try #require(tab.split(vertical: true))
        let outer = try #require(tab.root as? SplitView)
        outer.setPosition(350, ofDividerAt: 0)
        let third = try #require(tab.split(vertical: false))
        let inner = try #require(second.layoutView.superview as? SplitView)
        inner.setPosition(200, ofDividerAt: 0)
        let frames = tab.panes.map { $0.layoutView.frame }
        let innerFrame = inner.frame
        tab.focus(first)
        if maximized { tab.togglePaneMaximized() }

        tab.swapPane(by: direction)

        let expected = direction == 1 ? [second, first, third] : [third, second, first]
        #expect(tab.panes.elementsEqual(expected, by: { $0 === $1 }))
        #expect(tab.activePane === first)
        #expect(tab.isPaneMaximized == maximized)
        if maximized {
            #expect(tab.displayedView === first.layoutView)
            tab.togglePaneMaximized()
        }
        #expect(tab.root === outer)
        #expect(outer.subviews[1] === inner)
        #expect(inner.frame == innerFrame)
        #expect(tab.panes.map { $0.layoutView.frame } == frames)
        // Walking from the moved terminal must now follow the swapped order.
        tab.cyclePane(by: 1)
        #expect(tab.activePane === third)
    }

    @Test func swappingOnlyPaneDoesNothing() {
        let tab = tab()
        let pane = tab.activePane
        let frame = tab.root.frame
        tab.swapPane(by: 1)
        tab.swapPane(by: -1)
        #expect(tab.panes.count == 1)
        #expect(tab.activePane === pane)
        #expect(tab.root === pane.layoutView)
        #expect(tab.root.frame == frame)
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
