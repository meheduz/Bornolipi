import XCTest
@testable import BanglaEngine

final class NormalizationAndUserDataTests: XCTestCase {
    static let suggester: Suggester = {
        try! Suggester(dataDirectory: TestData.dataDir, loadDictionaryInBackground: false)
    }()
    var s: Suggester { NormalizationAndUserDataTests.suggester }

    override func tearDown() {
        s.settings = EngineSettings()
        s.setUserWords([])
        s.selections.removeAll()
    }

    func scalars(_ text: String) -> Set<UInt32> { Set(text.unicodeScalars.map(\.value)) }

    func testAvroFormIsTheDefault() {
        XCTAssertEqual(EngineSettings().normalization, .avro)
        let top = s.suggest("banglay").candidates[0]
        XCTAssertEqual(top, "বাংলায়")
        XCTAssertTrue(scalars(top).contains(0x09DF), "য় as one code point, like Avro")
    }

    func testAvroFormMakesDictionaryWordsConsistent() {
        // The OpenBangla dictionary spells a few words with ঢ + nukta instead of ঢ়.
        XCTAssertEqual(Suggester.avroForm("দাঢ\u{09BC}ি"), "দা\u{09DD}ি")
        XCTAssertEqual(Suggester.avroForm("আমি"), "আমি")
        for c in s.suggest("dRhi").candidates { XCTAssertFalse(scalars(c).contains(0x09BC), c) }
    }

    func testNFCOption() {
        var st = EngineSettings(); st.normalization = .nfc
        s.settings = st
        for word in ["banglay", "baRi", "dRhi", "amar"] {
            for c in s.suggest(word).candidates {
                XCTAssertEqual(c, c.precomposedStringWithCanonicalMapping, "\(word): \(c) is not NFC")
                XCTAssertTrue(scalars(c).isDisjoint(with: [0x09DC, 0x09DD, 0x09DF]), c)
            }
        }
        XCTAssertEqual(s.suggest("banglay").candidates[0], "বাংলায\u{09BC}")
    }

    func testUnknownNormalizationFallsBackToDefault() throws {
        let json = #"{"normalization": "something-new", "banglaDigits": false}"#
        let st = try JSONDecoder().decode(EngineSettings.self, from: Data(json.utf8))
        XCTAssertEqual(st.normalization, .avro)
        XCTAssertFalse(st.banglaDigits)
    }

    func testUserWordsAreSuggested() {
        // A spelling the rules do not produce (long ূ), so it can only come from the personal dictionary.
        let mine = "মেহেদূজ"
        XCTAssertFalse(s.suggest("meheduj").candidates.contains(mine))
        s.setUserWords([mine, " ", mine])
        XCTAssertEqual(s.userWords, [mine], "trimmed, blanks and duplicates dropped")
        XCTAssertEqual(s.suggest("meheduj").candidates.first, mine)
        XCTAssertTrue(s.suggest("mehed").candidates.contains(mine), "completion")
        var st = EngineSettings(); st.suggestions = false
        s.settings = st
        XCTAssertFalse(s.suggest("meheduj").candidates.contains(mine), "suggestions off")
    }

    func testSelectionStoreEditing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bp-test-\(UUID().uuidString)/selections.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SelectionStore(url: url)
        store.record("kal", "কাল")
        store.record("mon", "মন")
        store.remove("kal")
        store.remove("missing")
        XCTAssertEqual(SelectionStore(url: url).all, ["mon": "মন"], "persisted")
        store.replaceAll(["ami": "আমি"])
        XCTAssertEqual(SelectionStore(url: url).all, ["ami": "আমি"])
        store.removeAll()
        XCTAssertEqual(SelectionStore(url: url).all, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class UserBackupTests: XCTestCase {
    func testRoundTrip() throws {
        var st = EngineSettings(); st.banglaDigits = false; st.normalization = .nfc; st.userAutocorrect = ["tmi": "tumi"]
        let b = UserBackup(settings: st, words: ["মেহেদূজ"], learned: ["kal": "কাল"])
        XCTAssertEqual(try UserBackup.decode(b.encoded()), b)
    }

    func testMissingFieldsTakeDefaults() throws {
        let b = try UserBackup.decode(Data(#"{"format": "bornolipi-backup", "words": ["ক"]}"#.utf8))
        XCTAssertEqual(b.settings, EngineSettings())
        XCTAssertEqual(b.words, ["ক"])
        XCTAssertEqual(b.learned, [:])
    }

    func testOtherFilesAreRejected() {
        XCTAssertThrowsError(try UserBackup.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try UserBackup.decode(Data(#"{"format": "something-else"}"#.utf8)))
        XCTAssertThrowsError(try UserBackup.decode(Data("not json".utf8)))
    }

    func testLearningCanBeTurnedOff() throws {
        let store = SelectionStore()
        let s = try Suggester(dataDirectory: TestData.dataDir, selections: store, loadDictionaryInBackground: false)
        var st = EngineSettings(); st.learnChoices = false
        s.settings = st
        let ses = PhoneticSession(suggester: s)
        for c in "kal" { ses.append(String(c)) }
        XCTAssertTrue(ses.select(index: 1))
        _ = ses.commit()
        XCTAssertEqual(store.all, [:], "nothing learned while learning is off")
    }
}
