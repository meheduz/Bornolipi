import XCTest
@testable import BanglaEngine

final class InputHandlerTests: XCTestCase {
    static let suggester: Suggester = {
        try! Suggester(dataDirectory: TestData.dataDir, loadDictionaryInBackground: false)
    }()
    var suggester: Suggester { InputHandlerTests.suggester }

    var handler: InputHandler!
    var client: RecordingClient!

    override func setUp() {
        suggester.settings = EngineSettings()
        suggester.selections.removeAll()
        handler = InputHandler(suggester: suggester)
        client = RecordingClient()
    }

    override func tearDown() { suggester.settings = EngineSettings() }

    @discardableResult
    func type(_ script: String, bangla: Bool = true, capsLock: Bool = false) -> [InputHandler.Result] {
        Keys.parse(script, capsLock: capsLock).map { handler.handle($0, bangla: bangla, client: client) }
    }

    func top(_ word: String) -> String { suggester.suggest(word).candidates[0] }

    // MARK: Composition and commit

    func testCompositionIsMarkedNotInserted() {
        XCTAssertEqual(type("ami"), [.handled, .handled, .handled])
        XCTAssertEqual(client.marked, "আমি")
        XCTAssertEqual(client.text, "")
        XCTAssertTrue(handler.isComposing)
    }

    func testSpaceCommitsWithSpace() {
        type("ami ")
        XCTAssertEqual(client.text, "আমি ")
        XCTAssertEqual(client.marked, "")
        XCTAssertFalse(handler.isComposing)
    }

    func testSentence() {
        type("ami banglay gan gai ")
        XCTAssertEqual(client.text, "আমি বাংলায় গান গাই ")
        type("amar sOnar bangla ")
        XCTAssertEqual(client.text, "আমি বাংলায় গান গাই আমার সোনার বাংলা ")
    }

