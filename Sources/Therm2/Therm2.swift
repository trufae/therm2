import AppKit

@main
enum Therm2 {
    @MainActor static func main() {
        let command: LaunchCommand?
        do {
            command = try LaunchCommand.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("Therm2: \(error)\n\(LaunchCommand.usage)\n".utf8))
            exit(2)
        }
        // A terminal needs repeated letters rather than the press-and-hold accent picker.
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
        let app = NSApplication.shared
        let delegate = AppDelegate(command: command)
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
