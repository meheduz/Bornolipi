import XCTest
@testable import BanglaEngine

final class SuggesterTests: XCTestCase {
    static let suggester: Suggester = {
        try! Suggester(dataDirectory: TestData.dataDir, loadDictionaryInBackground: false)
    }()
    var s: Suggester { SuggesterTests.suggester }

    func testDictionarySize() {
        XCTAssertGreaterThan(s.index.count, 150_000)
    }

    func testBasicWords() {
        let cases: [(String, String)] = [
            ("ami", "আমি"), ("tumi", "তুমি"), ("bangla", "বাংলা"), ("bhalo", "ভালো"),
            ("kemon", "কেমন"), ("chele", "ছেলে"), ("dhonyobad", "ধন্যবাদ"),
            ("bidyaloy", "বিদ্যালয়"), ("biggan", "বিজ্ঞান"), ("prem", "প্রেম"), ("bondhu", "বন্ধু"),
        ]
        var bad: [String] = []
        for (roman, want) in cases {
            let got = s.suggest(roman)
            if !got.candidates.contains(want) { bad.append("\(roman): \(got.candidates) lacks \(want)") }
            else if got.candidates.first != want { bad.append("\(roman): top is \(got.candidates.first ?? "-"), want \(want) (\(got.candidates))") }
        }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    func testAlternativesOffered() {
        XCTAssertTrue(s.suggest("bhalobasha").candidates.contains("ভালোবাসা"))
    }

    func testPhoneticAlwaysPresent() {
        let g = s.suggest("zzqxkw")
        XCTAssertTrue(g.candidates.contains(s.parser.convert("zzqxkw")))
    }

    func testPunctuationWrapping() {
        let g = s.suggest("(ami),")
        XCTAssertEqual(g.candidates.first, "(আমি),")
        XCTAssertEqual(s.suggest(".").candidates, ["।"])
    }

    func testAutocorrect() {
        var st = EngineSettings()
        st.userAutocorrect["tmi"] = "tumi"
        s.settings = st
        defer { s.settings = EngineSettings() }
        XCTAssertEqual(s.suggest("tmi").candidates.first, "তুমি")
    }

    func testSuffix() {
        let g = s.suggest("bondhuder")
        XCTAssertTrue(g.candidates.contains("বন্ধুদের"), "\(g.candidates)")
    }

    func testBanglaDigitsOff() {
        var st = EngineSettings(); st.banglaDigits = false
        s.settings = st
        defer { s.settings = EngineSettings() }
        XCTAssertEqual(s.suggest("2024").candidates.first, "2024")
    }

    func testSessionFlow() {
        let ses = PhoneticSession(suggester: s)
        for c in "ami" { ses.append(String(c)) }
        XCTAssertEqual(ses.markedText, "আমি")
        XCTAssertTrue(ses.backspace())
        XCTAssertEqual(ses.buffer, "am")
        ses.append("i")
        XCTAssertEqual(ses.commit(), "আমি")
        XCTAssertFalse(ses.isComposing)
        for c in "hello" { ses.append(String(c)) }
        XCTAssertEqual(ses.takeRaw(), "hello")
    }

    func testLearning() {
        let store = SelectionStore()
        let st = try! Suggester(dataDirectory: TestData.dataDir, selections: store, loadDictionaryInBackground: false)
        let ses = PhoneticSession(suggester: st)
        for c in "kal" { ses.append(String(c)) }
        XCTAssertTrue(ses.hasChoices)
        let second = ses.suggestion.words[1]
        XCTAssertTrue(ses.select(index: 1))
        XCTAssertEqual(ses.commit(), second)
        XCTAssertEqual(st.suggest("kal").candidates.first, second)
    }

    func testShortcut() {
        let sc = Shortcut.defaultToggle
        XCTAssertTrue(sc.matches(keyCode: 11, modifiers: Shortcut.control | Shortcut.shift | 0x100))
        XCTAssertFalse(sc.matches(keyCode: 11, modifiers: Shortcut.control))
        XCTAssertEqual(sc.display, "⌃⇧B")
        // Saved settings with the old default (which macOS swallows) move to the new one.
        let old = #"{"toggleShortcut": {"keyCode": 49, "modifiers": 393216}}"#
        XCTAssertEqual(try! JSONDecoder().decode(EngineSettings.self, from: Data(old.utf8)).toggleShortcut, .defaultToggle)
        let data = try! JSONEncoder().encode(EngineSettings())
        XCTAssertEqual(try! JSONDecoder().decode(EngineSettings.self, from: data), EngineSettings())
        XCTAssertEqual(try! JSONDecoder().decode(EngineSettings.self, from: Data("{}".utf8)), EngineSettings())
    }
}

final class ConjunctVariantTests: XCTestCase {
    var s: Suggester { SuggesterTests.suggester }

    func testWithoutConjuncts() {
        XCTAssertEqual(Suggester.withoutConjuncts("আব্দার"), ["আবদার"])
        XCTAssertEqual(Suggester.withoutConjuncts("নজ্র"), ["নজর"])
        XCTAssertEqual(Suggester.withoutConjuncts("আমি"), [], "no conjunct")
        XCTAssertEqual(Suggester.withoutConjuncts("র\u{200D}্য"), [], "র + ZWJ + ্য is not a consonant cluster")
        XCTAssertEqual(Suggester.withoutConjuncts("ক্ষ্ম"), ["কষ্ম", "ক্ষম", "কষম"])
    }

