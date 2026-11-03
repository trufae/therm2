import AppKit
import Testing
@testable import SwiftTerm
@testable import Therm2

@Suite(.serialized) @MainActor
struct RenderingTests {
    init() { _ = NSApplication.shared }

    private func context(_ pane: TerminalPane) throws -> (TerminalSnapshot, SnapshotRenderContext) {
        let snapshot = TerminalSnapshot()
        let state = FrameViewState(view: pane)
        pane.withTerminal { terminal in
            _ = snapshot.refresh(terminal: terminal, viewState: state,
                                 selection: SnapshotSelectionState(selection: pane.selection),
                                 deferBidiTypesetting: false)
        }
        return (snapshot, SnapshotRenderContext(viewState: state, snapshot: snapshot))
    }

    private func components(_ color: NSColor) throws -> [CGFloat] {
        let color = try #require(color.usingColorSpace(.sRGB))
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }

    private func expectDimmed(_ dimmed: NSColor, original: NSColor) throws {
        let dim = try components(dimmed)
        let original = try components(original)
        for channel in 0..<3 { #expect(abs(dim[channel] - original[channel] * 0.85) < 0.000_001) }
        #expect(dim[3] == original[3])
    }

    @Test func focusDimsOnlyRenderedForegroundsAndRestoresCachedColors() throws {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        pane.feed(text: "\u{1b}[31;44mA\u{1b}[38;2;200;120;80;48;2;30;60;90mB\u{1b}[0mC")
        #expect(try components(pane.nativeBackgroundColor) == [0, 0, 0, 1])

        func attributes() throws -> [[NSAttributedString.Key: Any]] {
            let (snapshot, context) = try self.context(pane)
            let row = try #require(snapshot.rows.first)
            let rendered = pane.textBuilder.buildAttributedString(row: row, absoluteRow: snapshot.firstRow,
                                                                  context: context)
            let text = NSMutableAttributedString()
            for segment in rendered.segments { text.append(segment.attributedString) }
            return (0..<3).map { text.attributes(at: $0, effectiveRange: nil) }
        }

        let bright = try attributes()
        pane.setFocused(false)
        let dimmed = try attributes()
        for cell in 0..<3 {
            let original = try #require(bright[cell][.foregroundColor] as? NSColor)
            let dim = try #require(dimmed[cell][.foregroundColor] as? NSColor)
            try expectDimmed(dim, original: original)
            #expect((dimmed[cell][.backgroundColor] as? NSColor) == (bright[cell][.backgroundColor] as? NSColor))
        }
        #expect(try components(pane.nativeBackgroundColor) == [0, 0, 0, 1])
        pane.setFocused(true)
        let restored = try attributes()
        for cell in 0..<3 {
            #expect((restored[cell][.foregroundColor] as? NSColor) == (bright[cell][.foregroundColor] as? NSColor))
        }
    }

    @Test func metalPlainRowsKeepBackgroundsAndMatchShapedTextDimming() throws {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        pane.feed(text: "\u{1b}[38;2;200;120;80;48;2;30;60;90mA")
        let (brightSnapshot, brightContext) = try self.context(pane)
        let brightRow = try #require(brightSnapshot.rows.first)
        let bright = try #require(pane.textBuilder.plainRow(row: brightRow, absoluteRow: brightSnapshot.firstRow,
                                                           context: brightContext)?.runs.first)
        let foreground = pane.textBuilder.platformColor(bright.style.foreground, context: brightContext)
        let background = pane.textBuilder.platformColor(bright.style.background, context: brightContext)
        pane.setFocused(false)
        let (dimSnapshot, dimContext) = try self.context(pane)
        let dimRow = try #require(dimSnapshot.rows.first)
        let dimmed = try #require(pane.textBuilder.plainRow(row: dimRow, absoluteRow: dimSnapshot.firstRow,
                                                           context: dimContext)?.runs.first)
        try expectDimmed(pane.textBuilder.platformColor(dimmed.style.foreground, context: dimContext), original: foreground)
        #expect(pane.textBuilder.platformColor(dimmed.style.background, context: dimContext) == background)
        #expect(brightContext.identity != dimContext.identity)
    }

    @Test func selectedTextDimsWithoutChangingSelectionHighlight() throws {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        pane.feed(text: "selected")
        pane.selection.startSelection(row: 0, col: 0)
        pane.selection.dragExtend(bufferPosition: Position(col: 3, row: 0))
        let (_, bright) = try self.context(pane)
        pane.setFocused(false)
        let (_, dimmed) = try self.context(pane)
        try expectDimmed(dimmed.selectedTextForegroundColor, original: bright.selectedTextForegroundColor)
        #expect(dimmed.selectionFillColor == bright.selectionFillColor)
    }
}
