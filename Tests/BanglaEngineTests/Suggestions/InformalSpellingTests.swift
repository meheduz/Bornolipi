import XCTest
@testable import BanglaEngine

/// Informal romanisation habits Avro reads differently (r for ড়, t for ট, chh for ছ, gy for জ্ঞ,
/// ri for ৃ): the dictionary word is offered right after the exact conversion, which Space still types.
final class InformalSpellingTests: XCTestCase {
    let s = ConventionalSpellingTests.suggester

    func testTheMeantWordFollowsTheExactConversion() {
        for (input, exact, meant) in [("bari", "বারি", "বাড়ি"), ("gari", "গারি", "গাড়ি"), ("taka", "তাকা", "টাকা"),
                                      ("chhatro", "ছহাত্র", "ছাত্র"), ("gyani", "গ্যানি", "জ্ঞানী"), ("juddho", "জুদ্ধ", "যুদ্ধ")] {
            let c = s.suggest(input).candidates
            XCTAssertEqual(c.first, exact, "\(input): Space types the Avro conversion")
            XCTAssertEqual(c.dropFirst().first, meant, input)
        }
    }

    func testTwoRewritesTogether() {
        // ri for ৃ and st for ষ্ট in one word.
        XCTAssertTrue(s.suggest("bristi").candidates.prefix(3).contains("বৃষ্টি"))
    }

    func testOnlyDictionaryWordsAndAvroNotationUnaffected() {
        XCTAssertEqual(s.informalSpellings("xqzt"), [], "a rewrite that makes no known word adds nothing")
        XCTAssertEqual(s.suggest("baRi").candidates.first, "বাড়ি", "Avro notation is unaffected")
    }

    func testTheTypedEnglishWordStaysVisible() {
        var st = EngineSettings(); st.includeEnglish = true
        for limit in [3, 5] {
            st.maxCandidates = limit
            s.settings = st
            for input in ["taka", "tren", "gari"] {
                let c = s.suggest(input).candidates
                XCTAssertTrue(c.contains(input), "\(input), limit \(limit): \(c)")
                XCTAssertLessThanOrEqual(c.count, limit)
                XCTAssertEqual(c.first, s.parser.convert(input))
            }
        }
        s.settings = EngineSettings()
    }

    func testALearnedEnglishChoiceStaysFirst() throws {
        let store = SelectionStore()
        store.record("taka", "taka")
        let learned = try Suggester(dataDirectory: TestData.dataDir, selections: store, loadDictionaryInBackground: false)
        var st = EngineSettings(); st.includeEnglish = true
        for limit in [3, 5, 8] {
            st.maxCandidates = limit
            learned.settings = st
            XCTAssertEqual(learned.suggest("taka").candidates.first, "taka", "limit \(limit): Space inserts the learned choice")
        }
    }
}
