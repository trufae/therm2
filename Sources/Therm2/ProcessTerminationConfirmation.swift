import AppKit

@MainActor
enum ProcessTerminationConfirmation {
    private static var isPresenting = false

    static func confirm(_ action: String, panes: [TerminalPane],
                        runModal: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }) -> Bool {
        guard !isPresenting else { return false }
        guard panes.contains(where: \.hasRunningPrograms) else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(action) with running programs?"
        alert.informativeText = "Continuing will terminate the running programs in the affected terminal sessions."
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let confirm = alert.addButton(withTitle: action)
        confirm.keyEquivalent = ""
        confirm.hasDestructiveAction = true

        isPresenting = true
        defer { isPresenting = false }
        return runModal(alert) == .alertSecondButtonReturn
    }
}
