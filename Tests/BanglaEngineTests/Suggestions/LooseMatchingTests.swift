import XCTest
@testable import BanglaEngine

/// Informal English spellings the exact lookup misses: same consonants, different vowels, dental
/// for retroflex, ch for চ. Offered after the exact conversion, only for unrecognised words.
final class LooseMatchingTests: XCTestCase {
    let s = ConventionalSpellingTests.suggester

    func testInformalSpellingsOfferTheStandardWord() {
        // Words in the dictionary or the proper-noun list, typed informally, that the exact lookup misses.
        for (input, want) in [("sarkar", "সরকার"), ("mondol", "মণ্ডল"), ("bhairob", "ভৈরব"), ("akter", "আক্তার")] {
            let c = s.suggest(input).candidates
            XCTAssertTrue(c.contains(want), "\(input) offers \(want): \(c)")
            XCTAssertEqual(c.first, Suggester.avroForm(s.parser.convert(input)), "\(input): Space still inserts the Avro conversion")
        }
    }

    func testWordsTheDictionaryAlreadyMatchesAreNotLooselyExtended() {
        // janota: the exact lookup finds dictionary words (জানোটা...), so no loose guesses are added.
        let c = s.suggest("janota").candidates
        let loose = s.looseSpellings(s.parser.convert("janota"), dictionary: true)
        XCTAssertTrue(loose.allSatisfy { !c.contains($0) || s.index.matches(for: s.parser.convert("janota"), limit: 20).contains($0) }, "\(c)")
    }

    func testRecognisedWordsGainNothing() {
        // Words the exact lookup already knows keep exactly their candidates (no loose additions).
        var plain = EngineSettings()
        plain.suggestions = true
        for input in ["ami", "tumi", "kemon", "bhalo", "bangla", "kotha", "sokal", "manush"] {
            let c = s.suggest(input).candidates
            let loose = s.looseSpellings(s.parser.convert(input), dictionary: true)
            let added = loose.filter { w in c.contains(w) && !s.index.matches(for: s.parser.convert(input), limit: 20).contains(w) }
            XCTAssertTrue(added.isEmpty || s.index.matches(for: s.parser.convert(input), limit: 1).isEmpty, "\(input): \(added)")
        }
    }

    func testShortWordsAndShortKeysAreLeftAlone() {
        XCTAssertNil(WordIndex.looseKey("কম".unicodeScalars.map(\.value)), "two consonants: too ambiguous")
        XCTAssertNotNil(WordIndex.looseKey("সরকার".unicodeScalars.map(\.value)))
        XCTAssertEqual(WordIndex.looseKey("সরকার".unicodeScalars.map(\.value)), WordIndex.looseKey("সারকার".unicodeScalars.map(\.value)))
        XCTAssertEqual(WordIndex.looseKey("মণ্ডল".unicodeScalars.map(\.value)), WordIndex.looseKey("মন্দল".unicodeScalars.map(\.value)))
        XCTAssertNotEqual(WordIndex.looseKey("সরকার".unicodeScalars.map(\.value)), WordIndex.looseKey("সরকারি".unicodeScalars.map(\.value).dropLast().map { $0 } + [0x09AE]))
    }

    func testRadixSortMatchesSort() {
        var g = SystemRandomNumberGenerator()
        for n in [0, 1, 2, 1000, 70_000] {
            var a = (0..<n).map { _ in UInt64.random(in: 0...UInt64.max, using: &g) >> UInt64.random(in: 0...40, using: &g) }
            let expected = a.sorted()
            WordIndex.radixSort(&a)
            XCTAssertEqual(a, expected, "\(n) keys")
        }
    }

    func testLongWordsCompareOnTheirFirstEightClasses() {
        let key = { (s: String) in WordIndex.looseKey(s.unicodeScalars.map(\.value)) }
        XCTAssertEqual(key("কগচজটডনপবম"), key("কগচজটডনপলর"), "only the first eight classes count")
        XCTAssertNotEqual(key("কগচজটডনপ"), key("কগচজটডনব"))
    }

    func testDistantDictionaryWordsAreNotOffered() {
        // Same consonant classes, but too many other letters differ: পিসবোর্ড, বারাসাত, ওষধিনাথ.
        for (input, unrelated) in [("password", "পিসবোর্ড"), ("bristi", "বারাসাত"), ("shadhinota", "ওষধিনাথ")] {
            XCTAssertFalse(s.suggest(input).candidates.contains(unrelated), input)
            XCTAssertTrue(s.looseSpellings(s.parser.convert(input), dictionary: true).isEmpty, input)
        }
    }

    func testASecondDictionaryWordOnlyWhenAsClose() {
        // ডাক্তার is one class-equal letter away; ডাক্তারি and ত্রিন are further and not offered by loose matching.
        XCTAssertEqual(s.looseSpellings(s.parser.convert("daktar"), dictionary: true), ["ডাক্তার"])
        XCTAssertEqual(s.looseSpellings(s.parser.convert("tren"), dictionary: true), ["ট্রেন"])
        XCTAssertEqual(Array(s.suggest("tren").candidates.prefix(2)), ["ত্রেন", "ট্রেন"], "Space still types the conversion")
    }

    func testLongerFormsOfTheConversionAreNotLooseMatches() {
        // খারাপি starts with the conversion খারাপ: a completion (offered as one), not a correction.
        XCTAssertFalse(s.looseSpellings(s.parser.convert("kharap"), dictionary: true).contains("খারাপি"))
        XCTAssertFalse(s.looseSpellings(s.parser.convert("namaj"), dictionary: true).contains("নামাজি"))
    }

    func testLooseDistanceIgnoresSameClassLetters() {
        let sc = { (s: String) in s.unicodeScalars.map(\.value) }
        XCTAssertEqual(WordIndex.looseDistance(sc("মন্দল"), sc("মণ্ডল")), 0)
        XCTAssertEqual(WordIndex.looseDistance(sc("তেবিল"), sc("টেবিল")), 0)
        XCTAssertEqual(WordIndex.looseDistance(sc("তেবিল"), sc("তাবিল")), 1, "a vowel difference still counts")
    }
}
