import AppKit
import SwiftTerm

/// The AppKit view tree is also the split tree. Every branch has two children.
@MainActor
final class TerminalTab: LocalProcessTerminalViewDelegate {
    weak var controller: TerminalWindowController?
    private(set) var root: NSView
    private(set) var activePane: TerminalPane {
        didSet {
            guard activePane !== oldValue else { return }
            oldValue.setFocused(false)
            activePane.setFocused(true)
        }
    }
    var panes: [TerminalPane] { Self.panes(in: root) }
    var title: String { panes.map(\.title).filter { !$0.isEmpty }.joined(separator: " · ") }
    private var maximizedPlaceholder: PanePlaceholder?
    var isPaneMaximized: Bool { maximizedPlaceholder != nil }
    var displayedView: NSView { maximizedPlaceholder?.paneView ?? root }

    init(directory: String) {
        let pane = TerminalPane(directory: directory)
        root = TerminalPaneFrame(pane: pane)
        activePane = pane
        pane.tab = self
        pane.processDelegate = self
    }

    func focus(_ pane: TerminalPane) {
        guard activePane !== pane else { return }
        activePane = pane
        controller?.refreshChrome()
    }

    @discardableResult
    func split(vertical: Bool) -> TerminalPane? {
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        let old = activePane
        let oldView = old.layoutView
        let minimum = SplitView.minimumSize(of: oldView)
        let available = vertical ? oldView.bounds.width : oldView.bounds.height
        guard available >= (vertical ? minimum.width : minimum.height) * 2 + 1 else {
            setPaneMaximized(wasMaximized)
            controller?.layoutChanged(in: self)
            return nil
        }
        let pane = TerminalPane(directory: old.newSessionDirectory)
        insert(pane, vertical: vertical)
        controller?.layoutChanged(in: self)
        return pane
    }

    private func insert(_ pane: TerminalPane, vertical: Bool) {
        setPaneMaximized(false)
        let oldView = activePane.layoutView
        let available = vertical ? oldView.bounds.width : oldView.bounds.height
        pane.tab = self
        pane.processDelegate = self
        let paneView = pane.layoutView === pane ? TerminalPaneFrame(pane: pane) : pane.layoutView
        let split = SplitView(frame: oldView.frame)
        split.isVertical = vertical
        replace(oldView, with: split)
        split.addSubview(oldView)
        split.addSubview(paneView)
        split.adjustSubviews()
        split.setPosition((available - split.dividerThickness) / 2, ofDividerAt: 0)
        activePane = pane
    }

    /// Reparent the existing terminal and its PTY without stopping or restarting it.
    func moveActivePane(to destination: TerminalTab) {
        guard destination !== self else { return }
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        let pane = activePane
        removePane(pane)
        setPaneMaximized(wasMaximized)
        destination.insert(pane, vertical: true)
    }

    func close(_ pane: TerminalPane) {
        guard panes.contains(where: { $0 === pane }) else { return }
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        let paneView = pane.layoutView
        guard paneView.superview is SplitView else {
            controller?.closeTab(self)
            return
        }
        pane.stop()
        removePane(pane)
        setPaneMaximized(wasMaximized)
        controller?.layoutChanged(in: self)
    }

    private func removePane(_ pane: TerminalPane) {
        let paneView = pane.layoutView
        guard let parent = paneView.superview as? SplitView else {
            paneView.removeFromSuperview()
            return
        }
        let sibling = parent.subviews.first { $0 !== paneView }!
        if activePane === pane { activePane = Self.panes(in: sibling)[0] }
        paneView.removeFromSuperview()
        sibling.removeFromSuperview()
        replace(parent, with: sibling)
    }

    func stop() {
        setPaneMaximized(false)
        for pane in panes { pane.stop() }
    }

    func cyclePane(by delta: Int) {
        let all = panes
        guard let index = all.firstIndex(where: { $0 === activePane }) else { return }
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        activePane = all[(index + delta + all.count) % all.count]
        setPaneMaximized(wasMaximized)
        controller?.layoutChanged(in: self)
    }

    func swapPane(by delta: Int) {
        let all = panes
        guard all.count > 1, let index = all.firstIndex(where: { $0 === activePane }) else { return }
        let other = all[(index + delta + all.count) % all.count]
        guard other !== activePane else { return }
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        let paneView = activePane.layoutView
        let otherView = other.layoutView
        let placeholder = NSView(frame: paneView.frame)
        replace(paneView, with: placeholder)
        replace(otherView, with: paneView)
        replace(placeholder, with: otherView)
        setPaneMaximized(wasMaximized)
        controller?.layoutChanged(in: self)
    }

