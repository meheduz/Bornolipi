#if canImport(InputMethodKit)
import AppKit
import Carbon
import InputMethodKit
import BanglaEngine

/// One controller exists per text-input client. It turns NSEvents into `KeyPress`es for the engine's
/// `InputHandler`, which owns the key policy, and shows the result: marked (underlined) text in the
/// host app and the candidate window.
@objc(BornolipiInputController)
final class InputController: IMKInputController {
    private lazy var handler: InputHandler? = Engine.shared.suggester.map(InputHandler.init)
    private var panelUpdatePending = false
    private var lastCaret: NSRect?

    /// The controller that last received keys. macOS 26 and later can switch input sources without
    /// calling deactivateServer, so the app delegate commits through this when that happens.
    static weak var active: InputController?

    fileprivate static let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    /// When the mode was switched from the input menu: choosing the item deactivates the keyboard
    /// in the app, which hides the বাং/EN bubble at once, so it is shown again on return.
    private static var modeSwitchedFromMenu: (app: String?, at: Date)?

    // MARK: IMK overrides

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        InputController.active = self
        Engine.shared.appActivated((sender as? IMKTextInput)?.bundleIdentifier())
        Log.imk.debug("activate in \((sender as? IMKTextInput)?.bundleIdentifier() ?? "?", privacy: .public)")
        if let switched = InputController.modeSwitchedFromMenu {
            InputController.modeSwitchedFromMenu = nil
            if Date().timeIntervalSince(switched.at) < 3, let client = sender as? IMKTextInput,
               client.bundleIdentifier() == switched.app {
                DispatchQueue.main.async { [weak self] in self?.showModeHUD(client) }
            }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        Log.imk.debug("deactivate in \((sender as? IMKTextInput)?.bundleIdentifier() ?? "?", privacy: .public)")
        commitCurrent(sender)
        super.deactivateServer(sender)
    }

    /// The client wants the composition finished now (click elsewhere, focus change).
    override func commitComposition(_ sender: Any!) {
        Log.imk.debug("commitComposition")
        commitCurrent(sender)
    }

