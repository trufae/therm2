import AppKit
import SwiftTerm

/// The terminal view owns its PTY. No second session model or output buffering.
final class TerminalPane: LocalProcessTerminalView {
    static var defaultFontSize: CGFloat { Preferences.shared.defaultFontSize }
    static let minimumFontSize: CGFloat = 4
    static let maximumFontSize: CGFloat = 1024
    static let background = NSColor.black
    weak var tab: TerminalTab?
    private(set) var title = ""
    private(set) var directory: String
    private(set) var started = false
    private var pinchFontSize: CGFloat?
    private var maximizedMarker: MaximizedPaneMarker?
    private var stopped = false
    var layoutView: NSView { superview as? TerminalPaneFrame ?? self }

    var newSessionDirectory: String {
        guard Preferences.shared.directoryMode == .inherit else { return NSHomeDirectory() }
        if process.running, let path = WorkingDirectory.path(of: process.shellPid) { return path }
        return WorkingDirectory.valid(directory) ? directory : NSHomeDirectory()
    }

    init(directory: String) {
        self.directory = directory
        var options = TerminalOptions.default
        options.scrollback = Preferences.shared.scrollbackSize
        options.cursorStyle = .steadyBlock
        options.maximumOscBytes = 1_048_576
        options.kittyGraphics.storageLimitBytesPerScreen = 0
        options.enableSixelReported = false
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500),
                   font: Preferences.shared.font(size: Self.defaultFontSize), options: options)
        nativeBackgroundColor = Preferences.shared.terminalBackgroundColor
        nativeForegroundColor = NSColor(white: 0.86, alpha: 1)
        caretColor = NSColor(white: 0.86, alpha: 1)
        selectedTextBackgroundColor = NSColor(srgbRed: 0.22, green: 0.29, blue: 0.38, alpha: 1)
        selectedTextForegroundColor = .white
        // Let the keyboard layout compose Option characters (e.g. Spanish ⌥º → \).
        optionAsMetaKey = false
        suspendsRenderingWhenNotVisible = true
        setAccessibilityLabel("Terminal")
        registerForDraggedTypes(TerminalDrop.pasteboardTypes)
    }

    required init?(coder: NSCoder) { fatalError("Use init(directory:)") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !stopped, TerminalDrop.canRead(sender.draggingPasteboard) else { return [] }
        // Never move or delete the source: a terminal drop only inserts text.
        let allowed = sender.draggingSourceOperationMask
        return allowed.contains(.copy) ? .copy : allowed.intersection(.generic)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !draggingEntered(sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender) else { return false }
        window?.makeFirstResponder(self)
        return TerminalDrop.receive(sender.draggingPasteboard) { [weak self] result in
            guard let self, !self.stopped else { return }
            switch result {
            case .success(let text): self.pasteText(text)
            case .failure(let error):
                NSLog("Could not receive terminal drop: %@", error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    override var frame: NSRect {
        didSet {
            if frame.size != oldValue.size {
                // NSSplitView sets the whole frame; AppKit need not call setFrameSize.
                // SwiftTerm's geometry and PTY notification live in that size setter.
                super.setFrameSize(frame.size)
            }
        }
    }

    func setFocused(_ focused: Bool) {
        let preferences = Preferences.shared
        let brightness = focused ? 1 : CGFloat(1 - preferences.inactiveTextDimming)
        foregroundBrightness = brightness
        nativeBackgroundColor = preferences.backgroundColor(brightness: brightness)
            .withAlphaComponent(preferences.terminalBackgroundColor.alphaComponent)
        layoutView.needsDisplay = true
    }

    func setMaximized(_ maximized: Bool) {
        if maximized, maximizedMarker == nil {
            let marker = MaximizedPaneMarker(frame: NSRect(x: bounds.maxX - 11, y: bounds.maxY - 11,
                                                           width: 7, height: 7))
            marker.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(marker, positioned: .above, relativeTo: nil)
            maximizedMarker = marker
        }
        maximizedMarker?.isHidden = !maximized
    }

    func setFontSize(_ size: CGFloat) {
        guard size.isFinite else { return }
        let size = min(Self.maximumFontSize, max(Self.minimumFontSize, size.rounded()))
        guard size != font.pointSize else { return }
        font = Preferences.shared.font(size: size)
    }

    override func magnify(with event: NSEvent) {
        if event.phase.contains(.began) { window?.makeFirstResponder(self) }
        applyMagnification(event.magnification, phase: event.phase)
    }

    func applyMagnification(_ delta: CGFloat, phase: NSEvent.Phase) {
        if phase.contains(.began) || pinchFontSize == nil { pinchFontSize = font.pointSize }
        defer {
            if !phase.intersection([.ended, .cancelled]).isEmpty { pinchFontSize = nil }
        }
        guard delta.isFinite, !phase.contains(.cancelled), let base = pinchFontSize else { return }
        // Keep fractional travel, but rebuild glyph caches only at whole-point steps.
        let size = min(Self.maximumFontSize, max(Self.minimumFontSize, base * (1 + delta)))
        pinchFontSize = size
        setFontSize(size)
    }

    func start() {
        guard !started else { return }
        started = true
        if ProcessInfo.processInfo.environment["THERM2_METAL"] == "1" {
            do { try setUseMetal(true) }
            catch { NSLog("Metal unavailable, using Core Graphics: %@", String(describing: error)) }
        }
        startProcess(executable: Self.shell, environment: Self.environment,
                     execName: "-" + URL(fileURLWithPath: Self.shell).lastPathComponent,
                     currentDirectory: directory)
    }

    func stop() {
        stopped = true
        processDelegate = nil
        tab = nil
        if started { terminate() }
    }

    private static var shell: String {
        if let entry = getpwuid(getuid()), let value = entry.pointee.pw_shell {
            let path = String(cString: value)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    private static var environment: [String] {
        var values = ProcessInfo.processInfo.environment
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["TERM_PROGRAM"] = "Therm2"
        values["TERM_PROGRAM_VERSION"] = "0.1.0"
        values["SHELL"] = shell
        values["HOME"] = NSHomeDirectory()
        if values["PATH"] == nil { values["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" }
        if values["LANG"] == nil { values["LANG"] = "en_US.UTF-8" }
        // Parent terminal identity must not leak into the new PTY.
        for key in ["TERM_SESSION_ID", "ITERM_SESSION_ID", "WINDOWID", "TMUX", "STY"] {
            values.removeValue(forKey: key)
        }
        return values.map { "\($0.key)=\($0.value)" }
    }

    func updateTitle(_ title: String) {
        let clean = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(256))
        self.title = clean
        tab?.controller?.refreshChrome()
    }

    func updateDirectory(_ directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL else { return }
        // Ignore OSC 7 from SSH hosts; a remote path is not a local launch directory.
        let host = url.host ?? ""
        guard host.isEmpty || host == "localhost" || host == ProcessInfo.processInfo.hostName else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            self.directory = url.path
        }
    }

    func showLaunchError(_ error: LocalProcessError) {
        title = "Launch failed"
        feed(text: "\r\nCould not start \(Self.shell): \(error)\r\nPress ⌘W to close this pane.\r\n")
        tab?.controller?.refreshChrome()
    }
}

/// Insets the terminal itself so drawing, hit testing, and PTY sizing share the same geometry.
final class TerminalPaneFrame: NSView {
    let pane: TerminalPane

    init(pane: TerminalPane) {
        self.pane = pane
        super.init(frame: pane.frame)
        autoresizingMask = [.width, .height]
        addSubview(pane)
        updateMargin()
    }

    required init?(coder: NSCoder) { fatalError("Use init(pane:)") }
    override var isOpaque: Bool { !Preferences.shared.glassyWindow }

    override var frame: NSRect {
        didSet { updateMargin() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMargin()
    }

    func updateMargin() {
        let margin = Preferences.shared.borderMargin
        let horizontal = min(margin, max(0, (bounds.width - 1) / 2))
        let vertical = min(margin, max(0, (bounds.height - 1) / 2))
        let rect = bounds.insetBy(dx: horizontal, dy: vertical)
        if pane.frame != rect { pane.frame = rect }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        pane.nativeBackgroundColor.setFill()
        // Paint only the margin: tinting beneath the terminal would apply its alpha twice.
        let margin = NSBezierPath(rect: bounds)
        margin.appendRect(pane.frame)
        margin.windingRule = .evenOdd
        margin.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? pane : hit
    }
}

private final class MaximizedPaneMarker: NSView {
    private static let color = NSColor(white: 0.65, alpha: 1)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Self.color.setStroke()
        let square = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        square.lineWidth = 1
        square.stroke()
    }
}