    func testSpaceOutsideCompositionPassesThrough() {
        XCTAssertEqual(type(" "), [.passThrough])
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testReturnEnterTabCommitThenPassThrough() {
        for key in ["{return}", "{enter}", "{tab}"] {
            setUp()
            XCTAssertEqual(type("ami" + key).last, .passThrough, key)
            XCTAssertEqual(client.text, "আমি", key)
            XCTAssertFalse(handler.isComposing, key)
            XCTAssertEqual(type(key), [.passThrough], "\(key) with nothing composed")
            XCTAssertEqual(client.calls.filter { $0.hasPrefix("insert") }.count, 1, key)
        }
    }

    func testEscapeKeepsEnglish() {
        XCTAssertEqual(type("ami{esc}").last, .handled)
        XCTAssertEqual(client.text, "ami")
        XCTAssertFalse(handler.isComposing)
        XCTAssertEqual(type("{esc}"), [.passThrough])
    }

    // MARK: Editing

    func testBackspaceEditsComposition() {
        type("amix{bs}")
        XCTAssertEqual(client.marked, top("ami"))
        XCTAssertEqual(handler.session.buffer, "ami")
    }

    func testBackspaceToEmptyEndsComposition() {
        type("ab{bs}{bs}")
        XCTAssertEqual(client.marked, "")
        XCTAssertEqual(client.calls.last, "mark()")
        XCTAssertFalse(handler.isComposing)
        XCTAssertEqual(type("{bs}"), [.passThrough], "nothing composed: the app deletes")
        XCTAssertEqual(client.text, "")
    }

    func testControlDeleteDiscardsWord() {
        XCTAssertEqual(type("amar{ctrl+bs}").last, .handled)
        XCTAssertEqual(client.marked, "")
        XCTAssertEqual(client.text, "")
        XCTAssertFalse(handler.isComposing)
        XCTAssertEqual(type("{ctrl+bs}"), [.passThrough])
    }

    func testForwardDeleteAndFunctionKeysCommitFirst() {
        for key in ["{fwd}", "{f5}", "{home}", "{left}", "{right}"] {
            setUp()
            XCTAssertEqual(type("ami" + key).last, .passThrough, key)
            XCTAssertEqual(client.text, "আমি", key)
        }
    }

    // MARK: Candidates

    func testArrowsChooseCandidates() {
        type("kal")
        let words = handler.session.candidates
        XCTAssertGreaterThan(words.count, 2)
        type("{down}")
        XCTAssertEqual(client.marked, words[1])
        type("{up}{up}")
        XCTAssertEqual(client.marked, words.last, "up from the first wraps to the last")
        type("{down} ")
        XCTAssertEqual(client.text, words[0] + " ")
        XCTAssertEqual(type("{down}"), [.passThrough], "nothing composed")
    }

    func testCandidateListFollowsComposition() {
        XCTAssertNil(handler.candidateList)
        type("kal")
        let list = handler.candidateList
        XCTAssertEqual(list?.typed, "kal")
        XCTAssertEqual(list?.selected, 0)
        XCTAssertEqual(list?.candidates, handler.session.candidates)
        type("{down}")
        XCTAssertEqual(handler.candidateList?.selected, 1)
        type(" ")
        XCTAssertNil(handler.candidateList)
    }

    func testNoCandidateListWhenSuggestionsOff() {
        var s = EngineSettings(); s.suggestions = false
        suggester.settings = s
        type("kal")
        XCTAssertNil(handler.candidateList)
        XCTAssertEqual(client.marked, suggester.suggest("kal").candidates.first)
    }

    func testPickByClick() {
        type("kal")
        let words = handler.session.candidates
        XCTAssertFalse(handler.pick(99, client: client))
        XCTAssertTrue(handler.pick(1, client: client))
        XCTAssertEqual(client.text, words[1])
        XCTAssertFalse(handler.isComposing)
        XCTAssertFalse(handler.pick(0, client: client), "nothing composed")
    }

    func testLearnedChoiceComesFirstNextTime() {
        let fresh = try! Suggester(dataDirectory: TestData.dataDir, selections: SelectionStore(), loadDictionaryInBackground: false)
        let h = InputHandler(suggester: fresh)
        let c = RecordingClient()
        for k in Keys.parse("kal{down} ") { _ = h.handle(k, bangla: true, client: c) }
        let chosen = String(c.text.dropLast())
        XCTAssertNotEqual(chosen, fresh.parser.convert("kal"))
        for k in Keys.parse("kal ") { _ = h.handle(k, bangla: true, client: c) }
        XCTAssertEqual(c.text, chosen + " " + chosen + " ")
    }

    // MARK: Modifiers, modes and special input

    func testShortcutsCommitAndPassThrough() {
        for key in ["{cmd+z}", "{ctrl+a}", "{opt+e}"] {
            setUp()
            XCTAssertEqual(type("ami" + key).last, .passThrough, key)
            XCTAssertEqual(client.text, "আমি", key)
        }
    }

    func testToggleShortcutCommitsAndWorksInBothModes() {
        XCTAssertEqual(type("ami{ctrl+shift+b}").last, .toggleMode)
        XCTAssertEqual(client.text, "আমি")
        XCTAssertEqual(type("{ctrl+shift+b}", bangla: false), [.toggleMode])
    }

    /// Control-Shift-B with Caps Lock on still switches (Caps Lock is not part of the shortcut); the
    /// same letter with other modifiers does not.
    func testToggleShortcutIgnoresCapsLockButNotOtherModifiers() {
        let withCaps = KeyPress(keyCode: 11, characters: "\u{2}", modifiers: Shortcut.control | Shortcut.shift | KeyPress.capsLock)
        XCTAssertEqual(handler.handle(withCaps, bangla: true, client: client), .toggleMode, "Caps Lock on, Bangla mode")
        XCTAssertEqual(handler.handle(withCaps, bangla: false, client: client), .toggleMode, "Caps Lock on, English mode")
        for script in ["{ctrl+b}", "{ctrl+shift+opt+b}", "{ctrl+shift+cmd+b}"] {
            XCTAssertNotEqual(type(script).first, .toggleMode, script)
        }
    }

    func testCustomToggleShortcut() {
        var s = EngineSettings(); s.toggleShortcut = Shortcut(keyCode: 96, modifiers: 0)   // F5
        suggester.settings = s
        XCTAssertEqual(type("{f5}"), [.toggleMode])
        XCTAssertEqual(type("{ctrl+shift+b}"), [.passThrough], "the old shortcut no longer toggles")
    }

    func testEnglishModePassesEverythingThrough() {
        XCTAssertEqual(Set(type("ami {bs}{return}", bangla: false)), [.passThrough])
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testDigits() {
        type("2024 ")
        XCTAssertEqual(client.text, "২০২৪ ")
    }

    func testDigitsWhenBanglaDigitsOff() {
        var s = EngineSettings(); s.banglaDigits = false
        suggester.settings = s
        XCTAssertEqual(type("2"), [.passThrough], "a digit starting a word goes straight to the app")
        type("ami2 ")
        XCTAssertEqual(client.text, "আমি2 ")
    }

    func testCapsLockDoesNotCapitalise() {
        type("ami ", capsLock: true)
        XCTAssertEqual(client.text, "আমি ")
    }

    func testShiftSelectsCapitalLetters() {
        type("sOnar ")
        XCTAssertEqual(client.text, "সোনার ")
    }

    func testPunctuation() {
        type("ami, tumi. ")
        XCTAssertEqual(client.text, "আমি, তুমি। ")
        setUp()
        type(".")
        XCTAssertEqual(client.marked, "।")
    }

    func testNonASCIICharacterCommitsAndPassesThrough() {
        type("ami")
        XCTAssertEqual(handler.handle(Keys.press("é"), bangla: true, client: client), .passThrough)
        XCTAssertEqual(client.text, "আমি")
    }

    func testCommitAndCancel() {
        type("ami")
        handler.commit(client)
        XCTAssertEqual(client.text, "আমি")
        handler.commit(client)
        XCTAssertEqual(client.text, "আমি", "second commit does nothing")
        type("tumi")
        XCTAssertEqual(handler.typedText, "tumi")
        handler.cancel()
        XCTAssertFalse(handler.isComposing)
        XCTAssertEqual(handler.typedText, "")
        XCTAssertEqual(client.text, "আমি")
    }

    // MARK: Properties over many random words (seeded, so failures reproduce)

    struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func randomWords(_ count: Int) -> [String] {
        var rng = SeededRandom(state: 42)
        let letters = Array("abcdeghijklmnoprstuyzAOIUDTNRSGJ")
        return (0..<count).map { _ in String((0..<Int.random(in: 1...9, using: &rng)).map { _ in letters.randomElement(using: &rng)! }) }
    }

    func testPropertySpaceCommitsTheMarkedTopCandidate() {
        for word in randomWords(400) {
            setUp()
            type(word)
            XCTAssertEqual(client.marked, suggester.suggest(word).candidates.first, word)
            type(" ")
            XCTAssertEqual(client.text, suggester.suggest(word).candidates[0] + " ", word)
            XCTAssertFalse(handler.isComposing, word)
        }
    }

    func testPropertyEscapeReturnsExactlyWhatWasTyped() {
        for word in randomWords(400) {
            setUp()
            type(word + "{esc}")
            XCTAssertEqual(client.text, word)
        }
    }

    func testPropertyBackspacingEverythingLeavesNothing() {
        for word in randomWords(200) {
            setUp()
            type(word + String(repeating: "{bs}", count: word.count))
            XCTAssertEqual(client.text, "", word)
            XCTAssertEqual(client.marked, "", word)
            XCTAssertFalse(handler.isComposing, word)
        }
    }

    func testLongSessionLosesNothing() {
        let words = "ami tomake bhalobashi amar sOnar bangla ekhane shobai bhalo ache ajke akash khub sundor".split(separator: " ").map(String.init)
        var want = ""
        for _ in 0..<25 {
            for w in words { type(w + " "); want += top(w) + " " }
        }
        XCTAssertEqual(client.text, want)
    }
}

final class CandidatePlacementTests: XCTestCase {
    let main = CandidatePlacement.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         visible: CGRect(x: 0, y: 70, width: 1440, height: 805))
    let right = CandidatePlacement.Screen(frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
                                          visible: CGRect(x: 1440, y: -200, width: 1920, height: 1055))
    let size = CGSize(width: 150, height: 200)

    func testBelowTheCaretLine() {
        let caret = CGRect(x: 300, y: 500, width: 1, height: 18)
        XCTAssertEqual(CandidatePlacement.origin(size: size, caret: caret, screens: [main, right]), CGPoint(x: 300, y: 297))
    }

    func testAboveWhenNoRoomBelow() {
        let caret = CGRect(x: 300, y: 120, width: 1, height: 18)
        XCTAssertEqual(CandidatePlacement.origin(size: size, caret: caret, screens: [main]), CGPoint(x: 300, y: 141))
    }

    func testKeptInsideTheRightEdge() {
        let caret = CGRect(x: 1430, y: 500, width: 1, height: 18)
        XCTAssertEqual(CandidatePlacement.origin(size: size, caret: caret, screens: [main]).x, 1290)
    }

    func testUsesTheScreenWithTheCaret() {
        let caret = CGRect(x: 1500, y: -150, width: 1, height: 18)
        let p = CandidatePlacement.origin(size: size, caret: caret, screens: [main, right])
        XCTAssertGreaterThanOrEqual(p.x, 1440)
        XCTAssertGreaterThanOrEqual(p.y, -200, "inside the second screen, which extends below the first")
        XCTAssertEqual(p.y, -150 + 18 + 3, "no room below on that screen either: goes above the line")
    }

    func testCaretOffAllScreensStaysVisible() {
        let caret = CGRect(x: -5000, y: 5000, width: 0, height: 0)
        let p = CandidatePlacement.origin(size: size, caret: caret, screens: [main])
        XCTAssertTrue(main.visible.contains(CGRect(origin: p, size: size)))
    }
}
