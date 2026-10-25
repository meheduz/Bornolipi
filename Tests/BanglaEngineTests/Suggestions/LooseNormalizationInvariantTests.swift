import XCTest
@testable import BanglaEngine

/// Every loose code path (index keys, query keys, the curated-spelling lookup, loose and exact distances,
/// the check for a word already chosen) compares `WordIndex.looseLetters`: the text as Avro writes it
/// (ড় ঢ় য় as one code point, ো ৌ as one sign). The one exception is choosing the words 0.1.0 offered, which
/// repeats its comparison of stored code points (`LooseCompatibilityTests`). Escapes are used because
/// editors and NFC change these letters.
final class LooseNormalizationInvariantTests: XCTestCase {
    let s = ConventionalSpellingTests.suggester

    /// The text as Avro writes it, code point by code point (what `WordIndex.looseLetters` returns).
    static func letters(_ w: String) -> [UInt32] { Suggester.avroForm(Suggester.composeVowelSigns(w)).unicodeScalars.map(\.value) }

    /// The same word as letter + nukta, NFC, NFD and with ো ৌ as two signs.
    static func encodings(_ w: String) -> [String] {
        var split = String.UnicodeScalarView()
        for u in Suggester.avroForm(w).unicodeScalars {
            switch u.value {
            case 0x09DC: split.append(contentsOf: ["\u{09A1}", "\u{09BC}"])
            case 0x09DD: split.append(contentsOf: ["\u{09A2}", "\u{09BC}"])
            case 0x09DF: split.append(contentsOf: ["\u{09AF}", "\u{09BC}"])
            case 0x09CB: split.append(contentsOf: ["\u{09C7}", "\u{09BE}"])
            case 0x09CC: split.append(contentsOf: ["\u{09C7}", "\u{09D7}"])
            default: split.append(u)
            }
        }
        return [Suggester.avroForm(w), String(split), w.precomposedStringWithCanonicalMapping, w.decomposedStringWithCanonicalMapping]
    }

    func testLooseSpellingsDependOnlyOnTheWordNotItsEncoding() throws {
        // Curated spellings with nukta letters and a sample of dictionary words with ড় ঢ় য় ো ৌ.
        var words = ["পটুয়াখালী", "নোয়াখালী", "পাহাড়ি", "জায়গাটা", "দৃঢ়তা", "মোহাম্মদপুর", "কৌশল"]
        var n = 0
        try WordIndex.forEachWord(in: Data(contentsOf: TestData.dataDir.appendingPathComponent("dictionary.json"))) { w in
            guard WordIndex.isPlausibleWord(w), w.unicodeScalars.contains(where: { [0x09DC, 0x09DD, 0x09DF, 0x09CB, 0x09CC, 0x09BC].contains($0.value) }) else { return }
            n += 1
            if n % 97 == 0 { words.append(w) }
        }
        var checked = 0, differ: [String] = []
        for w in words {
            let forms = Self.encodings(w)
            guard WordIndex.looseKey(Self.letters(w)) != nil else { continue }
            checked += 1
            let expected = s.looseSpellings(forms[0], dictionary: true).map(Self.letters)
            for f in forms.dropFirst() where s.looseSpellings(f, dictionary: true).map(Self.letters) != expected {
                differ.append("\(w) as \(f.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))")
            }
            XCTAssertEqual(s.index.looseMatches(for: forms[1], limit: 3), s.index.looseMatches(for: forms[0], limit: 3), w)
        }
        XCTAssertGreaterThan(checked, 300)
        XCTAssertTrue(differ.isEmpty, "\(differ.count) encodings give other loose spellings, e.g. \(differ.prefix(3))")
    }

    func testAWordInTwoEncodingsTakesOneLooseSlot() throws {
        // The proper noun is stored with য + nukta, the dictionary word precomposed: one word, so the second
        // slot goes to the next dictionary word.
        let s = try Self.suggester(names: ["পটুয\u{09BC}াখালী"], dictionary: ["পটু\u{09DF}াখালী", "পটু\u{09DF}াখালি"])
        let loose = s.looseSpellings("পতু\u{09DF}াখালী", dictionary: true).map(Suggester.avroForm)
        XCTAssertEqual(loose, ["পটু\u{09DF}াখালী", "পটু\u{09DF}াখালি"])
    }

    func testLooseDistancesReadVowelSignsAsAvroWritesThem() {
        // যেকোন stored with ে + া (as 54 dictionary words spell ো ৌ) is the word Avro types as যেক\u{09CB}ন.
        let index = WordIndex()
        index.build(["যেকান", "যেক\u{09C7}\u{09BE}ন"])
        XCTAssertEqual(index.looseMatches(for: "যেক\u{09CB}ন", limit: 2), ["যেক\u{09C7}\u{09BE}ন", "যেকান"])
    }

    func testAWordStoredInTwoEncodingsIsOneLooseMatch() {
        // 42 dictionary words are stored in two encodings (তো, কোন, শ্রোতা: ো as one sign and as two). Swift compares
        // strings by canonical equivalence, so the expected list holds two different words.
        let index = WordIndex()
        index.build(["যেক\u{09C7}\u{09BE}ন", "যেক\u{09CB}ন", "যেকান"])
        XCTAssertEqual(index.looseMatches(for: "যেক\u{09CB}ন", limit: 2), ["যেক\u{09CB}ন", "যেকান"])
    }

    /// A suggester over a small data folder: the real grammar, these proper nouns and dictionary words.
    static func suggester(names: [String], dictionary: [String] = []) throws -> Suggester {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseNormalizationInvariantTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestData.dataDir.appendingPathComponent("AvroPhonetic.json"), to: dir.appendingPathComponent("AvroPhonetic.json"))
        let entries = names.enumerated().map { ["roman": ["name\($0.offset)"], "bangla": [$0.element]] }
        try JSONSerialization.data(withJSONObject: ["format": "bornolipi.propernouns", "entries": entries]).write(to: dir.appendingPathComponent("propernouns.json"))
        try JSONSerialization.data(withJSONObject: ["words": dictionary]).write(to: dir.appendingPathComponent("dictionary.json"))
        return try Suggester(dataDirectory: dir, selections: SelectionStore(), loadDictionaryInBackground: false)
    }
}
