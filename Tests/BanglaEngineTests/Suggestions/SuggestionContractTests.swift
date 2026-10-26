import XCTest
@testable import BanglaEngine

/// The contract of the integrated list: with loanword suggestions on, the list with them off is an exact
/// prefix, so Space and every engine candidate keep their places; at most three retrieved words follow, within the
/// limit, with no duplicates. Checked over varied inputs × maxCandidates 2...9 × typed English × completions (and
/// autocorrect off and NFC output at 2 and 9 candidates), with a personal word list and learned choices, on two
/// suggesters built from the same data.
final class SuggestionContractTests: XCTestCase {
    static let mine = ["টার্মিনালগুলো", "সারকারবাড়ি", "কম্পিউটারওয়ালা", "বাংকো", "অরিন"]
    static let learned = ["internet": "নেট", "bari": "বাড়ি", "ami": "আমি", "skul": "স্কুল", "kemon": "কেমন"]

    static func make(loanwords: Bool) -> Suggester {
        var settings = EngineSettings()
        settings.loanwordSuggestions = loanwords
        let s = try! Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        s.setUserWords(mine)
        for (k, v) in learned { s.selections.record(k, v) }
        return s
    }
    static let off = make(loanwords: false)
    static let on = make(loanwords: true)

    /// Informal Bangla, English loanwords, their prefixes, punctuation, Avro capitals, addresses and digits.
    static let inputs: [String] = {
        let words = ["ami", "tumi", "kemon", "acho", "bari", "taka", "sarkar", "janota", "bhalobasha", "bristi", "nojr",
                     "shotti", "kotha", "amader", "bangladesh", "dhaka", "chittagong", "sust", "abisk", "porikkha",
                     "term", "computer", "school", "skul", "internet", "mobile", "bank", "banko", "tren", "train",
                     "doctor", "hospital", "university", "office", "phone", "facebook", "video", "camera", "market",
                     "station", "police", "cricket", "football", "gif", "chowdhury", "terminal", "keyboard", "email",
                     "gari", "meyar", "aarial", "afzol", "jekono", "porer", "dhaRi"]
        var out: [String] = []
        for w in words {
            out.append(w)
            for n in stride(from: 2, to: w.count, by: 2) { out.append(String(w.prefix(n))) }
        }
        out += ["(term),", "\"ami\"", "bari.", "computer?", "(janota)", "school!", "'tren'", "taka,", "-bank-", ".5", "term...",
                "Term", "TERM", "kOmputer", "baRi", "Taka", "SUST", "amI", "shOtti", "DhaKa", "BUET",
                "name@example.com", "example.com", "www.example.com", "https://bornolipi.app", "a@b.co",
                "123", "term2", "2024", "1st", "o'term", "t", "a", "k", String(repeating: "bhalobasha", count: 5)]
        return out
    }()

    static func forEachSetting(_ body: () -> Void) {
        for max in 2...9 {
            for english in [false, true] {
                for completions in [false, true] {
                    for (autocorrect, nfc) in max == 2 || max == 9 ? [(true, false), (false, false), (true, true)] : [(true, false)] {
                        for s in [off, on] {
                            s.settings.maxCandidates = max
                            s.settings.includeEnglish = english
                            s.settings.completions = completions
                            s.settings.autocorrect = autocorrect
                            s.settings.normalization = nfc ? .nfc : .avro
                        }
                        body()
                    }
                }
            }
        }
        for s in [off, on] { s.settings.autocorrect = true; s.settings.normalization = .avro }
    }

    func testTheEngineListIsAPrefixOfTheIntegratedList() {
        let off = Self.off, on = Self.on
        XCTAssertNotNil(on.loanwordRetriever, "\(on.loanwordError.map { "\($0)" } ?? "")")
        var appended = 0
        Self.forEachSetting {
            let max = off.settings.maxCandidates
            for typed in Self.inputs {
                let a = off.suggest(typed), b = on.suggest(typed)
                let tag = "\(typed) max=\(max) english=\(off.settings.includeEnglish) completions=\(off.settings.completions) autocorrect=\(off.settings.autocorrect) nfc=\(off.settings.normalization == .nfc)"
                XCTAssertEqual(b.candidates.first, a.candidates.first, "\(tag): Space is unchanged")
                XCTAssertEqual(Array(b.candidates.prefix(a.candidates.count)), a.candidates, "\(tag): the engine list is a prefix")
                XCTAssertEqual(Array(b.words.prefix(a.words.count)), a.words, tag)
                XCTAssertLessThanOrEqual(b.words.count - a.words.count, 3, "\(tag): at most three retrieved words")
                XCTAssertLessThanOrEqual(b.words.count, max, tag)
                XCTAssertEqual(Set(b.words.map(\.precomposedStringWithCanonicalMapping)).count, b.words.count, "\(tag): no duplicates")
                XCTAssertEqual(b.exactIndex, a.exactIndex, tag)
                XCTAssertEqual(b.autocorrected, a.autocorrected, tag)
                // The typed English word is the word without its surrounding punctuation (SplitWord).
                let english = SplitWord(typed).word
                XCTAssertEqual(b.words.firstIndex(of: english), a.words.firstIndex(of: english), "\(tag): the typed English word keeps its index")
                if b.words.count > a.words.count {
                    appended += 1
                    XCTAssertEqual(b.engineCount, a.engineCount ?? a.words.count, "\(tag): engineCount marks the engine's list")
                } else {
                    XCTAssertEqual(b.engineCount, a.engineCount, tag)
                }
            }
        }
        XCTAssertGreaterThan(appended, 0, "the retriever added words somewhere")
    }

    /// ↑ on the first candidate, pressed as InputHandler presses it (only when there is a choice), leaves the session as
    /// it is with loanword suggestions off: the engine's last candidate (the typed English word when that setting is on),
    /// never an appended word; with a single engine candidate nothing changes, as in 0.1.0, where ↑ was not passed on.
    func testUpFromTheFirstCandidateIsUnchanged() {
        let a = PhoneticSession(suggester: Self.off), b = PhoneticSession(suggester: Self.on)
        var single = 0
        Self.forEachSetting {
            for typed in Self.inputs {
                a.reset(); b.reset()
                a.append(typed); b.append(typed)
                guard !a.suggestion.words.isEmpty else { continue }
                if a.suggestion.words.count == 1 && b.suggestion.words.count > 1 { single += 1 }
                for s in [a, b] where s.hasChoices { s.moveSelection(by: -1) }
                let tag = "\(typed) max=\(Self.off.settings.maxCandidates) english=\(Self.off.settings.includeEnglish)"
                XCTAssertEqual(b.markedText, a.markedText, tag)
                XCTAssertEqual(b.selected, a.selected, tag)
                XCTAssertEqual(b.defaultIsAutocorrection, a.defaultIsAutocorrection, "\(tag): Space would insert the same kind of word")
                if Self.off.settings.includeEnglish, a.suggestion.words.count > 1, typed.allSatisfy({ $0.isASCII && $0.isLowercase }) {
                    XCTAssertEqual(b.markedText, typed, "\(tag): ↑ reaches the typed English word")
                }
            }
        }
        XCTAssertGreaterThan(single, 0, "some inputs have one engine candidate and appended words")
    }
}
