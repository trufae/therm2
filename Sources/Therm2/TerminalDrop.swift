import AppKit

/// Converts drag pasteboard contents to input for the pane that received the drop.
@MainActor
enum TerminalDrop {
    private static let imageTypes = NSBitmapImageRep.imageTypes.map { NSPasteboard.PasteboardType($0) }
    static let pasteboardTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string] + imageTypes +
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: pasteboardTypes) != nil
    }

    /// Promises (including screenshot thumbnails) finish asynchronously. Ordinary files
    /// keep their original paths; only image data and promises need temporary storage.
    @discardableResult
    static func receive(_ pasteboard: NSPasteboard,
                        completion: @escaping (Result<String, Error>) -> Void) -> Bool {
        do {
            // A screenshot may advertise a provisional URL as well as a promise.
            // Receive the promise so its file survives after the source finishes dragging.
            if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
                as? [NSFilePromiseReceiver], !promises.isEmpty {
                try receivePromises(promises, completion: completion)
                return true
            }
            if let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true]) as? [URL],
               !files.isEmpty {
                completion(.success(try paths(files)))
                return true
            }
            if let type = pasteboard.availableType(from: imageTypes) {
                guard let data = pasteboard.data(forType: type),
                      let bitmap = NSBitmapImageRep(data: data),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let file = try temporaryDirectory().appendingPathComponent("image.png")
                try png.write(to: file, options: .atomic)
                completion(.success(try paths([file])))
                return true
            }
            if let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
               !text.isEmpty {
                completion(.success(text))
                return true
            }
        } catch {
            completion(.failure(error))
        }
        return false
    }

    static func paths(_ files: [URL]) throws -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")
        return try files.map { file in
            let path = file.path
            // Control bytes would be interpreted or removed by terminal paste handling.
            guard file.isFileURL, !path.isEmpty,
                  path.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            if path.rangeOfCharacter(from: safe.inverted) == nil { return path }
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ") + " "
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Therm2-Drop-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        // Keep these files after the pane closes: programs may still be using the paths.
        return directory
    }

    static func receivePromises(_ receivers: [NSFilePromiseReceiver],
                                completion: @escaping (Result<String, Error>) -> Void) throws {
        let directory = try temporaryDirectory()
        PromisedDrop(receivers: receivers, completion: completion).receive(at: directory)
    }

    @MainActor private final class PromisedDrop {
        let receivers: [NSFilePromiseReceiver]
        let queue = OperationQueue()
        var expected: [Int]
        var files: [[URL]]
        var completion: ((Result<String, Error>) -> Void)?

        init(receivers: [NSFilePromiseReceiver], completion: @escaping (Result<String, Error>) -> Void) {
            self.receivers = receivers
            self.completion = completion
            expected = Array(repeating: 0, count: receivers.count)
            files = Array(repeating: [], count: receivers.count)
        }

        func receive(at directory: URL) {
            for (index, receiver) in receivers.enumerated() {
                receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) {
                    [self] url, error in
                    // Retain the receivers until delivery and marshal all state back to AppKit.
                    DispatchQueue.main.async { self.received(url, error: error, index: index) }
                }
                // Legacy promises can contain several files in one pasteboard item.
                expected[index] = max(1, receiver.fileNames.count)
            }
        }

        func received(_ url: URL, error: Error?, index: Int) {
            guard let completion else { return }
            if let error {
                self.completion = nil
                completion(.failure(error))
                return
            }
            files[index].append(url)
            guard zip(files, expected).allSatisfy({ $0.count == $1 }) else { return }
            self.completion = nil
            // Paste once, in drag order, even when providers complete out of order.
            completion(Result { try TerminalDrop.paths(files.flatMap { $0 }) })
        }
    }
}
