// Avro Phonetic rule engine.
//
// The rule table (Data/AvroPhonetic.json) comes from the OpenBangla project
// (MPL-2.0). This is an independent Swift implementation of the table-driven
// longest-match algorithm used by Avro Keyboard and OpenBangla.

import Foundation

public final class AvroParser {
    private enum Scope { case punctuation, vowel, consonant, number, exact }

    private struct Match {
        let scope: Scope
        let negative: Bool
        let suffix: Bool
        let value: [Character]
    }

    private struct Rule {
        let matches: [Match]
        let replace: String
    }

    private struct Pattern {
        let replace: String
        let rules: [Rule]
    }

    private struct RawMatch: Decodable { let type: String; let scope: String; let value: String? }
    private struct RawRule: Decodable { let matches: [RawMatch]; let replace: String }
    private struct RawPattern: Decodable { let find: String; let replace: String; let rules: [RawRule]? }
    private struct RawGrammar: Decodable {
        let patterns: [RawPattern]
        let vowel: String
        let consonant: String
        let number: String
        let casesensitive: String
    }

    private var patterns: [String: Pattern] = [:]
    private var maxLen = 1
    private let vowel: Set<Character>
    private let consonant: Set<Character>
    private let number: Set<Character>
    private let caseSensitive: Set<Character>

    public init(grammarURL: URL) throws {
        let data = try Data(contentsOf: grammarURL)
        let g = try JSONDecoder().decode(RawGrammar.self, from: data)
        vowel = Set(g.vowel)
        consonant = Set(g.consonant)
        number = Set(g.number)
        caseSensitive = Set(g.casesensitive)
        for p in g.patterns {
            let rules = (p.rules ?? []).map { r -> Rule in
                let ms = r.matches.map { m -> Match in
                    var s = m.scope
                    var neg = false
                    if s.hasPrefix("!") { neg = true; s.removeFirst() }
                    let scope: Scope
                    switch s {
                    case "punctuation": scope = .punctuation
                    case "vowel": scope = .vowel
                    case "consonant": scope = .consonant
                    case "number": scope = .number
                    default: scope = .exact
                    }
                    return Match(scope: scope, negative: neg, suffix: m.type == "suffix", value: Array(m.value ?? ""))
                }
                return Rule(matches: ms, replace: r.replace)
            }
            patterns[p.find] = Pattern(replace: p.replace, rules: rules)
            maxLen = max(maxLen, p.find.count)
        }
    }

    // MARK: Character classes

    func isVowel(_ c: Character) -> Bool { vowel.contains(lower(c)) }
    func isConsonant(_ c: Character) -> Bool { consonant.contains(lower(c)) }
    func isPunctuation(_ c: Character) -> Bool { !(isVowel(c) || isConsonant(c)) }

    private func lower(_ c: Character) -> Character {
        guard c.isASCII, c.isUppercase else { return c }
        return Character(c.lowercased())
    }

    private func fix(_ input: String) -> [Character] {
        input.map { c in
            if caseSensitive.contains(lower(c)) { return c }
            return lower(c)
        }
    }

    // MARK: Conversion

    public func convert(_ input: String) -> String {
        let s = fix(input)
        let n = s.count
        var out = ""
        out.reserveCapacity(n * 3)
        var cur = 0
        while cur < n {
            var matched = false
            var len = min(maxLen, n - cur)
            while len >= 1 {
                let end = cur + len
                let chunk = String(s[cur..<end])
                if let p = patterns[chunk] {
                    var replacement = p.replace
                    for r in p.rules where ruleApplies(r, s, cur, end) {
                        replacement = r.replace
                        break
                    }
                    out += replacement
                    cur = end - 1
                    matched = true
                    break
                }
                len -= 1
            }
            if !matched { out.append(s[cur]) }
            cur += 1
        }
        return out
    }

    private func ruleApplies(_ r: Rule, _ s: [Character], _ start: Int, _ end: Int) -> Bool {
        let n = s.count
        for m in r.matches {
            let chk = m.suffix ? end : start - 1
            switch m.scope {
            case .punctuation:
                let v = (chk < 0 && !m.suffix) || (chk >= n && m.suffix)
                    || (chk >= 0 && chk < n && isPunctuation(s[chk]))
                if v == m.negative { return false }
            case .vowel, .consonant, .number:
                var v = false
                if chk >= 0 && chk < n {
                    switch m.scope {
                    case .vowel: v = isVowel(s[chk])
                    case .consonant: v = isConsonant(s[chk])
                    default: v = number.contains(s[chk])
                    }
                }
                if v == m.negative { return false }
            case .exact:
                let a: Int, b: Int
                if m.suffix { a = end; b = end + m.value.count } else { a = start - m.value.count; b = start }
                // Same boundary behaviour as the reference implementation (b < n).
                let hit = a >= 0 && b < n && Array(s[a..<b]) == m.value
                if hit == m.negative { return false }
            }
        }
        return true
    }
}
