import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var windows: [ObjectIdentifier: TerminalWindowController] = [:]
    private var preferencesWindow: PreferencesWindowController?
    private var presentationUpdatePending = false
    private var current: TerminalWindowController? {
        (NSApp.keyWindow?.windowController as? TerminalWindowController)
            ?? (NSApp.mainWindow?.windowController as? TerminalWindowController)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BundledFonts.register()
        Preferences.shared.onChange = { [weak self] change in
            guard let self else { return }
            windows.values.forEach { $0.applyPreferences(change) }
            preferencesWindow?.refresh()
        }
        buildMenu()
        newWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        UpdateChecker.checkOnStartup()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { updatePresentation() }
    func applicationDidResignActive(_ notification: Notification) { updatePresentation() }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in windows.values { controller.tabs.forEach { $0.stop() } }
    }

    func updatePresentation() {
        // Key-window notifications arrive during app switching. Wait for the handoff
        // to finish before reading the new key window or changing Dock/menu-bar state.
        guard !presentationUpdatePending else { return }
        presentationUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationUpdatePending = false
            self.applyPresentation()
        }
    }

    private func applyPresentation() {
        // AppKit applies these options only while we are active. Let it switch to
        // the next app's options instead of resetting them during deactivation.
        guard NSApp.isActive else { return }
        // AppKit owns presentation options while a native fullscreen Space is active.
        let controller = NSApp.keyWindow?.windowController as? TerminalWindowController
        guard !NSApp.presentationOptions.contains(.fullScreen),
              controller?.isTransitioningNativeFullscreen != true else { return }
        let fullscreen = controller?.isFastFullscreen == true
        let options: NSApplication.PresentationOptions = fullscreen
            ? [.autoHideDock, .autoHideMenuBar, .disableMenuBarTransparency] : []
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
    }

    @objc private func newWindow(_ sender: Any?) {
        let controller = TerminalWindowController()
        let id = ObjectIdentifier(controller)
        windows[id] = controller
        controller.onClose = { [weak self] in self?.windows.removeValue(forKey: id) }
        controller.showWindow(nil)
        controller.newTab()
    }

    @objc private func newTab(_ sender: Any?) {
        if let current { current.newTab() } else { newWindow(sender) }
    }

    @objc private func closePane(_ sender: Any?) {
        if NSApp.keyWindow?.windowController is PreferencesWindowController {
            NSApp.keyWindow?.performClose(sender)
            return
        }
        if let tab = current?.selectedTab { tab.close(tab.activePane) }
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil { preferencesWindow = PreferencesWindowController() }
        preferencesWindow?.refresh()
        preferencesWindow?.window?.level = current?.isAlwaysOnTop == true ? .floating : .normal
        preferencesWindow?.showWindow(sender)
        preferencesWindow?.window?.makeKeyAndOrderFront(sender)
    }

    @objc private func closeTab(_ sender: Any?) {
        if let current, let tab = current.selectedTab { current.closeTab(tab) }
    }

    @objc private func splitVertical(_ sender: Any?) { current?.split(vertical: true) }
    @objc private func splitHorizontal(_ sender: Any?) { current?.split(vertical: false) }
    @objc private func fullscreen(_ sender: Any?) { current?.toggleFullscreen() }
    @objc private func alwaysOnTop(_ sender: Any?) { current?.toggleAlwaysOnTop() }
    @objc private func maximizePane(_ sender: Any?) { current?.selectedTab?.togglePaneMaximized() }
    @objc private func notchGuard(_ sender: Any?) { current?.toggleNotchGuard() }

    @objc private func selectTab(_ sender: NSMenuItem) { current?.selectTab(at: sender.tag) }
    @objc private func movePaneToTab(_ sender: NSMenuItem) { current?.moveActivePane(toTabAt: sender.tag) }
    @objc private func cycleTab(_ sender: NSMenuItem) { current?.cycleTab(by: sender.tag) }
    @objc private func cyclePane(_ sender: NSMenuItem) { current?.selectedTab?.cyclePane(by: sender.tag) }
    @objc private func swapPane(_ sender: NSMenuItem) { current?.selectedTab?.swapPane(by: sender.tag) }

    @objc private func resizeSplit(_ sender: NSMenuItem) {
        current?.selectedTab?.resizeSplit(vertical: abs(sender.tag) == 1, by: sender.tag > 0 ? 24 : -24)
    }

    @objc private func fontSize(_ sender: NSMenuItem) {
        guard let pane = current?.selectedTab?.activePane else { return }
        pane.setFontSize(sender.tag == 0 ? TerminalPane.defaultFontSize : pane.font.pointSize + CGFloat(sender.tag))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(fullscreen(_:)) {
            item.title = Preferences.shared.useNativeFullscreen ? "Toggle Native Fullscreen" : "Toggle Fast Fullscreen"
            return current != nil && current?.isTransitioningNativeFullscreen != true
        }
        if item.action == #selector(alwaysOnTop(_:)) {
            item.state = current?.isAlwaysOnTop == true ? .on : .off
            return current != nil && current?.isFastFullscreen != true
        }
        if item.action == #selector(notchGuard(_:)) {
            item.state = current?.ignoresNotchInFullscreen == true ? .on : .off
            return current != nil
        }
        return true
    }

    private func buildMenu() {
        let bar = NSMenu()
        NSApp.mainMenu = bar

        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            item.submenu = menu
            bar.addItem(item)
            return menu
        }

        @discardableResult
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.tag = tag
            menu.addItem(item)
            return item
        }

        let app = menu("Therm2")
        add(app, "About Therm2", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        add(app, "Preferences…", #selector(showPreferences(_:)), ",")
        app.addItem(.separator())
        add(app, "Hide Therm2", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Therm2", #selector(NSApplication.terminate(_:)), "q")

        let file = menu("File")
        add(file, "New Window", #selector(newWindow(_:)), "n")
        add(file, "New Tab", #selector(newTab(_:)), "t")
        file.addItem(.separator())
        add(file, "Split Left / Right", #selector(splitVertical(_:)), "d")
        add(file, "Split Top / Bottom", #selector(splitHorizontal(_:)), "d", [.command, .shift])
        file.addItem(.separator())
        add(file, "Close Pane", #selector(closePane(_:)), "w")
        add(file, "Close Tab", #selector(closeTab(_:)), "w", [.command, .shift])
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .option])

        let edit = menu("Edit")
        add(edit, "Copy", NSSelectorFromString("copy:"), "c")
        add(edit, "Paste", NSSelectorFromString("paste:"), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, "Find", #selector(NSResponder.performTextFinderAction(_:)), "f",
            tag: NSTextFinder.Action.showFindInterface.rawValue)

        let view = menu("View")
        add(view, "Toggle Fast Fullscreen", #selector(fullscreen(_:)), "\r")
        add(view, "Toggle Maximize Pane", #selector(maximizePane(_:)), "\r", [.command, .shift])
        add(view, "Ignore Notch in Fullscreen", #selector(notchGuard(_:)), "g", [.command, .shift])
        add(view, "Always on Top", #selector(alwaysOnTop(_:)), "f", [.command, .shift])
        view.addItem(.separator())
        add(view, "Increase Font Size", #selector(fontSize(_:)), "+", tag: 1)
        let increaseWithEquals = add(view, "Increase Font Size", #selector(fontSize(_:)), "=", tag: 1)
        increaseWithEquals.isHidden = true
        increaseWithEquals.allowsKeyEquivalentWhenHidden = true
        add(view, "Decrease Font Size", #selector(fontSize(_:)), "-", tag: -1)
        add(view, "Reset Font Size", #selector(fontSize(_:)), "0", tag: 0)
        view.addItem(.separator())
        for (key, title, tag) in [("h", "Move Divider Left", -1), ("l", "Move Divider Right", 1),
                                  ("j", "Move Divider Up", 2), ("k", "Move Divider Down", -2)] {
            add(view, title, #selector(resizeSplit(_:)), key, [.command, .shift], tag: tag)
        }

        let window = menu("Window")
        NSApp.windowsMenu = window
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        window.addItem(.separator())
        add(window, "Previous Tab", #selector(cycleTab(_:)), "[", [.command, .shift], tag: -1)
        add(window, "Next Tab", #selector(cycleTab(_:)), "]", [.command, .shift], tag: 1)
        add(window, "Previous Pane", #selector(cyclePane(_:)), "k", tag: -1)
        add(window, "Next Pane", #selector(cyclePane(_:)), "j", tag: 1)
        add(window, "Swap with Previous Pane", #selector(swapPane(_:)), "p", [.command, .shift], tag: -1)
        add(window, "Swap with Next Pane", #selector(swapPane(_:)), "n", [.command, .shift], tag: 1)
        window.addItem(.separator())
        for number in 1...9 {
            add(window, "Tab \(number)", #selector(selectTab(_:)), "\(number)", tag: number - 1)
        }
        window.addItem(.separator())
        for number in 1...9 {
            add(window, "Move Pane to Tab \(number)", #selector(movePaneToTab(_:)), "\(number)",
                [.command, .shift], tag: number - 1)
        }
    }
}
