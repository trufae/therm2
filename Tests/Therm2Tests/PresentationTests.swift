import AppKit
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct PresentationTests {
    init() { _ = NSApplication.shared }

    @Test func losingAppFocusLeavesPresentationHandoffToAppKit() async {
        let delegate = AppDelegate()
        let originalOptions = NSApp.presentationOptions
        defer { NSApp.presentationOptions = originalOptions }
        NSApp.deactivate()
        #expect(!NSApp.isActive)
        let fullscreenOptions: NSApplication.PresentationOptions = [
            .autoHideDock, .autoHideMenuBar, .disableMenuBarTransparency
        ]
        NSApp.presentationOptions = fullscreenOptions

        // A key-window loss and app deactivation can both request an update.
        // Neither may reset presentation options during the app switch.
        delegate.updatePresentation()
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification,
                                                         object: NSApp))
        #expect(NSApp.presentationOptions == fullscreenOptions)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(NSApp.presentationOptions == fullscreenOptions)
        #expect(!NSApp.isActive)
        #expect(!NSApp.presentationOptions.contains(.disableProcessSwitching))
    }
}
