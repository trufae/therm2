import AppKit

final class TerminalWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The fullscreen backing must cover the menu bar/notch strip as well.
        if (windowController as? TerminalWindowController)?.isFastFullscreen == true { return frameRect }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    override func sendEvent(_ event: NSEvent) {
        if isKeyWindow, event.type == .mouseMoved { focusPane(at: event.locationInWindow) }
        super.sendEvent(event)
    }

    func focusPane(at windowPoint: NSPoint) {
        guard let content = contentView else { return }
        let point = content.superview?.convert(windowPoint, from: nil) ?? windowPoint
        var view = content.hitTest(point)
        while let current = view {
            if let pane = current as? TerminalPane {
                if pane.tab?.activePane !== pane { makeFirstResponder(pane) }
                return
            }
            view = current.superview
        }
    }

    @discardableResult override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted, let pane = responder as? TerminalPane { pane.tab?.focus(pane) }
        return accepted
    }

    override func zoom(_ sender: Any?) { toggleFullScreen(sender) }

    override func toggleFullScreen(_ sender: Any?) {
        (windowController as? TerminalWindowController)?.toggleFullscreen()
    }

    func toggleNativeFullscreen() { super.toggleFullScreen(nil) }
}

final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private(set) var tabs: [TerminalTab] = []
    private(set) var selectedIndex = 0
    private(set) var isFastFullscreen = false
    private(set) var isTransitioningNativeFullscreen = false
    var isFullscreen: Bool { isFastFullscreen || window?.styleMask.contains(.fullScreen) == true }
    private var savedFrame = NSRect.zero
    private var savedStyle: NSWindow.StyleMask = []
    private let tabBar = TabBar(frame: .zero)
    private let content = NSView()
    private var glassView: NSView?
    var onClose: (() -> Void)?
    var selectedTab: TerminalTab? { tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil }
    var isAlwaysOnTop: Bool { window?.level == .floating }
    var ignoresNotchInFullscreen: Bool { Preferences.shared.ignoreNotch }

    init() {
        let window = TerminalWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                    backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = Preferences.shared.backgroundColor
        window.isOpaque = true
        window.hasShadow = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true
        updateFullscreenBehavior()
        window.contentView = content
        updateWindowBackground()
        window.center()
        content.addSubview(tabBar)
        tabBar.onSelect = { [weak self] index in self?.selectTab(at: index) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func newTab() {
        let tab = TerminalTab(directory: selectedTab?.activePane.newSessionDirectory ?? NSHomeDirectory())
        tab.controller = self
        tabs.append(tab)
        selectTab(at: tabs.count - 1)
        tab.activePane.start()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTab?.displayedView.removeFromSuperview()
        selectedIndex = index
        layoutChanged(in: tabs[index])
    }

    func cycleTab(by delta: Int) {
        guard !tabs.isEmpty else { return }
        selectTab(at: (selectedIndex + delta + tabs.count) % tabs.count)
    }

    func closeTab(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let previous = selectedTab
        tab.stop()
        tab.root.removeFromSuperview()
        tabs.remove(at: index)
        if tabs.isEmpty { window?.close(); return }
        if previous === tab {
            selectedIndex = min(index, tabs.count - 1)
        } else if let previous, let remaining = tabs.firstIndex(where: { $0 === previous }) {
            selectedIndex = remaining
        }
        layoutChanged(in: tabs[selectedIndex])
    }

    func split(vertical: Bool) {
        guard let pane = selectedTab?.split(vertical: vertical) else { NSSound.beep(); return }
        pane.start()
    }

    func layoutChanged(in tab: TerminalTab) {
        guard tab === selectedTab else { refreshChrome(); return }
        if tab.displayedView.superview !== content { content.addSubview(tab.displayedView) }
        layoutContent()
        window?.makeFirstResponder(tab.activePane)
        refreshChrome()
    }

    func refreshChrome() {
        let title = selectedTab?.activePane.title ?? ""
        window?.title = Preferences.shared.emptyWindowTitle ? "" : (title.isEmpty ? "Therm2" : title)
        tabBar.isHidden = tabs.count < 2
        tabBar.update(titles: tabs.map(\.title), selected: selectedIndex)
        layoutContent()
    }

    private func layoutContent() {
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = isFullscreen ? 0 : 12
        }
        guard let tab = selectedTab else { return }
        let barHeight = tabs.count > 1 ? TabBar.height : 0
        let safeTop = isFastFullscreen && !ignoresNotchInFullscreen ? (window?.screen?.safeAreaInsets.top ?? 0) : 0
        let height = max(0, content.bounds.height - safeTop - barHeight)
        tab.displayedView.frame = NSRect(x: 0, y: barHeight, width: content.bounds.width, height: height)
        tabBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: barHeight)
        let minimum = SplitView.minimumSize(of: tab.displayedView)
        window?.contentMinSize = NSSize(width: max(320, minimum.width), height: max(180, minimum.height + barHeight + safeTop))
    }

    func toggleFullscreen() {
        guard !isTransitioningNativeFullscreen, let window = window as? TerminalWindow else { return }
        // Always leave the active mode, even if the preference changed while fullscreen.
        if !isFastFullscreen && (isFullscreen || Preferences.shared.useNativeFullscreen) {
            isTransitioningNativeFullscreen = true
            window.toggleNativeFullscreen()
            return
        }
        guard let screen = window.screen ?? NSScreen.main else { return }
        if isFastFullscreen {
            isFastFullscreen = false
            window.styleMask = savedStyle
            // If a monitor disappeared, return to a visible part of the current display.
            let frame = NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) })
                ? savedFrame : screen.visibleFrame.insetBy(dx: 60, dy: 60)
            window.setFrame(frame, display: true, animate: false)
            updateFullscreenBehavior()
        } else {
            savedFrame = window.frame
            savedStyle = window.styleMask
            isFastFullscreen = true
            window.styleMask = .borderless
            window.setFrame(screen.frame, display: true, animate: false)
        }
        updateWindowBackground()
        window.makeKeyAndOrderFront(nil)
        layoutContent()
        if let pane = selectedTab?.activePane { window.makeFirstResponder(pane) }
        (NSApp.delegate as? AppDelegate)?.updatePresentation()
    }

    func toggleNotchGuard() {
        Preferences.shared.ignoreNotch.toggle()
    }

    private func updateFullscreenBehavior() {
        guard !isFullscreen, !isTransitioningNativeFullscreen else { return }
        window?.collectionBehavior = Preferences.shared.useNativeFullscreen
            ? [.fullScreenPrimary, .managed] : [.fullScreenNone, .managed]
    }

    private func updateWindowBackground() {
        guard let window else { return }
        let preferences = Preferences.shared
        let glassy = preferences.glassyWindow
        let responder = window.firstResponder
        window.isOpaque = !glassy
        window.backgroundColor = glassy ? .clear : (isFastFullscreen ? .black : preferences.backgroundColor)
        window.hasShadow = glassy && !isFullscreen

        if glassy, glassView == nil {
            let effect: NSView
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: content.frame)
                glass.style = .clear
                glass.cornerRadius = isFullscreen ? 0 : 12
                effect = glass
                window.contentView = glass
                glass.contentView = content
            } else {
                let blur = NSVisualEffectView(frame: content.frame)
                blur.material = .hudWindow
                blur.blendingMode = .behindWindow
                blur.state = .active
                effect = blur
                window.contentView = blur
                blur.addSubview(content)
            }
            glassView = effect
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]
        } else if !glassy, let effect = glassView {
            if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
                glass.contentView = nil
            } else {
                content.removeFromSuperview()
            }
            window.contentView = content
            glassView = nil
        }
        if window.firstResponder !== responder { window.makeFirstResponder(responder) }
        tabBar.needsDisplay = true
    }

    func applyPreferences(_ change: Preferences.Change) {
        let preferences = Preferences.shared
        switch change {
        case .background, .glass:
            updateWindowBackground()
            for pane in tabs.flatMap(\.panes) {
                pane.nativeBackgroundColor = preferences.terminalBackgroundColor
                pane.backgroundOpacity = preferences.terminalBackgroundColor.alphaComponent
                pane.layoutView.needsDisplay = true
            }
            layoutContent()
        case .font:
            for pane in tabs.flatMap(\.panes) { pane.font = preferences.font(size: pane.font.pointSize) }
        case .fontSize:
            for pane in tabs.flatMap(\.panes) { pane.setFontSize(preferences.defaultFontSize) }
        case .margin:
            for pane in tabs.flatMap(\.panes) { (pane.layoutView as? TerminalPaneFrame)?.updateMargin() }
            layoutContent()
        case .scrollback:
            for pane in tabs.flatMap(\.panes) { pane.changeScrollback(preferences.scrollbackSize) }
        case .dimming:
            for tab in tabs {
                for pane in tab.panes { pane.setFocused(pane === tab.activePane) }
            }
        case .accent:
            tabBar.needsDisplay = true
            func redraw(_ view: NSView) {
                guard let split = view as? SplitView else { return }
                split.needsDisplay = true
                split.subviews.forEach { redraw($0) }
            }
            tabs.forEach { redraw($0.root) }
        case .notch: layoutContent()
        case .fullscreen: updateFullscreenBehavior()
        case .title: refreshChrome()
        case .directory: break
        }
    }

    func toggleAlwaysOnTop() {
        window?.level = isAlwaysOnTop ? .normal : .floating
        window?.orderFront(nil)
    }

    @objc private func screensChanged() {
        if isFastFullscreen, let window, let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.frame, display: true, animate: false)
        }
        layoutContent()
    }

    func windowDidResize(_ notification: Notification) { layoutContent() }
    func windowWillEnterFullScreen(_ notification: Notification) { isTransitioningNativeFullscreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { isTransitioningNativeFullscreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) { nativeFullscreenTransitionFinished() }
    func windowDidExitFullScreen(_ notification: Notification) { nativeFullscreenTransitionFinished() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { nativeFullscreenTransitionFinished() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { nativeFullscreenTransitionFinished() }

    private func nativeFullscreenTransitionFinished() {
        isTransitioningNativeFullscreen = false
        updateFullscreenBehavior()
        updateWindowBackground()
        layoutContent()
        if let pane = selectedTab?.activePane { window?.makeFirstResponder(pane) }
        (NSApp.delegate as? AppDelegate)?.updatePresentation()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.updatePresentation()
    }
    func windowDidResignKey(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.updatePresentation()
    }
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        tabs.forEach { $0.stop() }
        tabs.removeAll()
        (NSApp.delegate as? AppDelegate)?.updatePresentation()
        onClose?()
    }
}
