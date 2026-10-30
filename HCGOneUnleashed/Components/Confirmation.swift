import AppKit

/// Confirmation for destructive actions started from menu commands, which
/// cannot present SwiftUI dialogs themselves.
@MainActor
enum Confirmation {
    /// Shows a modal warning alert; `true` when the user chose `action`.
    static func confirm(_ title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let confirm = alert.addButton(withTitle: action)
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static let resetSessionTitle = "Reset the simulated session?"
    static let resetSessionMessage = "All four simulated markets restart and the simulated account returns to its starting balance. Positions, working orders and trade history are cleared. Nothing outside this Mac is affected."
    static let resetAccountTitle = "Reset the simulated account?"
    static let resetAccountMessage = "Positions and working orders are removed, order and trade history are cleared, and the balance returns to the starting balance set in Settings. The simulated markets keep running."
}