    /// IMK's default replaces the marked text with `originalString(_:)`: the roman letters typed, so
    /// nothing the user typed is lost. Then the composition is forgotten.
    override func cancelComposition() {
        Log.imk.debug("cancelComposition")
        super.cancelComposition()
        handler?.cancel()
        CandidatePanel.shared.hide()
    }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: handler?.typedText ?? "")
    }

    override func composedString(_ sender: Any!) -> Any! {
        handler?.isComposing == true ? handler?.session.markedText : ""
    }

    override func hidePalettes() {
        CandidatePanel.shared.hide()
        HUD.shared.hide()
        super.hidePalettes()
    }

    override func inputControllerWillClose() {
        handler?.cancel()
        CandidatePanel.shared.hide()
        super.inputControllerWillClose()
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        // Explicit Bangla and English items: macOS shows a cached copy of this menu, so nothing in it
        // may depend on the current mode (see ModeMenu).
        for item in ModeMenu.items {
            let action = item.bangla ? #selector(chooseBangla(_:)) : #selector(chooseEnglish(_:))
            let entry = menu.addItem(withTitle: item.title, action: action, keyEquivalent: "")
            entry.target = self
        }
        let hint = menu.addItem(withTitle: ModeMenu.hint(SettingsStore.shared.settings.toggleShortcut), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(.separator())
        let prefs = menu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        prefs.target = self
        if KeyboardLifecycle.shared.restartPending {
            menu.addItem(.separator())
            let finish = menu.addItem(withTitle: "Restart to Finish Updating", action: #selector(finishUpdate(_:)), keyEquivalent: "")
            finish.target = self
        }
        return menu
    }

    /// Menu actions; IMK passes an info dictionary as the sender, so the client comes from `client()`.
    @objc func chooseBangla(_ sender: Any?) { chooseMode(ModeMenu.items[0]) }
    @objc func chooseEnglish(_ sender: Any?) { chooseMode(ModeMenu.items[1]) }

    /// Choosing the mode already in use changes nothing but still shows the bubble: the menu cannot
    /// show the mode, so choosing either item always tells the user which mode is on.
    private func chooseMode(_ item: ModeMenuItem) {
        if ModeMenu.choose(item, current: Engine.shared.isBangla) != nil {
            commitCurrent(client())
            Engine.shared.toggleMode(in: client()?.bundleIdentifier())
        }
        InputController.modeSwitchedFromMenu = (client()?.bundleIdentifier(), Date())
        if let client = client() { showModeHUD(client) }
    }

    @objc func finishUpdate(_ sender: Any?) {
        KeyboardLifecycle.shared.restartNow()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    // MARK: Key handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        // A nil event (the Character Viewer sends one) means: finish the word.
        guard let event else { commitCurrent(sender); return false }
        guard event.type == .keyDown, let handler, let client = sender as? IMKTextInput else { return false }
        InputController.active = self
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command, .capsLock])
        let key = KeyPress(keyCode: event.keyCode, characters: event.characters, modifiers: flags.rawValue)
        let result = handler.handle(key, bangla: Engine.shared.isBangla, client: Bridge(client: client, controller: self))
        if result == .toggleMode {
            Engine.shared.toggleMode(in: client.bundleIdentifier())
            showModeHUD(client)
        }
        schedulePanelUpdate(client)
        return result != .passThrough
    }

    // MARK: Helpers

    /// The dictionary finished loading while a word was being typed: show its full candidates.
    func dictionaryBecameReady() {
        guard let handler, let client = client() else { return }
        if handler.dataBecameAvailable(Bridge(client: client, controller: self)) { schedulePanelUpdate(client) }
    }

    /// Commits and hides everything, for an input source switch that skipped deactivateServer.
    func finishAfterSourceChange() { commitCurrent(client()) }

    private func commitCurrent(_ sender: Any!) {
        guard let handler else { return }
        if let client = (sender as? IMKTextInput) ?? client() {
            handler.commit(Bridge(client: client, controller: self))
        } else {
            handler.cancel()
        }
        CandidatePanel.shared.hide()
    }

    /// The candidate window is drawn after `handle` returns, so the host app is not kept waiting
    /// for view layout; several fast keys result in one redraw.
    private func schedulePanelUpdate(_ client: IMKTextInput) {
        guard !panelUpdatePending else { return }
        panelUpdatePending = true
        DispatchQueue.main.async { [weak self, weak client] in
            guard let self else { return }
            self.panelUpdatePending = false
            guard let client, let list = self.handler?.candidateList else {
                CandidatePanel.shared.hide()
                return
            }
            CandidatePanel.shared.onPick = { [weak self, weak client] index in
                guard let self, let client, let handler = self.handler else { return }
                if handler.pick(index, client: Bridge(client: client, controller: self)) { CandidatePanel.shared.hide() }
            }
            CandidatePanel.shared.show(list, near: self.caretRect(client), clientLevel: Int(client.windowLevel()))
        }
    }

    private func caretRect(_ client: IMKTextInput) -> NSRect {
        // Start non-zero (some clients mishandle a zero rect); (0,0) or off-screen means "unknown",
        // as Google Docs in Chrome reports. Then reuse the last good position, then the mouse.
        var rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
        if rect.origin != .zero, onScreen {
            lastCaret = rect
            return rect
        }
        if let lastCaret { return lastCaret }
        Log.imk.debug("no caret rectangle from \(client.bundleIdentifier() ?? "?", privacy: .public); using the mouse position")
        let p = NSEvent.mouseLocation
        return NSRect(x: p.x, y: p.y, width: 1, height: 16)
    }

    private func showModeHUD(_ client: IMKTextInput) {
        CandidatePanel.shared.hide()
        HUD.shared.flash(Engine.shared.isBangla ? "বাং" : "EN", near: caretRect(client))
    }

    /// The system's standard composition style (underline and clause attributes) for `length` UTF-16 units.
    fileprivate func compositionAttributes(_ length: Int) -> [NSAttributedString.Key: Any] {
        guard length > 0, let marks = mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: length)) else {
            return [.underlineStyle: NSUnderlineStyle.single.rawValue]
        }
        var out: [NSAttributedString.Key: Any] = [:]
        for (key, value) in marks {
            if let k = key as? String { out[NSAttributedString.Key(k)] = value }
        }
        return out
    }
}

/// Sends the handler's output to the host app.
private struct Bridge: TextClient {
    let client: IMKTextInput
    unowned let controller: InputController

    func insert(_ text: String) {
        client.insertText(text, replacementRange: InputController.noRange)
    }

    func setMarked(_ text: String) {
        let length = text.utf16.count
        let string = NSAttributedString(string: text, attributes: controller.compositionAttributes(length))
        client.setMarkedText(string, selectionRange: NSRange(location: length, length: 0),
                             replacementRange: InputController.noRange)
    }

    /// The text just before the caret, when the app reports a caret position and can return text.
    func textBeforeCaret(utf16Length: Int) -> String? {
        let caret = client.selectedRange()
        guard caret.location != NSNotFound, caret.length == 0, caret.location >= utf16Length else { return nil }
        return client.attributedSubstring(from: NSRange(location: caret.location - utf16Length, length: utf16Length))?.string
    }

    func remark(utf16Length: Int, as marked: String) -> Bool {
        let caret = client.selectedRange()
        guard caret.location != NSNotFound, caret.location >= utf16Length else { return false }
        let length = marked.utf16.count
        let string = NSAttributedString(string: marked, attributes: controller.compositionAttributes(length))
        client.setMarkedText(string, selectionRange: NSRange(location: length, length: 0),
                             replacementRange: NSRange(location: caret.location - utf16Length, length: utf16Length))
        return true
    }
}
#endif
