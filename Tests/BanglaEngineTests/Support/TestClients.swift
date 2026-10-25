import XCTest
@testable import BanglaEngine

/// Records what the input method sends to the host app, like a text field would show it.
final class RecordingClient: TextClient {
    var text = ""
    var marked = ""
    var calls: [String] = []
    func insert(_ t: String) { text += t; marked = ""; calls.append("insert(\(t))") }
    func setMarked(_ t: String) { marked = t; calls.append("mark(\(t))") }
    /// Caret at the end of `text`, like a field where the user only types.
    func textBeforeCaret(utf16Length: Int) -> String? {
        let u = Array(text.utf16)
        guard utf16Length <= u.count else { return nil }
        return String(decoding: u.suffix(utf16Length), as: UTF16.self)
    }
    func remark(utf16Length: Int, as m: String) -> Bool {
        let u = Array(text.utf16)
        guard utf16Length <= u.count else { return false }
        text = String(decoding: u.dropLast(utf16Length), as: UTF16.self)
        marked = m
        calls.append("remark(\(utf16Length), \(m))")
        return true
    }
}

/// An app that cannot report text around the caret (some terminals and custom views).
final class OpaqueClient: TextClient {
    var text = "", marked = ""
    func insert(_ t: String) { text += t; marked = "" }
    func setMarked(_ t: String) { marked = t }
}

/// Builds key presses the way a US keyboard produces them. `{name}` and `{mod+name}` give special keys.
enum Keys {
    static let codes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50, " ": 49,
    ]
    static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]
    static let named: [String: (UInt16, String)] = [
        "space": (49, " "), "return": (36, "\r"), "enter": (76, "\u{3}"), "tab": (48, "\t"), "esc": (53, "\u{1b}"),
        "bs": (51, "\u{7f}"), "fwd": (117, "\u{F728}"), "up": (126, "\u{F700}"), "down": (125, "\u{F701}"),
        "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "home": (115, "\u{F729}"), "f5": (96, "\u{F708}"),
    ]

    static func parse(_ script: String, capsLock: Bool = false) -> [KeyPress] {
        var out: [KeyPress] = []
        var i = script.startIndex
        while i < script.endIndex {
            if script[i] == "{", let close = script[i...].firstIndex(of: "}") {
                var parts = script[script.index(after: i)..<close].split(separator: "+").map(String.init)
                let name = parts.removeLast()
                var mods: UInt = 0
                for p in parts {
                    switch p {
                    case "ctrl": mods |= Shortcut.control
                    case "shift": mods |= Shortcut.shift
                    case "opt": mods |= Shortcut.option
                    case "cmd": mods |= Shortcut.command
                    default: fatalError("modifier \(p)")
                    }
                }
                if let key = named[name] {
                    out.append(KeyPress(keyCode: key.0, characters: key.1, modifiers: mods))
                } else if let c = name.first, name.count == 1, let code = codes[c] {
                    out.append(KeyPress(keyCode: code, characters: name, modifiers: mods))
                } else {
                    fatalError("key \(name)")
                }
                i = script.index(after: close)
                continue
            }
            out.append(press(script[i], capsLock: capsLock))
            i = script.index(after: i)
        }
        return out
    }

    static func press(_ c: Character, capsLock: Bool = false) -> KeyPress {
        let caps: UInt = capsLock ? KeyPress.capsLock : 0
        if let code = codes[c] {
            let chars = capsLock && c.isLetter ? c.uppercased() : String(c)
            return KeyPress(keyCode: code, characters: chars, modifiers: caps)
        }
        if c.isUppercase, let code = codes[Character(c.lowercased())] {
            return KeyPress(keyCode: code, characters: String(c), modifiers: Shortcut.shift | caps)
        }
        if let base = shifted[c], let code = codes[base] {
            return KeyPress(keyCode: code, characters: String(c), modifiers: Shortcut.shift)
        }
        // Something a non-US layout produced; the key code does not matter.
        return KeyPress(keyCode: 10, characters: String(c), modifiers: 0)
    }
}
