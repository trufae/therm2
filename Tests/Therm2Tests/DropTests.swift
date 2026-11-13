import AppKit
import SwiftTerm
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct DropTests {
    init() { _ = NSApplication.shared }

    private final class Recorder: TerminalViewDelegate {
        var text = ""
        func send(source: TerminalView, data: ArraySlice<UInt8>) { text += String(decoding: data, as: UTF8.self) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    }

    private final class Drag: NSObject, NSDraggingInfo {
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .copy
        var draggingLocation: NSPoint = .zero
        var draggedImageLocation: NSPoint = .zero
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 0
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func resetSpringLoading() {}
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                                    classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    }

    private func flushOutput() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test(arguments: [false, true])
    func filesDropIntoTargetPaneAndHonorBracketedPaste(bracketed: Bool) async throws {
        let window = TerminalWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let tab = TerminalTab(directory: NSTemporaryDirectory())
        window.contentView = tab.root
        let target = tab.activePane
        let sibling = try #require(tab.split(vertical: true))
        window.contentView = tab.root
        window.makeFirstResponder(sibling)
        let recorder = Recorder()
        let siblingRecorder = Recorder()
        target.terminalDelegate = recorder
        sibling.terminalDelegate = siblingRecorder
        if bracketed { target.feed(text: "\u{1b}[?2004h") }
        let drag = Drag()
        defer { drag.draggingPasteboard.releaseGlobally() }
        drag.draggingDestinationWindow = window
        let files = [URL(fileURLWithPath: "/tmp/a screenshot.png"), URL(fileURLWithPath: "/tmp/folder")]
        #expect(drag.draggingPasteboard.writeObjects(files as [NSURL]))
        #expect(target.registeredDraggedTypes.contains(.fileURL))
        #expect(NSFilePromiseReceiver.readableDraggedTypes.allSatisfy {
            target.registeredDraggedTypes.contains(NSPasteboard.PasteboardType($0))
        })
        #expect(target.draggingEntered(drag) == .copy)
        #expect(target.draggingUpdated(drag) == .copy)
        #expect(target.prepareForDragOperation(drag))
        #expect(target.performDragOperation(drag))
        await flushOutput()
        let text = "'/tmp/a screenshot.png' /tmp/folder "
        #expect(recorder.text == (bracketed ? "\u{1b}[200~" + text + "\u{1b}[201~" : text))
        #expect(siblingRecorder.text.isEmpty)
        #expect(window.firstResponder === target)
        #expect(tab.activePane === target)
    }

    @Test func quotedPathsRoundTripThroughShellsWithoutExpansion() throws {
        let paths = ["/tmp/plain", "/tmp/a b's \"$HOME\";$(printf BAD)`printf BAD`[1]*?.png", "/tmp/日本語 café"]
        let files = paths.map { URL(fileURLWithPath: $0) }
        let quoted = try TerminalDrop.paths(files)
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", "printf '%s\\0' " + quoted]
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(data == Data((files.map(\.path).joined(separator: "\0") + "\0").utf8))
        }
        #expect(throws: CocoaError.self) {
            try TerminalDrop.paths([URL(fileURLWithPath: "/tmp/line\nbreak")])
        }
    }

    @Test(arguments: [NSBitmapImageRep.FileType.png, .tiff, .jpeg])
    func imageDataCreatesReadableTemporaryPNG(type: NSBitmapImageRep.FileType) throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 3,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<3 {
            for x in 0..<2 {
                bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        let data = try #require(bitmap.representation(using: type, properties: [:]))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let pasteboardType: NSPasteboard.PasteboardType = type == .png ? .png :
            type == .tiff ? .tiff : NSPasteboard.PasteboardType("public.jpeg")
        pasteboard.setData(data, forType: pasteboardType)
        pasteboard.setString("image fallback text", forType: .string)
        var result: Result<String, Error>?
        #expect(TerminalDrop.receive(pasteboard) { result = $0 })
        let text = try #require(result).get()
        let path = String(text.dropLast())
        let file = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let saved = try #require(NSBitmapImageRep(data: Data(contentsOf: file)))
        #expect(saved.pixelsWide == 2)
        #expect(saved.pixelsHigh == 3)
        #expect(file.pathExtension == "png")
        #expect(try #require(saved.colorAt(x: 0, y: 0)).redComponent > 0.9)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func unsupportedInvalidAndMoveOnlyDropsDoNotInsertAnything() async {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        let recorder = Recorder()
        pane.terminalDelegate = recorder
        let drag = Drag()
        defer { drag.draggingPasteboard.releaseGlobally() }
        drag.draggingPasteboard.setString("unknown", forType: NSPasteboard.PasteboardType("test.unknown"))
        #expect(pane.draggingEntered(drag).isEmpty)
        #expect(!pane.performDragOperation(drag))
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.setString("hello", forType: .string)
        drag.draggingSourceOperationMask = .move
        #expect(pane.draggingEntered(drag).isEmpty)
        #expect(!pane.performDragOperation(drag))
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.setData(Data([0, 1, 2]), forType: .png)
        var failed = false
        #expect(!TerminalDrop.receive(drag.draggingPasteboard) { if case .failure = $0 { failed = true } })
        #expect(failed)
        await flushOutput()
        #expect(recorder.text.isEmpty)
    }

    @Test func textAndWebLinksUsePasteWithoutChangingClipboard() async {
        let pane = TerminalPane(directory: NSTemporaryDirectory())
        let recorder = Recorder()
        pane.terminalDelegate = recorder
        let drag = Drag()
        defer { drag.draggingPasteboard.releaseGlobally() }
        let clipboardVersion = NSPasteboard.general.changeCount
        for type in [NSPasteboard.PasteboardType.string, .URL] {
            drag.draggingPasteboard.clearContents()
            drag.draggingPasteboard.setString("https://example.com/image.png", forType: type)
            #expect(pane.performDragOperation(drag))
            await flushOutput()
            #expect(recorder.text == "https://example.com/image.png")
            recorder.text = ""
        }
        #expect(NSPasteboard.general.changeCount == clipboardVersion)
    }

    private final class Promise: NSFilePromiseReceiver {
        // AppKit invokes this unannotated callback on the supplied operation queue.
        private struct Reader: @unchecked Sendable {
            let callback: (URL, Error?) -> Void
        }

        let names: [String]
        var destination: URL?
        private var reader: Reader?
        private var queue: OperationQueue?
        override var fileNames: [String] { destination == nil ? [] : names }

        init(_ names: [String]) { self.names = names; super.init() }

        required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
            fatalError("Use init(_:)")
        }

        override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any],
                                          operationQueue: OperationQueue,
                                          reader: @escaping (URL, Error?) -> Void) {
            destination = destinationDir
            self.reader = Reader(callback: reader)
            queue = operationQueue
        }

        @MainActor func finish(error: Error? = nil) async throws {
            let destination = try #require(destination)
            let reader = try #require(reader)
            let queue = try #require(queue)
            self.reader = nil
            let files = try names.map { name in
                let file = destination.appendingPathComponent(name)
                if error == nil { try Data("promised image".utf8).write(to: file) }
                return file
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.addOperation {
                    #expect(!Thread.isMainThread)
                    for file in files { reader.callback(file, error) }
                    continuation.resume()
                }
            }
        }
    }

    @Test func delayedPromisesWaitForAllFilesAndPreserveDragOrder() async throws {
        let first = Promise(["Screenshot 1.png", "Screenshot 2.png"])
        let second = Promise(["Screenshot 3.png"])
        var results: [Result<String, Error>] = []
        try TerminalDrop.receivePromises([first, second]) { results.append($0) }
        let directory = try #require(first.destination)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(second.destination == directory)
        try await second.finish()
        await flushOutput()
        #expect(results.isEmpty)
        try await first.finish()
        await flushOutput()
        #expect(results.count == 1)
        let files = (first.names + second.names).map { directory.appendingPathComponent($0) }
        #expect(try results.first?.get() == TerminalDrop.paths(files))
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func failedPromisesNeverPastePartialResults() async throws {
        let first = Promise(["one.png"])
        let second = Promise(["two.png"])
        var results: [Result<String, Error>] = []
        try TerminalDrop.receivePromises([first, second]) { results.append($0) }
        let directory = try #require(first.destination)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await second.finish(error: CocoaError(.fileWriteNoPermission))
        try await first.finish()
        await flushOutput()
        #expect(results.count == 1)
        #expect(throws: CocoaError.self) { try results.first?.get() }
    }
}
