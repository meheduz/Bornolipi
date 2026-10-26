import XCTest
@testable import BanglaEngine

/// The experimental loanword retriever (`EngineSettings.loanwordSuggestions`, off by default): known
/// words for informal and English spellings, offered after the engine's own candidates. Its results
/// equal the lab prototype's on 31,258 inputs (`swift run -c release loanword-parity`); these tests
/// cover the engine side.
final class LoanwordRetrieverTests: XCTestCase {
    static let on: Suggester = {
        var settings = EngineSettings()
        settings.loanwordSuggestions = true
        return try! Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
    }()
    let on = LoanwordRetrieverTests.on
    let off = ConventionalSpellingTests.suggester

    func testOffByDefaultAndOlderSettingsStayOff() throws {
        XCTAssertFalse(EngineSettings().loanwordSuggestions)
        XCTAssertFalse(try JSONDecoder().decode(EngineSettings.self, from: Data(#"{"suggestions":true}"#.utf8)).loanwordSuggestions)
        var s = EngineSettings()
        s.loanwordSuggestions = true
        XCTAssertTrue(try JSONDecoder().decode(EngineSettings.self, from: JSONEncoder().encode(s)).loanwordSuggestions)
        XCTAssertNil(off.loanwordRetriever, "nothing is loaded while the setting is off")
    }

    func testRetrieverFindsLoanwords() throws {
        let r = try XCTUnwrap(on.loanwordRetriever, "\(on.loanwordError.map { "\($0)" } ?? "")")
        for (typed, want) in [("term", "টার্ম"), ("computer", "কম্পিউটার"), ("school", "স্কুল"), ("internet", "ইন্টারনেট"), ("mobile", "মোবাইল")] {
            XCTAssertEqual(r.generate(typed).first?.word, want, typed)
        }
        XCTAssertEqual(r.generate("aeiou"), [], "no consonant, no key")
    }

    /// The engine's own list never changes: every candidate keeps its place, and at most three retrieved
    /// words follow its last candidate, within the limit. One-letter input gets nothing new.
    func testTheEngineListIsUntouchedAndWordsFollowIt() {
        for typed in ["term", "computer", "school", "bank", "sarkar", "bari", "ami", "kemon", "taka", "tren", "nojr", "sust", "janota", "abisk", "gif", "t", "te", "ter"] {
            let a = off.suggest(typed), b = on.suggest(typed)
            XCTAssertEqual(Array(b.candidates.prefix(a.candidates.count)), a.candidates, "\(typed): engine list unchanged")
            XCTAssertEqual(b.exactIndex, a.exactIndex, typed)
            XCTAssertEqual(b.autocorrected, a.autocorrected, typed)
            XCTAssertLessThanOrEqual(b.words.count - a.words.count, 3, typed)
            XCTAssertLessThanOrEqual(b.words.count, on.settings.maxCandidates, typed)
            XCTAssertEqual(Set(b.words).count, b.words.count, "\(typed): no duplicates")
        }
        XCTAssertEqual(on.suggest("t").candidates, off.suggest("t").candidates, "one letter: nothing new")
        XCTAssertTrue(on.suggest("term").candidates.prefix(3).contains("টার্ম"))
        XCTAssertFalse(off.suggest("term").candidates.contains("টার্ম"))
    }

    /// Retrieved words may follow a word the dictionary already recognises. The loose generator
    /// still adds nothing for janota (`LooseMatchingTests`, with the setting off); the engine's list is unchanged.
    func testARecognisedWordMayGainWordsAfterTheEngineList() {
        let a = off.suggest("janota"), b = on.suggest("janota")
        XCTAssertGreaterThan(a.words.count, 1, "the dictionary recognises janota: \(a.words)")
        XCTAssertEqual(Array(b.words.prefix(a.words.count)), a.words, "every engine candidate keeps its place")
        XCTAssertEqual(b.candidates.first, a.candidates.first, "Space is unchanged")
        XCTAssertLessThanOrEqual(b.words.count - a.words.count, 3)
        XCTAssertEqual(Set(b.words.map(\.precomposedStringWithCanonicalMapping)).count, b.words.count)
        XCTAssertTrue(b.words.dropFirst(a.words.count).contains("জনতা"), "the meant word follows the engine's list: \(b.words)")
        XCTAssertEqual(b.engineCount, a.engineCount ?? a.words.count)
    }

    /// The personal dictionary and the typed-English option keep their places.
    func testPersonalWordsAndTypedEnglishKeepTheirPlaces() throws {
        var settings = EngineSettings()
        settings.includeEnglish = true
        let plain = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        settings.loanwordSuggestions = true
        let with = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        let mine = ["টার্মিনালগুলো", "সারকারবাড়ি", "কম্পিউটারওয়ালা", "বাংকো"]
        plain.setUserWords(mine); with.setUserWords(mine)
        for typed in ["term", "termi", "sarkar", "computer", "bank", "banko", "bari", "pro", "sh"] {
            let a = plain.suggest(typed).candidates, b = with.suggest(typed).candidates
            XCTAssertEqual(Array(b.prefix(a.count)), a, "\(typed): personal words and typed English keep their places")
        }
    }

    func testOnlyLowercaseLettersAreLookedUp() {
        // Capitals are Avro's precision marks, and digits or punctuation inside the word are not informal spelling.
        for typed in ["Term", "TERM", "term2", "o'term", "kOmputer"] {
            XCTAssertEqual(on.suggest(typed).candidates, off.suggest(typed).candidates, typed)
        }
        // Very long words are left alone (the retriever's cost grows faster than their length).
        let long = String(repeating: "bhalobasha", count: 5)
        XCTAssertEqual(on.suggest(long).candidates, off.suggest(long).candidates)
        // Punctuation around the word is not part of it.
        XCTAssertEqual(on.suggest("(term),").candidates.first, off.suggest("(term),").candidates.first)
        XCTAssertTrue(on.suggest("(term),").candidates.contains("(টার্ম),"))
    }

    func testLearnedChoicesAndAutocorrectKeepPriority() throws {
        // A private suggester: the shared one stays as other test classes expect it.
        var settings = EngineSettings()
        settings.loanwordSuggestions = true
        settings.userAutocorrect["kompiutar"] = "kompiuTar"
        let s = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        s.selections.record("internet", "নেট")
        XCTAssertEqual(s.suggest("internet").candidates.first, "নেট")
        XCTAssertTrue(s.suggest("internet").candidates.contains("ইন্টারনেট"))
        XCTAssertEqual(s.suggest("kompiutar").candidates.first, s.parser.convert("kompiuTar"))
    }

    /// With two candidates, completions off and a learned choice equal to the exact conversion, the
    /// engine's own truncation cuts its autocorrection. A retrieved word equal to that correction is not
    /// appended, where it would be marked as the autocorrection.
    func testATruncatedAutocorrectionIsNotBroughtBack() throws {
        var settings = EngineSettings()
        settings.maxCandidates = 2
        settings.completions = false
        settings.userAutocorrect = ["term": "Tarrm"]   // টার্ম (Avro writes the reph for "rr")
        let corrected = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        let correction = try XCTUnwrap(corrected.suggest("term").words.first)
        XCTAssertEqual(correction, "টার্ম", "the autocorrection comes first without a learned choice")
        let s0 = corrected.suggest("term")
        let exact = s0.words[try XCTUnwrap(s0.exactIndex)]

        let plain = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        settings.loanwordSuggestions = true
        let with = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        plain.selections.record("term", exact)
        with.selections.record("term", exact)
        XCTAssertEqual(with.loanwordRetriever?.generate("term").first?.word, correction, "the retriever would bring the correction back")

        let a = plain.suggest("term"), b = with.suggest("term")
        XCTAssertEqual(a.words, [exact], "the engine's truncation cut the correction")
        XCTAssertNil(a.autocorrected)
        XCTAssertEqual(Array(b.words.prefix(a.words.count)), a.words)
        XCTAssertFalse(b.words.contains(correction))
        XCTAssertNil(b.autocorrected, "no retrieved word is marked as the autocorrection")
        XCTAssertEqual(b.exactIndex, a.exactIndex)
    }

    func testTurningTheSettingOnLaterBuildsTheRetriever() throws {
        let s = try Suggester(dataDirectory: TestData.dataDir, settings: EngineSettings(), selections: SelectionStore(), loading: .manual)
        s.settings.loanwordSuggestions = true   // before the dictionary has loaded
        XCTAssertNil(s.loanwordRetriever)
        s.loadDictionary?()
        XCTAssertNotNil(s.loanwordRetriever)
        XCTAssertTrue(s.suggest("term").candidates.contains("টার্ম"))
    }

    /// The lexicon file keys its counts by word, so another dictionary still gets a retriever (see
    /// LoanwordLexiconTests for edited dictionaries).
    func testLexiconForAnotherDictionaryStillLoads() throws {
        let index = WordIndex()
        index.build(["আমি", "তুমি"])
        let r = try LoanwordRetriever(dataDirectory: TestData.dataDir, dictionary: index)
        let lexicon = try String(contentsOf: TestData.dataDir.appendingPathComponent("loanword-lexicon.tsv"), encoding: .utf8)
        let lines = lexicon.split(separator: "\n")
        XCTAssertEqual(r.count, 2 + lines.filter { $0.hasPrefix("+\t") }.count, "the two words, then the added words")
        XCTAssertEqual(r.staleCounts, lines.filter { $0.hasPrefix("=\t") }.count - 2, "only the counts of আমি and তুমি are used")
        XCTAssertTrue(r.generate("mobile").map(\.word).contains("মোবাইলে"), "an added word")
    }

    func testSumsLikePython() {
        // Python 3.12+ sum() compensates rounding (Neumaier); the prototype's scores depend on it.
        let xs = [Double](repeating: 0.1, count: 10)
        XCTAssertEqual(LoanwordRetriever.pythonSum(xs), 1.0)
        XCTAssertNotEqual(xs.reduce(0, +), 1.0)
    }

    func testShapesFollowThePrototype() {
        // bnshape.shape: classes, vowel material, consonant letters; glides are vowel material.
        func shape(_ w: String) -> String {
            var b = BanglaShape.Builder()
            var n: [UInt32] = []
            BanglaShape.normalize(w.unicodeScalars.map(\.value), into: &n)
            _ = BanglaShape.shape(n, into: &b)
            return b.classes.map(String.init).joined(separator: ",") + "|" + b.segments.map(BanglaShape.segmentString).joined(separator: ",")
        }
        XCTAssertEqual(shape("টার্ম"), "7,13,12|,a,,0")
        XCTAssertEqual(shape("ব্যাংক"), "11,3,1|,ya,,0")
        XCTAssertEqual(shape("বৃষ্টি"), "11,13,15,7|,,i,,i")
        XCTAssertEqual(shape("সূর্য"), "15,13,5|,u,,0")
    }
}
