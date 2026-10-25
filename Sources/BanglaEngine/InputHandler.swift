import Foundation

/// A key press as the input method sees it. The app fills it from an NSEvent; tests build it directly.
public struct KeyPress: Equatable {
    public var keyCode: UInt16
    /// The characters the keyboard layout produced (NSEvent.characters).
    public var characters: String?
    /// Modifier bits, same values as NSEvent.ModifierFlags (see `Shortcut`).
    public var modifiers: UInt

    public static let capsLock: UInt = 1 << 16

    public init(keyCode: UInt16, characters: String?, modifiers: UInt = 0) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
    }

    var hasCommandModifier: Bool { modifiers & (Shortcut.command | Shortcut.control | Shortcut.option) != 0 }
}

/// Virtual key codes the handler cares about (US layout positions, same on every layout).
public enum KeyCode {
    public static let delete: UInt16 = 51, space: UInt16 = 49, returnKey: UInt16 = 36, enter: UInt16 = 76
    public static let tab: UInt16 = 48, escape: UInt16 = 53
    public static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    public static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121
}

/// Where the handler sends text: the app wraps the IMK client, tests record the calls.
public protocol TextClient {
    /// Ends the composition with this text.
    func insert(_ text: String)
    /// Shows the word being typed (underlined in the host app). An empty string removes it.
    func setMarked(_ text: String)
    /// The `utf16Length` UTF-16 units just before the caret, or nil when the app cannot tell.
    func textBeforeCaret(utf16Length: Int) -> String?
    /// Turns the `utf16Length` UTF-16 units before the caret back into a word being typed, shown as
    /// `marked`. Returns false (changing nothing) when the app does not support it.
    func remark(utf16Length: Int, as marked: String) -> Bool
}

public extension TextClient {
    func textBeforeCaret(utf16Length: Int) -> String? { nil }
    func remark(utf16Length: Int, as marked: String) -> Bool { false }
}

/// The candidate list to draw, if any.
public struct CandidateList: Equatable {
    public let candidates: [String]
    public let selected: Int
    /// The roman text typed so far.
    public let typed: String

    public init(candidates: [String], selected: Int, typed: String) {
        self.candidates = candidates
        self.selected = selected
        self.typed = typed
    }
}

/// Turns key presses into composition updates. Contains the input method's whole key policy so it
/// can be tested without AppKit; the macOS controller only translates events and draws the result.
public final class InputHandler {
    public enum Result: Equatable {
        /// The app must handle the key itself.
        case passThrough
        /// The key was used up.
        case handled
        /// The Bangla/English shortcut was pressed; any word was committed. The key was used up.
        case toggleMode
    }

    public let session: PhoneticSession
    private var settings: EngineSettings { session.suggester.settings }
    /// After Space committed an automatic correction: what was inserted and what was typed, so the
    /// very next Backspace can reopen the word. Any other event forgets it.
    private var undoableCorrection: (inserted: String, typed: String)?

    public init(suggester: Suggester) { session = PhoneticSession(suggester: suggester) }

    public var isComposing: Bool { session.isComposing }

    /// The candidate window contents, or nil when it should be hidden.
    public var candidateList: CandidateList? {
        guard session.isComposing, session.hasChoices, settings.suggestions else { return nil }
        return CandidateList(candidates: session.candidates, selected: session.selected, typed: session.buffer)
    }

