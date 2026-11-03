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
    var displayedView: NSView { maximizedPlaceholder?.pane ?? root }

    init(directory: String) {
        let pane = TerminalPane(directory: directory)
        root = pane
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
        let minimum = SplitView.minimumSize(of: old)
        let available = vertical ? old.bounds.width : old.bounds.height
        guard available >= (vertical ? minimum.width : minimum.height) * 2 + 1 else {
            setPaneMaximized(wasMaximized)
            controller?.layoutChanged(in: self)
            return nil
        }
        let pane = TerminalPane(directory: old.newSessionDirectory)
        pane.tab = self
        pane.processDelegate = self
        let split = SplitView(frame: old.frame)
        split.isVertical = vertical
        replace(old, with: split)
        split.addSubview(old)
        split.addSubview(pane)
        split.adjustSubviews()
        split.setPosition((available - split.dividerThickness) / 2, ofDividerAt: 0)
        activePane = pane
        controller?.layoutChanged(in: self)
        return pane
    }

    func close(_ pane: TerminalPane) {
        guard panes.contains(where: { $0 === pane }) else { return }
        let wasMaximized = isPaneMaximized
        setPaneMaximized(false)
        guard let parent = pane.superview as? SplitView else {
            controller?.closeTab(self)
            return
        }
        let sibling = parent.subviews.first { $0 !== pane }!
        if activePane === pane { activePane = Self.panes(in: sibling)[0] }
        pane.stop()
        pane.removeFromSuperview()
        sibling.removeFromSuperview()
        replace(parent, with: sibling)
        setPaneMaximized(wasMaximized)
        controller?.layoutChanged(in: self)
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

    func togglePaneMaximized() {
        setPaneMaximized(!isPaneMaximized)
        controller?.layoutChanged(in: self)
    }

    private func setPaneMaximized(_ maximized: Bool) {
        if !maximized, let placeholder = maximizedPlaceholder {
            let pane = placeholder.pane
            pane.setMaximized(false)
            pane.removeFromSuperview()
            pane.frame = placeholder.frame
            placeholder.superview?.replaceSubview(placeholder, with: pane)
            maximizedPlaceholder = nil
        } else if maximized, maximizedPlaceholder == nil, let parent = activePane.superview as? SplitView {
            let placeholder = PanePlaceholder(pane: activePane)
            parent.replaceSubview(activePane, with: placeholder)
            root.removeFromSuperview()
            maximizedPlaceholder = placeholder
            activePane.frame = root.bounds
            activePane.setMaximized(true)
        }
    }

    /// Move the nearest divider on the requested axis, preserving all other ratios.
    func resizeSplit(vertical: Bool, by delta: CGFloat) {
        guard !isPaneMaximized else { return }
        var child: NSView = activePane
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

    init(pane: TerminalPane) {
        self.pane = pane
        super.init(frame: pane.frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("Use init(pane:)") }
}

final class SplitView: NSSplitView, NSSplitViewDelegate {
    override var dividerThickness: CGFloat { 1 }
    override var dividerColor: NSColor { Preferences.shared.separatorColor }

    override init(frame: NSRect) {
        super.init(frame: frame)
        dividerStyle = .thin
        autoresizingMask = [.width, .height]
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    static func minimumSize(of view: NSView) -> NSSize {
        guard let split = view as? SplitView else { return NSSize(width: 160, height: 90) }
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
