import AppKit

@main
enum Therm2 {
    @MainActor static func main() {
        // A terminal needs repeated letters rather than the press-and-hold accent picker.
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
