import XCTest
@testable import BanglaEngine

/// The loose index and loose queries must key words from the same letters. ড় ঢ় য় (Avro's single code
/// points U+09DC, U+09DD, U+09DF) are in other consonant classes than ড ঢ য, and a few dictionary words
/// spell them as letter + nukta, so both sides are keyed from Avro's form of the word. Escapes are used
/// because editors and NFC decompose these letters.
final class LooseIndexNormalizationTests: XCTestCase {
    let s = ConventionalSpellingTests.suggester

    func testWordsWithNuktaLettersAreFoundByTheirOwnLooseKey() {
        let words = ["পাহা\u{09DC}ি", "জা\u{09DF}গাটা", "দৃ\u{09DD}তা", "সরকার"]
        let index = WordIndex()
        index.build(words)
        for w in words {
            XCTAssertEqual(index.looseMatches(for: w, limit: 5).first, w, w.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
        }
    }

    func testLetterPlusNuktaSpellingsAreFoundByAvroQueries() {
        // দৃঢ়তা stored as ঢ + nukta, as 84 dictionary words are; Avro types ঢ় as one code point.
        let index = WordIndex()
        index.build(["দৃঢ\u{09BC}তা"])
        XCTAssertEqual(index.looseMatches(for: "দৃ\u{09DD}তা", limit: 5).map(Suggester.avroForm), ["দৃ\u{09DD}তা"])
    }

    func testInformalSpellingsReachWordsWithNuktaLetters() {
        // Dakshina romanisations whose standard spelling only loose matching can find.
        for (input, want) in [("meyar", "মে\u{09DF}র"), ("biliyan", "বিলি\u{09DF}ন"), ("nipeeran", "নিপী\u{09DC}ন"), ("dayitwa", "দা\u{09DF}িত্ব")] {
            let c = s.suggest(input).candidates
            XCTAssertTrue(c.contains(want), "\(input) offers \(want): \(c)")
            XCTAssertEqual(c.first, Suggester.avroForm(s.parser.convert(input)), "\(input): Space still inserts the Avro conversion")
        }
    }

    func testEveryDictionaryWordWithALooseKeyIsFoundByItsOwnKey() throws {
        // A sample of the real dictionary (every 25th word): the index and the query agree on every key.
        var words: [String] = []
        try WordIndex.forEachWord(in: Data(contentsOf: TestData.dataDir.appendingPathComponent("dictionary.json"))) { words.append($0) }
        var checked = 0, missed: [String] = []
        for (i, w) in words.enumerated() where i % 25 == 0 && WordIndex.isPlausibleWord(w) {
            let query = Suggester.avroForm(w)
            guard WordIndex.looseKey(query.unicodeScalars.map(\.value)) != nil else { continue }
            checked += 1
            if !s.index.looseMatches(for: query, limit: 1000).map(Suggester.avroForm).contains(query) { missed.append(w) }
        }
        XCTAssertGreaterThan(checked, 5000)
        XCTAssertTrue(missed.isEmpty, "\(missed.count) of \(checked) not found, e.g. \(missed.prefix(5))")
    }
}
