import XCTest
@testable import BanglaEngine

/// Words 0.1.0 offered as loose matches are offered the same way; words its index could not reach (ড় ঢ় য়
/// keyed by their Avro form) only fill free slots, after every other candidate.
final class LooseCompatibilityTests: XCTestCase {
    func testWhat010OfferedIsKept() throws {
        // কারবেন: কাড়বেন is closer (ড় shares র's class) but 0.1.0 could not reach it; it offered করবেন and কারবন.
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: ["কা\u{09DC}বেন", "করবেন", "কারবন"])
        let loose = s.looseCandidates("কারবেন", dictionary: true, shown: [])
        XCTAssertEqual(loose.kept, ["করবেন", "কারবন"])
        XCTAssertEqual(loose.added, [])
    }

    func testANewlyReachableWordFillsAFreeSlot() throws {
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: ["কা\u{09DC}বেন", "করবেন"])
        let loose = s.looseCandidates("কারবেন", dictionary: true, shown: [])
        XCTAssertEqual(loose.kept, ["করবেন"])
        XCTAssertEqual(loose.added, ["কা\u{09DC}বেন"])
        XCTAssertEqual(s.looseCandidates("কারবেন", dictionary: true, shown: ["কা\u{09DC}বেন"]).added, [], "already shown by another step")
    }

    func testAddedWordsGoAfterEveryOtherCandidate() throws {
        // meyar: মেয়ারকা is a completion of the conversion, মেয়র a loose word 0.1.0 could not reach.
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: ["মে\u{09DF}র", "মে\u{09DF}ারকা"])
        XCTAssertEqual(s.suggest("meyar").candidates, ["মে\u{09DF}ার", "মে\u{09DF}ারকা", "মে\u{09DF}র"])
    }

    func testAddedWordsGoAfterTheTypedEnglishWord() throws {
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: ["মে\u{09DF}র", "মে\u{09DF}ারকা"])
        var st = EngineSettings(); st.includeEnglish = true
        s.settings = st
        XCTAssertEqual(s.suggest("meyar").candidates, ["মে\u{09DF}ার", "মে\u{09DF}ারকা", "meyar", "মে\u{09DF}র"])
        st.maxCandidates = 3
        s.settings = st
        XCTAssertEqual(s.suggest("meyar").candidates, ["মে\u{09DF}ার", "মে\u{09DF}ারকা", "meyar"], "no free slot is left")
    }

    func testAWordStoredWithTwoVowelSignsGoesAfterCompletions() throws {
        // onurodh: অনুরোধ is stored with ে + া, as 54 dictionary words spell ো ৌ. 0.1.0 compared those code
        // points, two edits from অনুরধ, too far, and offered the completion alone. The word now follows it.
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: ["অনুর\u{09C7}\u{09BE}ধ", "অনুরধক"])
        XCTAssertEqual(s.suggest("onurodh").candidates, ["অনুরধ", "অনুরধক", "অনুর\u{09CB}ধ"])
        XCTAssertEqual(s.looseCandidates("অনুরধ", dictionary: true, shown: []).kept, [])
    }

    func testProperNounsKeepThe010Order() throws {
        // পাহাড়ি stored as ড + nukta is the typed word itself, but 0.1.0 compared code points (two edits),
        // so পাহারি (one edit) came first, and stays first.
        let s = try LooseNormalizationInvariantTests.suggester(names: ["পাহা\u{09A1}\u{09BC}ি", "পাহারি"])
        let loose = s.looseCandidates("পাহা\u{09DC}ি", dictionary: false, shown: [])
        XCTAssertEqual(loose.kept.map(Suggester.avroForm), ["পাহারি", "পাহা\u{09DC}ি"])
        XCTAssertEqual(loose.added, [])
    }

    func testANameCloserAsAvroWritesItFollows() throws {
        // As stored, পাহাড়ী (ড + nukta) is three edits from পাহাড়ি and 0.1.0 offered the two others; as Avro
        // writes it, it is one edit away, so it is added after them.
        let s = try LooseNormalizationInvariantTests.suggester(names: ["পাহারি", "পাহারা", "পাহা\u{09A1}\u{09BC}ী"])
        let loose = s.looseCandidates("পাহা\u{09DC}ি", dictionary: false, shown: [])
        XCTAssertEqual(loose.kept, ["পাহারি", "পাহারা"])
        XCTAssertEqual(loose.added.map(Suggester.avroForm), ["পাহা\u{09DC}ী"])
    }

    func testAvroWritesInformalInputTheWayLooseLettersCompare() throws {
        // `looseWords010` compares 0.1.0's stored code points with the query as Avro writes it. That is the
        // query 0.1.0 compared only while Avro writes no nukta and no ো ৌ as two signs for the lowercase
        // a-z words the loose step takes (a backtick can make ে + া, as in kea`, but never reaches it).
        let s = try LooseNormalizationInvariantTests.suggester(names: [])
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var words: [String] = []
        func spell(_ prefix: String, _ n: Int) {
            guard n > 0 else { words.append(prefix); return }
            for c in letters { spell(prefix + String(c), n - 1) }
        }
        for n in 1...3 { spell("", n) }
        var seed: UInt64 = 20_261_025
        for _ in 0..<20_000 {
            var w = ""
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for _ in 0..<(4 + Int(seed >> 60) % 9) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                w.append(letters[Int(seed >> 33) % 26])
            }
            words.append(w)
        }
        let written = words.filter { WordIndex.needsLooseNormalization(s.parser.convert($0).unicodeScalars.map(\.value)) }
        XCTAssertEqual(written, [], "Avro wrote a nukta or ো ৌ as two signs")
        XCTAssertTrue(WordIndex.needsLooseNormalization(s.parser.convert("kea`").unicodeScalars.map(\.value)), "the check sees it")
    }

    func testDTypedForRraStillReachesTheWord() {
        // 0.1.0 keyed পাহাড়ি by its skeleton (ড), so pahadi found it; the Avro key (ড় with র) serves pahari.
        let index = WordIndex()
        index.build(["পাহা\u{09DC}ি", "ক্রী\u{09DC}া"])
        XCTAssertEqual(index.looseMatches(for: "পাহাদি", limit: 2), ["পাহা\u{09DC}ি"])
        XCTAssertEqual(index.looseMatches(for: "পাহারি", limit: 2), ["পাহা\u{09DC}ি"])
        XCTAssertEqual(index.looseMatches(for: "ক্রিদা", limit: 2), ["ক্রী\u{09DC}া"], "র and ড় merge: only the skeleton key has three classes")
        XCTAssertEqual(index.looseHits(for: "পাহাদি").map(\.compatible), [true])
        XCTAssertEqual(index.looseHits(for: "পাহারি").map(\.compatible), [false])
    }
}
