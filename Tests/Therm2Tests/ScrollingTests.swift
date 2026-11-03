import AppKit
import SwiftTerm
import Testing

/// Exercise the dependency through its real AppKit event handler and inspect PTY input.
@Suite(.serialized) @MainActor
struct ScrollingTests {
    private final class Recorder: TerminalViewDelegate {
        var writes: [[UInt8]] = []
        var text: String { writes.map { String(decoding: $0, as: UTF8.self) }.joined() }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { writes.append(Array(data)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    }

    init() { _ = NSApplication.shared }

    private func terminal(modes: String = "\u{1b}[?1000h\u{1b}[?1006h") -> (TerminalView, Recorder) {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400),
                                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                                options: TerminalOptions(cursorStyle: .steadyBlock))
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.feed(text: modes)
        return (view, recorder)
    }

    private func wheel(x: Int32 = 0, y: Int32 = 0, precise: Bool = true,
                       flags: CGEventFlags = [], phase: NSEvent.Phase = []) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                                     wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        cg.flags = flags
        let event = try #require(NSEvent(cgEvent: cg))
        #expect(event.scrollingDeltaX == CGFloat(x))
        #expect(event.scrollingDeltaY == CGFloat(y))
        #expect(event.hasPreciseScrollingDeltas == precise)
        return event
    }

    private func scroll(_ view: TerminalView, _ event: NSEvent) async {
        view.scrollWheel(with: event)
        // SwiftTerm queues terminal-generated mouse responses on the main queue.
        // A FIFO barrier observes delivery before checking either output or silence.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test(arguments: [false, true])
    func horizontalOnlyReportsLeftAndRight(precise: Bool) async throws {
        for (distance, code) in [(Int32(20), 66), (Int32(-20), 67)] {
            let (view, recorder) = terminal()
            await scroll(view, try wheel(x: distance, precise: precise))
            #expect(!recorder.writes.isEmpty)
            #expect(recorder.writes.allSatisfy { String(decoding: $0, as: UTF8.self).hasPrefix("\u{1b}[<\(code);") })
        }
    }

    @Test(arguments: [false, true])
    func verticalReportsRemainUpAndDown(precise: Bool) async throws {
        for (distance, code) in [(Int32(20), 64), (Int32(-20), 65)] {
            let (view, recorder) = terminal()
            await scroll(view, try wheel(y: distance, precise: precise))
            #expect(!recorder.writes.isEmpty)
            #expect(recorder.writes.allSatisfy { String(decoding: $0, as: UTF8.self).hasPrefix("\u{1b}[<\(code);") })
        }
    }

    @Test func legacyMouseEncodingIncludesHorizontalButtons() async throws {
        let (view, recorder) = terminal(modes: "\u{1b}[?1000h")
        await scroll(view, try wheel(x: 1, precise: false))
        await scroll(view, try wheel(x: -1, precise: false))
        #expect(recorder.writes.map { $0[3] } == [98, 99])
    }

    @Test func diagonalInputReportsBothAxesWithinOneBudget() async throws {
        let (view, recorder) = terminal()
        await scroll(view, try wheel(x: 20, y: 20))
        #expect(recorder.text.contains("\u{1b}[<66;"))
        #expect(recorder.text.contains("\u{1b}[<64;"))
        #expect(recorder.writes.count <= 6)
    }

    @Test func subcellHorizontalTravelAccumulates() async throws {
        let (view, recorder) = terminal()
        await scroll(view, try wheel(x: 1))
        #expect(recorder.writes.isEmpty)
        for _ in 0..<20 { await scroll(view, try wheel(x: 1)) }
        #expect(!recorder.writes.isEmpty)
        #expect(recorder.writes.allSatisfy { String(decoding: $0, as: UTF8.self).hasPrefix("\u{1b}[<66;") })
    }

    @Test func gestureBoundariesDiscardFractionalTravel() async throws {
        let (view, recorder) = terminal()
        for _ in 0..<20 {
            await scroll(view, try wheel(x: 1, phase: .began))
            await scroll(view, try wheel(phase: .ended))
        }
        #expect(recorder.writes.isEmpty)
    }

    @Test func alternateScreenMapsHorizontalTravelToCursorKeys() async throws {
        for (mode, left, right) in [("", "\u{1b}[D", "\u{1b}[C"),
                                    ("\u{1b}[?1h", "\u{1b}OD", "\u{1b}OC")] {
            let (view, recorder) = terminal(modes: "\u{1b}[?1049h\u{1b}[?1007h" + mode)
            await scroll(view, try wheel(x: 1, precise: false))
            #expect(recorder.text == left)
            recorder.writes.removeAll()
            await scroll(view, try wheel(x: -1, precise: false))
            #expect(recorder.text == right)
        }
    }

    @Test func disabledAlternateScrollAndLocalModifiersDoNotInjectKeys() async throws {
        for flags: CGEventFlags in [[], .maskAlternate, .maskShift] {
            let (view, recorder) = terminal(modes: "\u{1b}[?1049h\u{1b}[?1007l")
            await scroll(view, try wheel(x: 20, flags: flags))
            #expect(recorder.writes.isEmpty)
        }
    }

    @Test func normalShellDoesNotReceiveHorizontalArrowKeys() async throws {
        let (view, recorder) = terminal(modes: "")
        await scroll(view, try wheel(x: 20))
        #expect(recorder.writes.isEmpty)
    }

    @Test func mouseBypassAndControlModifierArePreserved() async throws {
        for flags: CGEventFlags in [.maskAlternate, .maskShift] {
            let (view, recorder) = terminal()
            await scroll(view, try wheel(x: 20, flags: flags))
            #expect(recorder.writes.isEmpty)
        }
        let (view, recorder) = terminal()
        await scroll(view, try wheel(x: 1, precise: false, flags: .maskControl))
        #expect(recorder.text.hasPrefix("\u{1b}[<82;"))
    }

    @Test func horizontalTravelDoesNotMoveVerticalScrollback() async throws {
        let (view, recorder) = terminal(modes: "")
        view.feed(text: String(repeating: "line\r\n", count: 200))
        view.scrollUp(lines: 20)
        let row = view.terminalStateSnapshot().viewportRow
        await scroll(view, try wheel(x: 100))
        #expect(view.terminalStateSnapshot().viewportRow == row)
        #expect(recorder.writes.isEmpty)
    }
}
