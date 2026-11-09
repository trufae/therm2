import AppKit

final class ClickableButton: NSButton {
    override var isEnabled: Bool {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
