import XCTest
@testable import BanglaEngine

/// Conventional spellings (Data/conventional.json): offered after the exact Avro conversion, never
/// changing what Space inserts. The raw conversion, the first candidate and the offered spelling are
/// three different things, and each is pinned separately here.
final class ConventionalSpellingTests: XCTestCase {
    static let suggester = try! Suggester(dataDirectory: TestData.dataDir, selections: SelectionStore(), loadDictionaryInBackground: false)
    var s: Suggester { Self.suggester }

    func testUniversityAcronymsKeepAvroAndOfferConventionalSpelling() {
        // input, Avro rule conversion (case-sensitive), conventional spelling
        let cases: [(String, String, String)] = [
            ("sust", "সুস্ত", "সাস্ট"), ("SUST", "শূশট", "সাস্ট"),
            ("buet", "বুএত", "বুয়েট"), ("BUET", "বূএট", "বুয়েট"),
            ("cuet", "চুএত", "চুয়েট"), ("CUET", "চূএট", "চুয়েট"),
            ("ruet", "রুএত", "রুয়েট"), ("RUET", "ড়ূএট", "রুয়েট"),
            ("kuet", "কুএত", "কুয়েট"), ("KUET", "কূএট", "কুয়েট"),
        ]
        for (input, avro, conventional) in cases {
            XCTAssertEqual(s.parser.convert(input), avro, "\(input): rule conversion")
            let c = s.suggest(input).candidates
            XCTAssertEqual(c.first, avro, "\(input): Space still inserts the Avro conversion")
            XCTAssertTrue(c.prefix(3).contains(conventional), "\(input): \(conventional) offered near the top, got \(c)")
            let ia = c.firstIndex(of: avro)!, ic = c.firstIndex(of: conventional)!
            XCTAssertLessThan(ia, ic, "\(input): offered after the exact conversion")
        }
    }

    func testShortFormsOnlyForCapitals() {
        XCTAssertTrue(s.suggest("DU").candidates.contains("ঢাবি"))
        XCTAssertFalse(s.suggest("du").candidates.contains("ঢাবি"), "lowercase du is দু, not an acronym")
        XCTAssertFalse(s.suggest("ru").candidates.contains("রাবি"))
        XCTAssertFalse(s.suggest("it").candidates.contains("আইটি"), "letter names only for input typed in capitals")
    }

    func testCapitalsAreSpelledWithLetterNames() {
        XCTAssertTrue(s.suggest("NSU").candidates.contains("এনএসইউ"))
        XCTAssertTrue(s.suggest("ICT").candidates.contains("আইসিটি"))
        XCTAssertFalse(s.suggest("Ami").candidates.contains("এএমআই"), "a capitalised word is not an acronym")
        XCTAssertEqual(s.suggest("TUMI").candidates.first, s.parser.convert("TUMI"))
    }

    func testDistrictsAndInformalSpellings() {
        for (input, want) in [("chittagong", "চট্টগ্রাম"), ("chattogram", "চট্টগ্রাম"), ("sylhet", "সিলেট"), ("coxsbazar", "কক্সবাজার"),
                              ("kmn", "কেমন"), ("vlo", "ভালো"), ("kno", "কেন"), ("donobad", "ধন্যবাদ")] {
            let c = s.suggest(input).candidates
            XCTAssertEqual(c.first, s.suggest(input).candidates.first)
            XCTAssertTrue(c.contains(want), "\(input) offers \(want): \(c)")
        }
        XCTAssertEqual(s.suggest("asi").candidates.first, "আসি", "asi is also a word (আসি): only offered, never replaced")
    }

    func testSuffixesOnAutocorrectedLoanwords() {
        for (input, want) in [("computerer", "কম্পিউটারের"), ("schoolta", "স্কুলটা"), ("mobilegulo", "মোবাইলগুলো"), ("internete", "ইন্টারনেটে")] {
            let c = s.suggest(input).candidates
            XCTAssertEqual(c.first, s.parser.convert(input), "\(input): Space unchanged")
            XCTAssertTrue(c.contains(want), "\(input) offers \(want): \(c)")
        }
    }

    func testRepeatedKeyIsNotTreatedAsAStem() {
        // E2: "rr" + suffix "ri" used to rank রররই above the exact conversion.
        XCTAssertEqual(s.suggest("rrri").candidates.first, "রররি")
        XCTAssertFalse(s.suggest("rrri").candidates.contains("রররই"))
        XCTAssertEqual(s.suggest("oke").candidates.first, "অকে", "one-letter stems are unchanged")
    }

    func testTwoCandidateLimitKeepsTheDefault() throws {
        var settings = EngineSettings()
        settings.maxCandidates = 2
        let small = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        for input in ["sust", "bhalo", "computer", "chittagong", "ami"] {
            XCTAssertEqual(small.suggest(input).candidates.first, s.suggest(input).candidates.first, "\(input): first candidate does not depend on the limit")
            XCTAssertLessThanOrEqual(small.suggest(input).candidates.count, 2)
        }
    }
}
