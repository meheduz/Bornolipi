import Foundation

/// Words Bornolipi never appends on its own (Data/suggestion-blocklist.txt): obscenities and slurs that
/// the loanword retriever or the loose matcher could otherwise offer for innocent input (chowdhu).
/// Only appended words are checked; the engine's own list, and so Space, never changes.
struct SuggestionBlocklist {
    // Compared as UTF-8 bytes: Swift's String matching compares whole characters, so the stem চুদ
    // would not be found in চুদি (দ and দি are different characters).
    private var stems: [[UInt8]] = []
    private var prefixes: [[UInt8]] = []
    private var words: Set<String> = []

    init() {}

    /// Reads the file; a missing or unreadable file blocks nothing.
    init(url: URL) {
        self.init(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    init(text: String) {
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let entry = SuggestionBlocklist.key(String(fields[1]).trimmingCharacters(in: .whitespaces))
            guard !entry.isEmpty else { continue }
            switch fields[0] {
            case "stem": stems.append(Array(entry.utf8))
            case "prefix": prefixes.append(Array(entry.utf8))
            case "word": words.insert(entry)
            default: continue
            }
        }
    }

    var isEmpty: Bool { stems.isEmpty && prefixes.isEmpty && words.isEmpty }

    func blocks(_ word: String) -> Bool {
        guard !isEmpty else { return false }
        let k = SuggestionBlocklist.key(word)
        guard !words.contains(k) else { return true }
        let b = Array(k.utf8)
        return prefixes.contains { b.starts(with: $0) } || stems.contains { SuggestionBlocklist.find($0, in: b) }
    }

    private static func find(_ stem: [UInt8], in b: [UInt8]) -> Bool {
        guard stem.count <= b.count else { return false }
        for i in 0...(b.count - stem.count) where b[i] == stem[0] && b[i..<(i + stem.count)].elementsEqual(stem) { return true }
        return false
    }

    /// The one form entries and candidates are compared in: NFC, then Avro's single code points for
    /// ড় ঢ় য় (which NFC splits), without ZWJ/ZWNJ.
    static func key(_ s: String) -> String {
        var u = String.UnicodeScalarView()
        for c in Suggester.avroForm(s.precomposedStringWithCanonicalMapping).unicodeScalars where c.value != 0x200C && c.value != 0x200D {
            u.append(c)
        }
        return String(u)
    }

    /// A retrieved word that is subtitle debris rather than a word: it has a digit (ASCII or Bangla),
    /// or it is not a dictionary word and ends in ঃ (speaker labels such as অনুবাদকঃ).
    static func isJunk(_ word: String, inDictionary: Bool) -> Bool {
        if word.unicodeScalars.contains(where: { (0x30...0x39).contains($0.value) || (0x09E6...0x09EF).contains($0.value) }) { return true }
        return !inDictionary && word.unicodeScalars.last?.value == 0x0983
    }
}
