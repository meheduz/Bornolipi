import Foundation

/// The composition state of one typing session: what has been typed, which candidate is
/// selected, and what to commit. It contains no AppKit so it can be unit tested anywhere.
public final class PhoneticSession {
    public let suggester: Suggester
    public private(set) var buffer = ""
    public private(set) var suggestion = Suggestion(preceding: "", trailing: "", words: [""], selected: 0)
    public private(set) var selected = 0
    private var userPicked = false

    static let keepSelectionOn: Set<Character> = Set(".?!,:;-_)}]'\"")

    public init(suggester: Suggester) { self.suggester = suggester }

    public var isComposing: Bool { !buffer.isEmpty }
    public var candidates: [String] { suggestion.candidates }
    public var hasChoices: Bool { suggestion.words.count > 1 }

    /// The text shown inline (underlined) while composing.
    public var markedText: String {
        let c = candidates
        return selected < c.count ? c[selected] : ""
    }

    public func append(_ s: String) {
        let keep = userPicked && s.count == 1 && PhoneticSession.keepSelectionOn.contains(s.first!)
        let previous = selected
        buffer += s
        refresh()
        if keep { selected = min(previous, suggestion.words.count - 1) } else { userPicked = false }
    }

    /// Removes the last typed character. Returns false when there was nothing to remove.
    @discardableResult
    public func backspace() -> Bool {
        guard !buffer.isEmpty else { return false }
        buffer.removeLast()
        userPicked = false
        refresh()
        return true
    }

    public func moveSelection(by delta: Int) {
        let n = suggestion.words.count
        guard n > 0 else { return }
        // ↑ on the first candidate wraps to the engine's last candidate, as before words were appended after it
        // (the typed English word, when that setting is on); appended words are reached with ↓ or a click.
        if delta < 0, selected == 0, let k = suggestion.engineCount, k < n {
            // With one engine candidate the arrows did nothing before; ↑ still does nothing.
            guard k > 1 else { return }
            selected = k - 1
        } else {
            selected = ((selected + delta) % n + n) % n
        }
        userPicked = true
    }

    public func select(index: Int) -> Bool {
        guard index >= 0, index < suggestion.words.count else { return false }
        selected = index
        userPicked = true
        return true
    }

    /// True when the default candidate is an automatic correction (not the exact conversion) and
    /// the user has not moved to another candidate: Space would insert a correction.
    public var defaultIsAutocorrection: Bool {
        isComposing && !userPicked && selected == 0 && suggestion.autocorrected == 0
    }

    /// Reopens a committed word: `typed` becomes the buffer again with the exact conversion selected,
    /// as if the user had moved to it. Committing it then teaches Bornolipi to prefer it for this word.
    public func reopen(_ typed: String) {
        buffer = typed
        refresh()
        if let exact = suggestion.exactIndex { selected = exact; userPicked = true }
    }

    /// Finishes the word. Returns the text to insert and clears the session.
    public func commit() -> String {
        let text = markedText
        if isComposing, suggester.settings.learnChoices, selected != suggestion.selected, selected < suggestion.words.count {
            suggester.learn(buffer: buffer, chosenWord: suggestion.words[selected])
        }
        reset()
        return text
    }

    /// Returns the raw English characters typed so far and clears the session.
    public func takeRaw() -> String {
        let raw = buffer
        reset()
        return raw
    }

    public func reset() {
        buffer = ""
        selected = 0
        userPicked = false
        suggestion = Suggestion(preceding: "", trailing: "", words: [""], selected: 0)
    }

    /// Recomputes the candidates for what is typed now (new data became available, such as the
    /// dictionary finishing loading). A candidate the user already moved to is left alone.
    /// Returns true when the candidates changed.
    @discardableResult
    public func refreshForNewData() -> Bool {
        guard isComposing, !userPicked else { return false }
        let before = suggestion
        refresh()
        return suggestion != before
    }

    private func refresh() {
        if buffer.isEmpty { reset(); return }
        suggestion = suggester.suggest(buffer)
        selected = suggestion.selected
    }
}
