import XCTest
@testable import BanglaEngine

/// ↑ on the first candidate wraps to the last candidate of the engine's list as 0.1.0 showed it (the typed English
/// word, when that setting is on), not to a word appended after it; appended words are reached with ↓ or a click.
final class NavigationBoundaryTests: XCTestCase {
    // meyar: মেয়ারকা is a completion, মেয়র a loose word 0.1.0 could not reach (appended after the list).
    static let words = ["মে\u{09DF}র", "মে\u{09DF}ারকা"]

    func suggester(english: Bool, dictionary: [String] = words) throws -> Suggester {
        let s = try LooseNormalizationInvariantTests.suggester(names: [], dictionary: dictionary)
        var st = EngineSettings(); st.includeEnglish = english
        s.settings = st
        return s
    }

    func session(english: Bool, dictionary: [String] = words) throws -> PhoneticSession {
        PhoneticSession(suggester: try suggester(english: english, dictionary: dictionary))
    }

    func type(_ session: PhoneticSession, _ text: String) { for c in text { session.append(String(c)) } }

    func testUpReachesTheTypedEnglishWordInOnePress() throws {
        let p = try session(english: true)
        type(p, "meyar")
        XCTAssertEqual(p.candidates, ["মে\u{09DF}ার", "মে\u{09DF}ারকা", "meyar", "মে\u{09DF}র"])
        XCTAssertEqual(p.suggestion.engineCount, 3)
        p.moveSelection(by: -1)
        XCTAssertEqual(p.markedText, "meyar", "↑ on the first candidate wraps to the engine's last candidate")
        p.moveSelection(by: -1)
        XCTAssertEqual(p.selected, 1)
    }

    func testAppendedWordsAreReachedWithDown() throws {
        let p = try session(english: true)
        type(p, "meyar")
        for _ in 0..<3 { p.moveSelection(by: 1) }
        XCTAssertEqual(p.markedText, "মে\u{09DF}র", "↓ past the engine's last candidate reaches the appended word")
        p.moveSelection(by: 1)
        XCTAssertEqual(p.selected, 0, "↓ on the very last candidate wraps to the first")
        XCTAssertTrue(p.select(index: 3), "a click (pick) still selects the appended word")
    }

    func testWithoutAppendedWordsNavigationIsUnchanged() throws {
        let p = try session(english: true)
        type(p, "meyarka")   // the dictionary word itself: nothing is appended
        XCTAssertNil(p.suggestion.engineCount)
        let n = p.candidates.count
        p.moveSelection(by: -1)
        XCTAssertEqual(p.selected, n - 1)
    }

    func testUpWrapsToTheEnginesLastCandidateWithEnglishOff() throws {
        // With typed English off, meyar shows the conversion and the completion; the appended word follows.
        let p = try session(english: false)
        type(p, "meyar")
        XCTAssertEqual(p.suggestion.engineCount, 2)
        p.moveSelection(by: -1)
        XCTAssertEqual(p.selected, 1, "↑ on the first candidate goes to the completion, as in 0.1.0, not to the appended word")
    }

    func testUpDoesNothingWithOneEngineCandidate() throws {
        // Without the completion, 0.1.0 showed the conversion alone and the arrows did nothing.
        let p = try session(english: false, dictionary: ["মে\u{09DF}র"])
        type(p, "meyar")
        XCTAssertEqual(p.candidates, ["মে\u{09DF}ার", "মে\u{09DF}র"])
        XCTAssertEqual(p.suggestion.engineCount, 1)
        p.moveSelection(by: -1)
        XCTAssertEqual(p.selected, 0)
        XCTAssertEqual(p.markedText, "মে\u{09DF}ার", "↑ leaves the conversion selected")
        XCTAssertTrue(p.refreshForNewData() == false && p.selected == 0)
        p.moveSelection(by: 1)
        XCTAssertEqual(p.markedText, "মে\u{09DF}র", "↓ reaches the appended word")
    }

    /// Types `script` through a fresh InputHandler (committing a picked word teaches it, so cases do not share one).
    func committed(_ script: String, english: Bool, dictionary: [String] = words) throws -> (text: String, marked: String) {
        let h = InputHandler(suggester: try suggester(english: english, dictionary: dictionary))
        let c = RecordingClient()
        for k in Keys.parse(script) { XCTAssertEqual(h.handle(k, bangla: true, client: c), .handled, script) }
        return (c.text, c.marked)
    }

    func testArrowsThroughTheInputHandler() throws {
        XCTAssertEqual(try committed("meyar{up}", english: true).marked, "meyar", "one ↑ shows the typed English word, as in 0.1.0")
        XCTAssertEqual(try committed("meyar{up} ", english: true).text, "meyar ")
        XCTAssertEqual(try committed("meyar{down}{down}{down} ", english: true).text, "মে\u{09DF}র ",
                       "↓ past the typed English word commits the appended word")
        XCTAssertEqual(try committed("meyar{up} ", english: false, dictionary: ["মে\u{09DF}র"]).text, "মে\u{09DF}ার ",
                       "↑ with one engine candidate changes nothing; Space inserts the conversion")
    }
}