    public func handle(_ key: KeyPress, bangla: Bool, client: TextClient) -> Result {
        let correction = undoableCorrection
        undoableCorrection = nil
        if settings.toggleShortcut.matches(keyCode: key.keyCode, modifiers: key.modifiers) {
            commit(client)
            return .toggleMode
        }
        guard bangla else { return .passThrough }

        let mods = key.modifiers & Shortcut.mask
        // Ctrl+Delete drops the whole word being composed.
        if key.keyCode == KeyCode.delete, mods == Shortcut.control, session.isComposing {
            session.reset()
            refresh(client)
            return .handled
        }
        // Command / Control / Option shortcuts belong to the app: finish the word first.
        if key.hasCommandModifier {
            commit(client)
            return .passThrough
        }

        switch key.keyCode {
        case KeyCode.delete:
            if !session.isComposing, mods == 0, let correction, reopen(correction, client: client) { return .handled }
            guard session.isComposing else { return .passThrough }
            session.backspace()
            refresh(client)
            return .handled
        case KeyCode.space:
            guard session.isComposing else { return .passThrough }
            let typed = session.buffer
            let corrected = session.defaultIsAutocorrection
            let inserted = session.commit() + " "
            client.insert(inserted)
            if corrected && settings.undoAutocorrect { undoableCorrection = (inserted, typed) }
            return .handled
        case KeyCode.returnKey, KeyCode.enter, KeyCode.tab:
            // Commit, then let the app see the key (new line, send, next field), as Avro does.
            commit(client)
            return .passThrough
        case KeyCode.escape:
            guard session.isComposing else { return .passThrough }
            client.insert(session.takeRaw())
            return .handled
        case KeyCode.left, KeyCode.right, KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown:
            commit(client)
            return .passThrough
        case KeyCode.down, KeyCode.up:
            guard session.isComposing else { return .passThrough }
            if session.hasChoices {
                session.moveSelection(by: key.keyCode == KeyCode.down ? 1 : -1)
                refresh(client)
            }
            return .handled
        default:
            break
        }

        guard let typed = InputHandler.typedCharacter(key) else {
            commit(client)
            return .passThrough
        }
        if !session.isComposing, !settings.banglaDigits, typed.first?.isNumber == true {
            return .passThrough
        }
        session.append(typed)
        refresh(client)
        return .handled
    }

    /// Backspace right after an automatic correction: the corrected word (and its space) becomes the
    /// word being typed again, with the exact Avro conversion selected. Only when the text before the
    /// caret is still exactly what was inserted; otherwise Backspace works as usual.
    private func reopen(_ correction: (inserted: String, typed: String), client: TextClient) -> Bool {
        let length = correction.inserted.utf16.count
        guard client.textBeforeCaret(utf16Length: length) == correction.inserted else { return false }
        session.reopen(correction.typed)
        guard client.remark(utf16Length: length, as: session.markedText) else { session.reset(); return false }
        return true
    }

    /// Commits the word being composed, if any (focus change, input source switch, shortcut).
    public func commit(_ client: TextClient) {
        undoableCorrection = nil
        guard session.isComposing else { return }
        client.insert(session.commit())
    }

    /// Picks a candidate by position (mouse click) and commits it. Returns false for a bad index.
    @discardableResult
    public func pick(_ index: Int, client: TextClient) -> Bool {
        undoableCorrection = nil
        guard session.isComposing, session.select(index: index) else { return false }
        client.insert(session.commit())
        return true
    }

    /// The dictionary finished loading: update the word being typed, if its candidates change.
    /// Returns true when the marked text or candidate list was updated.
    @discardableResult
    public func dataBecameAvailable(_ client: TextClient) -> Bool {
        guard session.refreshForNewData() else { return false }
        refresh(client)
        return true
    }

    /// Forgets the composition without inserting anything.
    public func cancel() { undoableCorrection = nil; session.reset() }

    /// The roman text typed so far, for `IMKInputController.originalString`.
    public var typedText: String { session.buffer }

    private func refresh(_ client: TextClient) {
        client.setMarked(session.isComposing ? session.markedText : "")
    }

    /// The printable ASCII character for this key press, or nil.
    static func typedCharacter(_ key: KeyPress) -> String? {
        guard let chars = key.characters, chars.unicodeScalars.count == 1,
              let scalar = chars.unicodeScalars.first, scalar.value >= 0x21, scalar.value <= 0x7E else { return nil }
        // Caps Lock should not turn every consonant into its capital (aspirated/retroflex) form.
        if key.modifiers & KeyPress.capsLock != 0, key.modifiers & Shortcut.shift == 0 {
            return chars.lowercased()
        }
        return chars
    }
}
