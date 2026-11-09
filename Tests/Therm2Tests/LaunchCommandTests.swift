import Foundation
import Testing
@testable import Therm2

struct LaunchCommandTests {
    @Test func normalLaunchIgnoresAppKitArguments() throws {
        #expect(try LaunchCommand.parse([]) == nil)
        #expect(try LaunchCommand.parse(["-psn_0_12345", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    }

    @Test func commandArgumentsRemainLiteral() throws {
        let arguments = ["space here", "", "'quotes'", "$HOME; * | >", "-e", "--help"]
        let command = try #require(try LaunchCommand.parse(["-psn_0_12345", "-e", "/bin/sh"] + arguments))
        #expect(command.name == "/bin/sh")
        #expect(command.executable == "/bin/sh")
        #expect(command.arguments == arguments)
    }

    @Test(arguments: [["-e"], ["-e", ""], ["-e", "/therm2/no-such-command"]])
    func invalidCommandsAreRejected(arguments: [String]) {
        #expect(throws: LaunchCommand.InvalidCommand.self) {
            try LaunchCommand.parse(arguments)
        }
    }

    @Test func resolvesPathEntriesAndRelativeExecutablesAgainstLaunchDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Therm2-Launch-" + UUID().uuidString)
        let bin = root.appendingPathComponent("bin with spaces")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = bin.appendingPathComponent("tool")
        try FileManager.default.createSymbolicLink(atPath: executable.path, withDestinationPath: "/bin/sh")

        // An executable directory must not shadow a real command later in PATH.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tool"), withIntermediateDirectories: true)
        let command = try #require(try LaunchCommand.parse(["-e", "tool"], directory: root.path,
                                                          path: ":bin with spaces"))
        #expect(command.executable == executable.path)
        #expect(command.directory == root.path)
        let relative = try #require(try LaunchCommand.parse(["-e", "./bin with spaces/tool"],
                                                           directory: root.path, path: "/missing"))
        #expect(URL(fileURLWithPath: relative.executable).standardizedFileURL == executable.standardizedFileURL)
        let emptyPath = try #require(try LaunchCommand.parse(["-e", "tool"], directory: bin.path, path: ""))
        #expect(emptyPath.executable == executable.path)

        // Files without execute permission are not launchable commands.
        let text = root.appendingPathComponent("text")
        try Data("hello".utf8).write(to: text)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: text.path)
        #expect(throws: LaunchCommand.InvalidCommand.self) {
            try LaunchCommand.parse(["-e", "text"], directory: root.path, path: "")
        }
        #expect(throws: LaunchCommand.InvalidCommand.self) {
            try LaunchCommand.parse(["-e", "./tool"], directory: root.path, path: bin.path)
        }
    }
}