    func togglePaneMaximized() {
        setPaneMaximized(!isPaneMaximized)
        controller?.layoutChanged(in: self)
    }

    private func setPaneMaximized(_ maximized: Bool) {
        if !maximized, let placeholder = maximizedPlaceholder {
            let pane = placeholder.pane
            let paneView = pane.layoutView
            pane.setMaximized(false)
            paneView.removeFromSuperview()
            paneView.frame = placeholder.frame
            placeholder.superview?.replaceSubview(placeholder, with: paneView)
            maximizedPlaceholder = nil
        } else if maximized, maximizedPlaceholder == nil, let parent = activePane.layoutView.superview as? SplitView {
            let paneView = activePane.layoutView
            let placeholder = PanePlaceholder(pane: activePane)
            parent.replaceSubview(paneView, with: placeholder)
            root.removeFromSuperview()
            maximizedPlaceholder = placeholder
            paneView.frame = root.bounds
            activePane.setMaximized(true)
        }
    }

    /// Move the nearest divider on the requested axis, preserving all other ratios.
    func resizeSplit(vertical: Bool, by delta: CGFloat) {
        guard !isPaneMaximized else { return }
        var child: NSView = activePane.layoutView
        while let parent = child.superview as? SplitView {
            if parent.isVertical == vertical {
                let first = parent.subviews[0]
                let position = vertical ? first.frame.width : first.frame.height
                let firstMinimum = SplitView.minimumSize(of: first)
                let secondMinimum = SplitView.minimumSize(of: parent.subviews[1])
                let low = vertical ? firstMinimum.width : firstMinimum.height
                let total = vertical ? parent.bounds.width : parent.bounds.height
                let high = total - parent.dividerThickness - (vertical ? secondMinimum.width : secondMinimum.height)
                parent.setPosition(min(max(position + delta, low), high), ofDividerAt: 0)
                return
            }
            child = parent
        }
    }

    private func replace(_ old: NSView, with new: NSView) {
        new.frame = old.frame
        new.autoresizingMask = [.width, .height]
        if root === old {
            old.removeFromSuperview()
            root = new
        } else {
            old.superview?.replaceSubview(old, with: new)
        }
    }

    private static func panes(in view: NSView) -> [TerminalPane] {
        if let pane = view as? TerminalPane { return [pane] }
        if let frame = view as? TerminalPaneFrame { return [frame.pane] }
        if let placeholder = view as? PanePlaceholder { return [placeholder.pane] }
        return view.subviews.flatMap { panes(in: $0) }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        (source as? TerminalPane)?.updateTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        (source as? TerminalPane)?.updateDirectory(directory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let pane = source as? TerminalPane { close(pane) }
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        (source as? TerminalPane)?.showLaunchError(error)
    }
}

/// Retains the original leaf position and frame while its terminal fills the tab.
private final class PanePlaceholder: NSView {
    let pane: TerminalPane
    let paneView: NSView

    init(pane: TerminalPane) {
        self.pane = pane
        paneView = pane.layoutView
        super.init(frame: paneView.frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("Use init(pane:)") }
}

final class SplitView: NSSplitView, NSSplitViewDelegate {
    override var dividerThickness: CGFloat { 1 }
    override var dividerColor: NSColor { Preferences.shared.accentColor }

    override init(frame: NSRect) {
        super.init(frame: frame)
        dividerStyle = .thin
        autoresizingMask = [.width, .height]
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    static func minimumSize(of view: NSView) -> NSSize {
        guard let split = view as? SplitView else {
            let margin = Preferences.shared.borderMargin * 2
            return NSSize(width: 160 + margin, height: 90 + margin)
        }
        let sizes = split.subviews.map { minimumSize(of: $0) }
        if split.isVertical {
            return NSSize(width: sizes.reduce(1) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 90)
        }
        return NSSize(width: sizes.map(\.width).max() ?? 160, height: sizes.reduce(1) { $0 + $1.height })
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let size = Self.minimumSize(of: subviews[0])
        return max(proposedMinimumPosition, isVertical ? size.width : size.height)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let size = Self.minimumSize(of: subviews[1])
        return min(proposedMaximumPosition,
                   (isVertical ? bounds.width - size.width : bounds.height - size.height) - dividerThickness)
    }

    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                   forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        drawnRect.insetBy(dx: isVertical ? -3 : 0, dy: isVertical ? 0 : -3)
    }
}
