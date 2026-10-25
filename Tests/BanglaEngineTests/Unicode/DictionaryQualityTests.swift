import XCTest
@testable import BanglaEngine

/// E9: dictionary data quality and one encoding for every committed word.
final class DictionaryQualityTests: XCTestCase {
    func testEntriesStartingWithASignAreSkipped() {
        XCTAssertFalse(WordIndex.isPlausibleWord("ি"))
        XCTAssertFalse(WordIndex.isPlausibleWord("\u{09CD}ক"))
        XCTAssertTrue(WordIndex.isPlausibleWord("কি"))
        XCTAssertTrue(WordIndex.isPlausibleWord("উল্লাহ্\u{200C}"))
    }

    /// The output form never changes what the rule engine itself writes.
    func testOutputFormMatchesTheRuleEngine() {
        var g = StateMachineTests.Seeded(state: 5)
        let p = TestData.parser
        for _ in 0..<20_000 {
            let w = String((0..<Int.random(in: 1...10, using: &g)).map { _ in StateMachineTests.letters[Int.random(in: 0..<StateMachineTests.letters.count, using: &g)] })
            let raw = p.convert(w)
            let out = Suggester.avroForm(raw.precomposedStringWithCanonicalMapping)
            XCTAssertTrue(out.unicodeScalars.elementsEqual(Suggester.avroForm(raw).unicodeScalars), "\(w): \(raw.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }

    func testComposeVowelSignsMatchesNFC() {
        for w in ["তো", "ত\u{09C7}\u{09BE}", "য\u{09C7}\u{09D7}থ", "ভাল", "বাড়ি", "ক\u{09C7}\u{09BE}ন\u{09C7}\u{09BE}"] {
            XCTAssertTrue(Suggester.avroForm(Suggester.composeVowelSigns(w)).unicodeScalars.elementsEqual(
                Suggester.avroForm(w.precomposedStringWithCanonicalMapping).unicodeScalars), w)
        }
    }

    /// Words stored in two encodings (ো as one code point or as ে + া) are committed identically.
    func testCanonicalDuplicatesCommitOneEncoding() {
        let s = ConventionalSpellingTests.suggester
        for input in ["bhalo", "shona", "alochona", "koTi", "srota", "prokoushol"] {
            for c in s.suggest(input).candidates {
                XCTAssertTrue(c.unicodeScalars.elementsEqual(Suggester.avroForm(c.precomposedStringWithCanonicalMapping).unicodeScalars),
                              "\(input): \(c) is not in the composed Avro form")
            }
        }
    }
}
