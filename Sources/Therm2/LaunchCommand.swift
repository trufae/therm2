import Foundation

struct LaunchCommand {
    static let usage = "Usage: Therm2 [-e command [args...]]"
    static let defaultPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    let name: String
    let executable: String
    let arguments: [String]
    let directory: String

    struct InvalidCommand: Error, CustomStringConvertible {
        let description: String
    }

    /// AppKit may supply its own arguments before -e. Everything after it belongs
    /// to the child, including flags, empty arguments, and shell metacharacters.
    static func parse(_ arguments: [String],
                      directory: String = FileManager.default.currentDirectoryPath,
                      path: String = ProcessInfo.processInfo.environment["PATH"] ?? defaultPath) throws -> LaunchCommand? {
        guard let index = arguments.firstIndex(of: "-e") else { return nil }
        let command = arguments.dropFirst(index + 1)
        guard let name = command.first, !name.isEmpty else {
            throw InvalidCommand(description: "-e requires a command")
        }

        let base = URL(fileURLWithPath: directory, isDirectory: true)
        let candidates: [String]
        if name.contains("/") {
            candidates = [name]
        } else {
            candidates = path.split(separator: ":", omittingEmptySubsequences: false).map {
                $0.isEmpty ? name : "\($0)/\(name)"
            }
        }
        for candidate in candidates {
            let executable = URL(fileURLWithPath: candidate, relativeTo: base).path
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: executable, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: executable) {
                return LaunchCommand(name: name, executable: executable,
                                     arguments: Array(command.dropFirst()), directory: directory)
            }
        }
        throw InvalidCommand(description: "command not found or not executable: \(name)")
    }
}
