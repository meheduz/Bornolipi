import XCTest
@testable import BanglaEngine

/// Candidate safety for appended words (Data/suggestion-blocklist.txt): the loanword retriever and the
/// loose matcher never append an obscenity for innocent input, while the engine's own list, and what a
/// user who types such a word deliberately gets, stays exactly as 0.1.0 had it.
final class SuggestionSafetyTests: XCTestCase {
    static let blocklist = SuggestionBlocklist(url: TestData.dataDir.appendingPathComponent("suggestion-blocklist.txt"))
    let blocklist = SuggestionSafetyTests.blocklist
    let on = LoanwordRetrieverTests.on
    let off = ConventionalSpellingTests.suggester

    /// The words after the engine's list (`Suggestion.engineCount`).
    func appended(_ s: Suggestion) -> [String] { s.engineCount.map { Array(s.words[$0...]) } ?? [] }

    func testTheMatcherReadsStemsPrefixesAndWholeWords() {
        XCTAssertFalse(blocklist.isEmpty)
        for w in ["চোদা", "চোদার", "মাদারচোদের", "চুদ", "চুদি", "খানকিখোর", "মাগী", "মাগি", "মাগিটাকে", "বেশ্যাকে", "হারামি", "হারামির", "হারামজাদা", "ভোদা",
                  "চুতিয়া", "চুতমারানি", "বাঞ্চোতগুলা", "চুত", "গুদ", "ধোন", "ধোনের", "পোঁদের", "পোঁদপাকা", "কুত্তারবাচ্চা"] {
            XCTAssertTrue(blocklist.blocks(w), w)
        }
        // Ordinary words that share letters with an entry.
        for w in ["চোদ্দ", "গুদাম", "উঁচুদের", "নিচুদর", "চাচ্চুদের", "নিমকহারামি", "মাগিতে", "মাগিবি", "দেমাগি", "ভোদাই", "বালক", "আমি", "চুড়ি",
                  "ধোনি", "ধোনে", "ধোনা", "ধোনকার", "চুতো", "কুত্তা"] {
            XCTAssertFalse(blocklist.blocks(w), w)
        }
    }

    func testMatchingIgnoresTheUnicodeForm() {
        let list = SuggestionBlocklist(text: "stem\tবাঁড়া\nword\tয়ো\n# comment\nprefix\tচ\u{09C7}\u{09BE}")
        XCTAssertTrue(list.blocks("বাঁড\u{09BC}া"), "decomposed ড়")
        XCTAssertTrue(list.blocks("বাঁ\u{09DC}া"), "precomposed ড়")
        XCTAssertTrue(list.blocks("য\u{09BC}ো"))
        XCTAssertTrue(list.blocks("চো"), "an entry with ে + া matches ো")
        XCTAssertTrue(list.blocks("চে\u{09BE}খ"))
        XCTAssertTrue(list.blocks("বাঁ\u{200C}ড়া"), "ZWNJ is ignored")
        XCTAssertFalse(SuggestionBlocklist(url: URL(fileURLWithPath: "/nonexistent")).blocks("চোদা"), "a missing file blocks nothing")
    }

    func testRetrievedJunkIsSkipped() {
        XCTAssertTrue(SuggestionBlocklist.isJunk("পি৯৯", inDictionary: false))
        XCTAssertTrue(SuggestionBlocklist.isJunk("q1", inDictionary: true))
        XCTAssertTrue(SuggestionBlocklist.isJunk("অনুবাদকঃ", inDictionary: false))
        XCTAssertFalse(SuggestionBlocklist.isJunk("দুঃ", inDictionary: true), "a dictionary word ending in ঃ stays")
        XCTAssertFalse(SuggestionBlocklist.isJunk("দুঃখ", inDictionary: false))
    }

    /// Every prefix of innocent input that surfaced obscenities in the research: nothing blocked is
    /// appended, and the engine's list is the list with the setting off.
    func testTheOffensiveWordProbeReportsZero() {
        let inputs = ["chowdhu", "choudhu", "chowdhury", "chowdhur", "chudi", "chanokyer", "bhashakeo", "megaby", "baisaike",
                      "chuada", "chodna", "magik", "beshi", "harami", "khanki", "bokachoda", "madarchod", "randi", "chhinal"]
        for input in inputs {
            for n in 1...input.count {
                let typed = String(input.prefix(n))
                let a = off.suggest(typed), b = on.suggest(typed)
                for w in appended(b) + appended(a) { XCTAssertFalse(blocklist.blocks(w), "\(typed): \(w)") }
                for w in appended(b) { XCTAssertFalse(w.contains { $0.isNumber }, "\(typed): \(w)") }
                let engine = a.engineCount ?? a.words.count
                XCTAssertEqual(Array(b.words.prefix(engine)), Array(a.words.prefix(engine)), "\(typed): engine list unchanged")
                XCTAssertEqual(b.engineCount ?? b.words.count, engine, typed)
            }
        }
    }

    /// A word typed deliberately keeps exactly what the engine offers: only appended words are filtered.
    func testADeliberatelyTypedWordKeepsTheEngineCandidates() {
        // 0.1.0's lists (672bda0, default settings): the engine part must stay exactly these, setting on or off.
        let expected: [String: [String]] = [
            "choda": ["ছদা", "ছড়া", "চড়া"],
            "chod": ["ছদ", "ছড়", "চড়", "ছদি", "ছদকা", "ছদিন"],
            "chudi": ["ছুদি", "ছুড়ি", "চুড়ি"],
            "khanki": ["খানকি", "খাঙ্কি"],
            "magi": ["মাগি", "মাগী", "মাগই", "মাগোই", "মাগিত", "মাগিব", "মাগিল"],
            "magee": ["মাগী", "মাগি", "মাগেয়ে", "মাগিত", "মাগিব", "মাগিল"],
            "beshya": ["বেশ্যা", "বেশ্যালয়", "বেশ্যাগমন", "বেশ্যাগিরি"],
            "harami": ["হারামি", "হারামই"],
            "haramjada": ["হারামজাদা", "হারামজাদাগিরি"],
            "bhoda": ["ভোদা", "ভোঁদা", "ভদা", "ভোঁদাই", "ভোঁদাভুঁদো"],
            "chhinal": ["ছহিনাল", "ছিনাল"],
        ]
        for (typed, list) in expected {
            for s in [off, on] { XCTAssertEqual(Array(s.suggest(typed).words.prefix(list.count)), list, "\(typed): 0.1.0's list") }
        }
        for typed in ["choda", "chod", "chudi", "khanki", "magi", "magee", "beshya", "harami", "haramjada", "bhoda", "chhinal"] {
            let a = off.suggest(typed), b = on.suggest(typed)
            let engine = a.engineCount ?? a.words.count
            XCTAssertEqual(Array(b.words.prefix(engine)), Array(a.words.prefix(engine)), typed)
            XCTAssertEqual(b.words.first, a.words.first, "\(typed): Space unchanged")
        }
        XCTAssertTrue(blocklist.blocks(off.suggest("khanki").words[0]), "the exact conversion is offered even when blocked")
    }
}
