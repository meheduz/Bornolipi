import XCTest
@testable import BanglaEngine

/// Backspace right after an automatic correction reopens the word with the exact conversion.
final class AutocorrectUndoTests: XCTestCase {
    private func run(_ script: String, _ client: TextClient, _ h: InputHandler) {
        for k in Keys.parse(script) {
            if h.handle(k, bangla: true, client: client) == .passThrough, k.keyCode == KeyCode.delete, let c = client as? RecordingClient {
                if !c.text.isEmpty { c.text.unicodeScalars.removeLast() }   // the app deletes
            }
        }
    }
    private func handler() -> InputHandler {
        var settings = EngineSettings()
        settings.learnChoices = false
        return InputHandler(suggester: try! Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false))
    }

    func testBackspaceAfterCorrectionReopensTheWord() {
        let h = handler(), c = RecordingClient()
        run("computer{space}", c, h)
        XCTAssertEqual(c.text, "কম্পিউটার ")
        run("{bs}", c, h)
        XCTAssertEqual(c.text, "", "the correction and its space are taken back")
        XCTAssertEqual(c.marked, "চম্পুতের", "the word is open again with the exact Avro conversion")
        XCTAssertEqual(h.session.buffer, "computer")
        run("{space}", c, h)
        XCTAssertEqual(c.text, "চম্পুতের ")
    }

    func testReopenedWordCanBeEditedOrRestoredToEnglish() {
        let h = handler(), c = RecordingClient()
        run("computer{space}{bs}{esc}", c, h)
        XCTAssertEqual(c.text, "computer", "Esc gives back the English letters")
        let h2 = handler(), c2 = RecordingClient()
        run("computer{space}{bs}{bs}", c2, h2)
        XCTAssertEqual(h2.session.buffer, "compute", "a second Backspace edits the reopened word")
    }

    func testOnlyImmediatelyAfterTheCorrection() {
        let h = handler(), c = RecordingClient()
        run("computer{space}a{bs}{bs}", c, h)
        XCTAssertEqual(c.text, "কম্পিউটার", "after another key, Backspace is ordinary again")
        XCTAssertEqual(c.marked, "")
    }

    func testNoUndoWithoutAnAutomaticCorrection() {
        for script in ["ami{space}{bs}", "computer{down}{space}{bs}"] {
            let h = handler(), c = RecordingClient()
            run(script, c, h)
            XCTAssertEqual(c.marked, "", "\(script): ordinary Backspace")
            XCTAssertFalse(c.calls.contains { $0.hasPrefix("remark") }, script)
        }
    }

    func testFocusChangeAndClicksForgetTheCorrection() {
        let h = handler(), c = RecordingClient()
        run("computer{space}", c, h)
        h.commit(c)
        run("{bs}", c, h)
        XCTAssertFalse(c.calls.contains { $0.hasPrefix("remark") })
    }

    func testCaretMovedOrTextChangedFallsBackToOrdinaryBackspace() {
        let h = handler(), c = RecordingClient()
        run("computer{space}", c, h)
        c.text += "x"   // the user clicked elsewhere or the app changed the text
        run("{bs}", c, h)
        XCTAssertEqual(c.text, "কম্পিউটার ", "the app's own Backspace removed x; nothing else changed")
        XCTAssertEqual(c.marked, "")
    }

    func testAppsThatCannotReportTextKeepOrdinaryBackspace() {
        let h = handler(), c = OpaqueClient()
        for k in Keys.parse("computer{space}") { _ = h.handle(k, bangla: true, client: c) }
        XCTAssertEqual(h.handle(Keys.parse("{bs}")[0], bangla: true, client: c), .passThrough)
        XCTAssertEqual(c.text, "কম্পিউটার ")
        XCTAssertFalse(h.isComposing)
    }

    func testSettingOff() {
        var settings = EngineSettings()
        settings.undoAutocorrect = false
        let h = InputHandler(suggester: try! Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false))
        let c = RecordingClient()
        run("computer{space}{bs}", c, h)
        XCTAssertEqual(c.text, "কম্পিউটার")
        XCTAssertEqual(c.marked, "")
    }

    func testArrowOrModeSwitchInBetweenGivesOrdinaryBackspace() {
        for script in ["computer{space}{left}{bs}", "computer{space}{ctrl+shift+b}{ctrl+shift+b}{bs}"] {
            let h = handler(), c = RecordingClient()
            run(script, c, h)
            XCTAssertFalse(c.calls.contains { $0.hasPrefix("remark") }, script)
            XCTAssertEqual(c.marked, "", script)
        }
    }

    func testCorrectionWithTrailingPunctuation() {
        let h = handler(), c = RecordingClient()
        run("computer,{space}", c, h)
        XCTAssertEqual(c.text, "কম্পিউটার, ")
        run("{bs}", c, h)
        XCTAssertEqual(c.text, "")
        XCTAssertEqual(h.session.buffer, "computer,")
        XCTAssertEqual(c.marked, "চম্পুতের,")
    }

    func testReturnAfterReopeningCommitsTheExactConversionOnce() {
        let h = handler(), c = RecordingClient()
        for k in Keys.parse("computer{space}{bs}") { _ = h.handle(k, bangla: true, client: c) }
        XCTAssertEqual(h.handle(Keys.parse("{return}")[0], bangla: true, client: c), .passThrough, "the app gets Return")
        XCTAssertEqual(c.text, "চম্পুতের", "committed once, no duplicate of the correction")
    }

    func testEnglishModeNeverUndoes() {
        let h = handler(), c = RecordingClient()
        for k in Keys.parse("computer{space}") { _ = h.handle(k, bangla: true, client: c) }
        XCTAssertEqual(h.handle(Keys.parse("{bs}")[0], bangla: false, client: c), .passThrough)
        XCTAssertFalse(c.calls.contains { $0.hasPrefix("remark") })
    }
}
