import Foundation

/// Splits typed text into leading punctuation, the phonetic word, and trailing punctuation,
/// so `"ami,"` becomes `("", "ami", ",")` and the comma is converted separately.
public struct SplitWord: Equatable {
    public let preceding: String
    public let word: String
    public let trailing: String

    static let meta: Set<Character> = Set("-]~!@#%&*()_=+[{}'\";<>/?|.,।")

    public init(_ input: String) {
        let chars = Array(input)
        guard let first = chars.firstIndex(where: { !SplitWord.meta.contains($0) }) else {
            preceding = input; word = ""; trailing = ""
            return
        }
        let rest = Array(chars[first...])
        var escape = false
        var last = rest.count
        var i = rest.count - 1
        while i >= 0 {
            let c = rest[i]
            if !escape && c == "`" {
                escape = true
            } else if (escape && c == ":") || SplitWord.meta.contains(c) {
                escape = false
                last = i
            } else {
                break
            }
            i -= 1
        }
        preceding = String(chars[..<first])
        word = String(rest[..<last])
        trailing = String(rest[last...])
    }
}
