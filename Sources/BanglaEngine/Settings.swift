import Foundation

/// A keyboard shortcut stored as a macOS virtual key code plus modifier bits.
/// Modifier bits use the same values as `NSEvent.ModifierFlags` so the app can compare directly.
public struct Shortcut: Codable, Equatable {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    public static let mask: UInt = shift | control | option | command

    public var keyCode: UInt16
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Shortcut.mask
    }

    /// Control + Shift + B. (Control + Shift + Space, the old default, never arrives: macOS treats it as
    /// its own "select the previous input source" shortcut, Control + Space, in reverse.)
    public static let defaultToggle = Shortcut(keyCode: 11, modifiers: control | shift)
    static let oldDefaultToggle = Shortcut(keyCode: 49, modifiers: control | shift)

    public func matches(keyCode: UInt16, modifiers: UInt) -> Bool {
        self.keyCode == keyCode && self.modifiers == (modifiers & Shortcut.mask)
    }

    public var display: String {
        var s = ""
        if modifiers & Shortcut.control != 0 { s += "⌃" }
        if modifiers & Shortcut.option != 0 { s += "⌥" }
        if modifiers & Shortcut.shift != 0 { s += "⇧" }
        if modifiers & Shortcut.command != 0 { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 76: "Enter",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S",
            17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        ]
        return names[code] ?? "Key \(code)"
    }
}

/// How the nukta letters ড় ঢ় য় are encoded in the output.
public enum Normalization: String, Codable, CaseIterable {
    /// One code point each (U+09DC, U+09DD, U+09DF), exactly as Avro Keyboard and OpenBangla write them.
    case avro
    /// Unicode NFC, where those letters are a base letter plus nukta (U+09BC), as on the web and Wikipedia.
    case nfc
}

/// User-facing options. Every field has a default so older saved settings keep loading.
public struct EngineSettings: Codable, Equatable {
    public var suggestions = true          // dictionary based candidates
    public var autocorrect = true          // roman autocorrect table
    public var completions = true          // longer words that start with what you typed
    public var includeEnglish = false      // offer the typed English text as a candidate
    public var banglaDigits = true         // 123 -> ১২৩
    public var maxCandidates = 8
    public var startInBangla = true
    public var toggleShortcut = Shortcut.defaultToggle
    public var userAutocorrect: [String: String] = [:]
    public var normalization = Normalization.avro
    public var learnChoices = true         // remember the candidate picked for a typed word
    public var candidateTextSize = 17      // points, in the candidate window
    public var undoAutocorrect = true      // Backspace right after an autocorrection reopens the word
    public var rememberModePerApp = false  // Bangla/English remembered per app (off: one mode everywhere)
    /// Experimental: for lowercase input, up to 3 known words found by the loanword retriever (term:
    /// টার্ম) after the engine's own candidates, which keep their places. What Space inserts never changes.
    public var loanwordSuggestions = false
    public static let candidateTextSizes = 13...28

    public init() {}

    enum CodingKeys: String, CodingKey {
        case suggestions, autocorrect, completions, includeEnglish, banglaDigits
        case maxCandidates, startInBangla, toggleShortcut, userAutocorrect, normalization, learnChoices, candidateTextSize, undoAutocorrect, rememberModePerApp
        case loanwordSuggestions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineSettings()
        suggestions = try c.decodeIfPresent(Bool.self, forKey: .suggestions) ?? d.suggestions
        autocorrect = try c.decodeIfPresent(Bool.self, forKey: .autocorrect) ?? d.autocorrect
        completions = try c.decodeIfPresent(Bool.self, forKey: .completions) ?? d.completions
        includeEnglish = try c.decodeIfPresent(Bool.self, forKey: .includeEnglish) ?? d.includeEnglish
        banglaDigits = try c.decodeIfPresent(Bool.self, forKey: .banglaDigits) ?? d.banglaDigits
        maxCandidates = min(max(try c.decodeIfPresent(Int.self, forKey: .maxCandidates) ?? d.maxCandidates, 2), 9)
        startInBangla = try c.decodeIfPresent(Bool.self, forKey: .startInBangla) ?? d.startInBangla
        toggleShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .toggleShortcut) ?? d.toggleShortcut
        if toggleShortcut == Shortcut.oldDefaultToggle { toggleShortcut = d.toggleShortcut }
        userAutocorrect = try c.decodeIfPresent([String: String].self, forKey: .userAutocorrect) ?? d.userAutocorrect
        // An unknown value (from a newer version) falls back to the default instead of failing.
        normalization = (try? c.decodeIfPresent(Normalization.self, forKey: .normalization)) ?? d.normalization
        learnChoices = try c.decodeIfPresent(Bool.self, forKey: .learnChoices) ?? d.learnChoices
        let size = (try? c.decodeIfPresent(Int.self, forKey: .candidateTextSize)) ?? d.candidateTextSize
        undoAutocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .undoAutocorrect)) ?? d.undoAutocorrect
        rememberModePerApp = (try? c.decodeIfPresent(Bool.self, forKey: .rememberModePerApp)) ?? d.rememberModePerApp
        loanwordSuggestions = (try? c.decodeIfPresent(Bool.self, forKey: .loanwordSuggestions)) ?? d.loanwordSuggestions
        candidateTextSize = min(max(size, EngineSettings.candidateTextSizes.lowerBound), EngineSettings.candidateTextSizes.upperBound)
    }
}