    func testBrokenConjunctIsOfferedAfterTheExactConversion() {
        var st = EngineSettings(); st.autocorrect = false
        s.settings = st
        defer { s.settings = EngineSettings() }
        // "nojr" converts to নজ্র; the dictionary word নজর (gaze) is offered next, Space still types নজ্র.
        let c = s.suggest("nojr").candidates
        XCTAssertEqual(c.first, "নজ্র")
        XCTAssertEqual(c.dropFirst().first, "নজর")
        // An explicit ya-phala keeps its conversion first.
        XCTAssertEqual(s.suggest("sZan").candidates.first, "স্যান")
    }
}

/// E1: a word typed while the dictionary is still loading gets its dictionary candidates once it is ready.
final class DictionaryLoadingTests: XCTestCase {
    private func manualSuggester() throws -> Suggester {
        try Suggester(dataDirectory: TestData.dataDir, settings: EngineSettings(), selections: SelectionStore(), loading: .manual)
    }

    func testWordTypedBeforeLoadIsRefreshedWhenReady() throws {
        let s = try manualSuggester()
        let h = InputHandler(suggester: s)
        let field = RecordingClient()
        for k in Keys.parse("bhalo") { _ = h.handle(k, bangla: true, client: field) }
        XCTAssertEqual(field.marked, "ভাল", "before the dictionary loads only the rule conversion is known")
        var notified = false
        s.onDictionaryReady = { notified = h.dataBecameAvailable(field) }
        s.loadDictionary?()
        XCTAssertTrue(notified)
        XCTAssertEqual(field.marked, "ভালো", "the dictionary's spelling replaces it while the word is still being typed")
        _ = h.handle(Keys.parse("{space}")[0], bangla: true, client: field)
        XCTAssertEqual(field.text, "ভালো ")
    }

    func testRefreshKeepsACandidateTheUserChose() throws {
        let s = try manualSuggester()
        let h = InputHandler(suggester: s)
        let field = RecordingClient()
        // Autocorrect works without the dictionary, so "computer" already has two candidates.
        for k in Keys.parse("computer{down}") { _ = h.handle(k, bangla: true, client: field) }
        let chosen = field.marked
        XCTAssertEqual(chosen, "চম্পুতের", "the user moved to the rule conversion")
        s.loadDictionary?()
        XCTAssertFalse(h.dataBecameAvailable(field), "a candidate the user moved to is never replaced")
        XCTAssertEqual(field.marked, chosen)
    }

    func testRefreshAfterCommitDoesNothing() throws {
        let s = try manualSuggester()
        let h = InputHandler(suggester: s)
        let field = RecordingClient()
        for k in Keys.parse("ami{space}") { _ = h.handle(k, bangla: true, client: field) }
        s.loadDictionary?()
        XCTAssertFalse(h.dataBecameAvailable(field), "a finished word is not touched")
        XCTAssertEqual(field.text, "আমি ")
        XCTAssertEqual(field.marked, "")
    }
}

/// E5: web and e-mail addresses are offered as typed, after the Avro conversion, which Space keeps.
final class AddressTests: XCTestCase {
    func testAddressesOfferedAsTyped() {
        let s = ConventionalSpellingTests.suggester
        for input in ["www.google.com", "a@b.com", "user@example.edu", "https://github.com", "http://x.org"] {
            let c = s.suggest(input).candidates
            XCTAssertEqual(c.first, Suggester.avroForm(s.parser.convert(input)), "\(input): Space unchanged")
            XCTAssertTrue(c.contains(input), "\(input) offered as typed: \(c)")
        }
        for input in ["ami", "a.b", "@ami", "ami@", "3.14", "www"] {
            XCTAssertFalse(s.suggest(input).candidates.contains(input), "\(input) is not an address")
        }
    }
}

/// Found by adversarial testing: the suffix steps tried every split of the word, so one long word
/// (typed without spaces) cost time growing with the square of its length (61 ms per key at 1,000
/// letters). Only the final letters that can form a suffix are tried now.
final class LongInputTests: XCTestCase {
    func testCostGrowsLinearlyWithWordLength() {
        let s = ConventionalSpellingTests.suggester
        func cost(_ n: Int) -> Double {
            let w = String(repeating: "bhalobasha", count: n / 10)
            let start = DispatchTime.now()
            for _ in 0..<3 { _ = s.suggest(w) }
            return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds)
        }
        _ = cost(100)
        let ratio = cost(1000) / cost(100)
        XCTAssertLessThan(ratio, 30, "10x the length cost \(ratio)x the time")
    }

    func testLongWordStillGetsSuffixes() {
        let s = ConventionalSpellingTests.suggester
        XCTAssertTrue(s.suggest("bondhuder").candidates.contains("বন্ধুদের"))
        XCTAssertTrue(s.suggest("computerer").candidates.contains("কম্পিউটারের"))
    }
}
