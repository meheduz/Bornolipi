#if canImport(InputMethodKit)
import AppKit
import Carbon
import InstallKit

/// The running keyboard's side of a hand-over to newly installed files (see `KeyboardRestart`).
/// It quits only when no word can be in progress, or when the user asked, after committing it.
final class KeyboardLifecycle: NSObject {
    static let shared = KeyboardLifecycle()
    /// A newer keyboard has been installed; quit as soon as Bornolipi is not the selected input source.
    private(set) var restartPending = false

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(restartRequested(_:)), name: KeyboardRestart.Channel.keyboard.request,
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func restartRequested(_ note: Notification) {
        let token = note.object as? String ?? ""
        let mode = KeyboardRestart.Mode(rawValue: note.userInfo?["mode"] as? String ?? "") ?? .whenSafe
        let decision = KeyboardRestart.decide(mode, bornolipiSelected: KeyboardLifecycle.bornolipiSelected())
        if decision.commitFirst { finishTyping() }
        restartPending = decision.quitOnSourceChange
        KeyboardRestart.answer(token: token, decision.reply)
        if decision.quit { quit() }
    }

    /// Only ever after the user asked: the unfinished word goes into the document first.
    func restartNow() {
        finishTyping()
        quit()
    }

    /// The user switched to another input source: a pending restart can happen now.
    func sourceChangedAway() {
        if restartPending { quit() }
    }

    func finishTyping() {
        InputController.active?.finishAfterSourceChange()
        CandidatePanel.shared.hide()
        HUD.shared.hide()
    }

    private func quit() {
        // Lets the answer go out before the process ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
    }

    static func bornolipiSelected() -> Bool {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let id = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        return KeyboardIdentity.owns(sourceID: id, bundleID: Bundle.main.bundleIdentifier ?? "-")
    }
}
#endif
