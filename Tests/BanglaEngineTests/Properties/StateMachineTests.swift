import XCTest
@testable import BanglaEngine

/// Property-based tests of the composition state machine: random key sequences (fixed seeds, so a
/// failure replays exactly) against invariants, with failing sequences shrunk to a minimal case.
final class StateMachineTests: XCTestCase {
    /// Learning is off so earlier sequences cannot change later ones; learning has its own test.
    static let suggester: Suggester = {
        var settings = EngineSettings()
        settings.learnChoices = false
        return try! Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
    }()

    /// A text field: committed text plus the marked (underlined) word, as IMK clients keep them.
    final class Field: TextClient {
        var text = "", marked = "", inserts = 0, remarks = 0
        func insert(_ t: String) { text += t; marked = ""; inserts += 1 }
        func setMarked(_ t: String) { marked = t }
        func textBeforeCaret(utf16Length: Int) -> String? {
            let u = Array(text.utf16)
            return utf16Length <= u.count ? String(decoding: u.suffix(utf16Length), as: UTF16.self) : nil
        }
        func remark(utf16Length: Int, as m: String) -> Bool {
            let u = Array(text.utf16)
            guard utf16Length <= u.count else { return false }
            text = String(decoding: u.dropLast(utf16Length), as: UTF16.self)
            marked = m
            remarks += 1
            return true
        }
    }

    enum Event: CustomStringConvertible {
        case char(Character), space, delete, returnKey, escape, tab, up, down, left, toggle, focusChange, click(Int), commandS
        var description: String {
            switch self {
            case .char(let c): return String(c)
            case .space: return "{space}"
            case .delete: return "{bs}"
            case .returnKey: return "{return}"
            case .escape: return "{esc}"
            case .tab: return "{tab}"
            case .up: return "{up}"
            case .down: return "{down}"
            case .left: return "{left}"
            case .toggle: return "{ctrl+shift+b}"
            case .focusChange: return "{focus}"
            case .click(let i): return "{click \(i)}"
            case .commandS: return "{cmd+s}"
            }
        }
        var key: KeyPress? {
            switch self {
            case .char(let c):
                let k = Keys.parse(String(c))
                return k.first
            case .space: return Keys.parse("{space}")[0]
            case .delete: return Keys.parse("{bs}")[0]
            case .returnKey: return Keys.parse("{return}")[0]
            case .escape: return Keys.parse("{esc}")[0]
            case .tab: return Keys.parse("{tab}")[0]
            case .up: return Keys.parse("{up}")[0]
            case .down: return Keys.parse("{down}")[0]
            case .left: return Keys.parse("{left}")[0]
            case .toggle: return KeyPress(keyCode: 11, characters: "\u{2}", modifiers: Shortcut.control | Shortcut.shift)
            case .commandS: return KeyPress(keyCode: 1, characters: "s", modifiers: Shortcut.command)
            case .focusChange, .click: return nil
            }
        }
    }

    /// Deterministic generator (a 64-bit LCG), so every run sees the same sequences.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    static let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`.,;:'\"?!-()[]0123456789^&*/_=+~")

    static func randomEvents(_ g: inout Seeded, count: Int) -> [Event] {
        (0..<count).map { _ in
            switch Int.random(in: 0..<100, using: &g) {
            case 0..<62: return .char(letters[Int.random(in: 0..<letters.count, using: &g)])
            case 62..<72: return .space
            case 72..<80: return .delete
            case 80..<83: return .returnKey
            case 83..<85: return .escape
            case 85..<88: return .down
            case 88..<90: return .up
            case 90..<92: return .left
            case 92..<94: return .toggle
            case 94..<96: return .focusChange
            case 96..<98: return .click(Int.random(in: 0..<10, using: &g))
            case 98: return .tab
            default: return .commandS
            }
        }
    }

    /// Runs the events; returns the first broken invariant, or nil, plus the field.
    static func run(_ events: [Event], startInBangla: Bool = true) -> (String?, Field) {
        let handler = InputHandler(suggester: suggester)
        let field = Field()
        var bangla = startInBangla
        func scalarsEqual(_ a: String, _ b: String) -> Bool { a.unicodeScalars.elementsEqual(b.unicodeScalars) }
        for (n, event) in events.enumerated() {
            let wasComposing = handler.isComposing
            let before = field.text, typed = handler.typedText, shown = field.marked
            let remarksBefore = field.remarks
            let candidates = handler.candidateList?.candidates
            switch event {
            case .focusChange: handler.commit(field)
            case .click(let i): _ = handler.pick(i, client: field)
            default:
                switch handler.handle(event.key!, bangla: bangla, client: field) {
                case .toggleMode: bangla.toggle()
                case .passThrough:
                    // What the host app does with keys the input method lets through.
                    switch event {
                    case .char(let c): field.text += String(c)
                    case .space: field.text += " "
                    case .returnKey: field.text += "\n"
                    case .tab: field.text += "\t"
                    case .delete: if !field.text.unicodeScalars.isEmpty { field.text.unicodeScalars.removeLast() }
                    default: break
                    }
                default: break
                }
            }
            let at = "after event \(n + 1) (\(event))"
            let expectedMark = suggester.suggest(handler.typedText).candidates.first ?? ""
            if handler.isComposing && field.marked.isEmpty && !expectedMark.isEmpty { return ("composing but nothing marked \(at)", field) }
            if !handler.isComposing && !field.marked.isEmpty { return ("marked text left after the word ended \(at)", field) }
            if case .delete = event {} else if !field.text.unicodeScalars.starts(with: before.unicodeScalars) {
                return ("committed text changed \(at)", field)
            }
            if case .escape = event, wasComposing, !scalarsEqual(field.text, before + typed) { return ("esc did not restore the typed letters \(at)", field) }
            if case .space = event, wasComposing, !scalarsEqual(field.text, before + shown + " ") { return ("space did not commit what was shown \(at)", field) }
            if case .click(let i) = event, wasComposing, let c = candidates, i < c.count, !scalarsEqual(field.text, before + c[i]) {
                return ("click committed the wrong candidate \(at)", field)
            }
            if case .focusChange = event {
                let count = field.inserts
                handler.commit(field)
                if field.inserts != count { return ("a second commit inserted again \(at)", field) }
            }
            if field.text.unicodeScalars.contains(where: { $0.value == 0xFFFD }) { return ("replacement character \(at)", field) }
            // Undoing a correction takes back exactly the last insertion and reopens it as the word.
            if field.remarks != remarksBefore {
                guard case .delete = event, !wasComposing, handler.isComposing, before.unicodeScalars.starts(with: field.text.unicodeScalars) else {
                    return ("a correction was undone outside a Backspace right after it \(at)", field)
                }
            }
        }
        return (nil, field)
    }

    /// Removes events while the same invariant still fails.
    static func shrink(_ events: [Event], startInBangla: Bool) -> [Event] {
        guard let first = run(events, startInBangla: startInBangla).0 else { return events }
        let kind = first.components(separatedBy: " after event").first!
        var current = events
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < current.count {
                var candidate = current
                candidate.remove(at: i)
                if let r = run(candidate, startInBangla: startInBangla).0, r.hasPrefix(kind) { current = candidate; changed = true } else { i += 1 }
            }
        }
        return current
    }

    /// BORNOLIPI_FUZZ_ITERATIONS=200000 swift test --filter StateMachineTests runs a longer search;
    /// BORNOLIPI_FUZZ_SEED picks another sequence of inputs. Failures print a minimal replay.
    static let iterations = Int(ProcessInfo.processInfo.environment["BORNOLIPI_FUZZ_ITERATIONS"] ?? "") ?? 4000
    static let seed = UInt64(ProcessInfo.processInfo.environment["BORNOLIPI_FUZZ_SEED"] ?? "") ?? 20261024

    func testRandomSequencesKeepInvariants() {
        var g = Seeded(state: Self.seed)
        for _ in 0..<Self.iterations {
            let events = Self.randomEvents(&g, count: Int.random(in: 1...60, using: &g))
            let bangla = Int.random(in: 0..<10, using: &g) > 0
            if let failure = Self.run(events, startInBangla: bangla).0 {
                let minimal = Self.shrink(events, startInBangla: bangla)
                return XCTFail("\(failure). Minimal replay (bangla=\(bangla)): \(minimal.map(\.description).joined())")
            }
        }
    }

    func testCorrectionsAreUndoneByFuzzedSequences() {
        // Make sure the fuzzer actually reaches the undo path, not just that nothing breaks.
        var g = Seeded(state: 42)
        var undone = 0
        let words = ["computer", "school", "mobile", "facebook", "internet", "ami", "bhalo"]
        for _ in 0..<400 {
            var events: [Event] = []
            for _ in 0..<Int.random(in: 1...4, using: &g) {
                events += words[Int.random(in: 0..<words.count, using: &g)].map { Event.char($0) } + [.space]
                if Bool.random(using: &g) { events.append(.delete) }
                if Int.random(in: 0..<4, using: &g) == 0 { events += Self.randomEvents(&g, count: 3) }
            }
            let (failure, field) = Self.run(events)
            XCTAssertNil(failure, events.map(\.description).joined())
            undone += field.remarks
        }
        XCTAssertGreaterThan(undone, 50, "the undo path was exercised")
    }

    func testSameInputGivesSameOutput() {
        var g = Seeded(state: 7)
        for _ in 0..<500 {
            let events = Self.randomEvents(&g, count: 25)
            XCTAssertEqual(Self.run(events).1.text, Self.run(events).1.text, events.map(\.description).joined())
        }
    }

    func testDeletingAWholeWordRestoresTheText() {
        var g = Seeded(state: 99)
        for _ in 0..<2000 {
            let word = (0..<Int.random(in: 1...14, using: &g)).map { _ in Event.char(Self.letters[Int.random(in: 0..<52, using: &g)]) }
            let (_, field) = Self.run([.char("x"), .space] + word + Array(repeating: .delete, count: word.count))
            XCTAssertEqual(field.text, Self.suggester.suggest("x").candidates[0] + " ", word.map(\.description).joined())
            XCTAssertEqual(field.marked, "")
        }
    }

    /// Differential: with suggestions and autocorrect off, Space inserts exactly the rule conversion.
    func testWithoutSuggestionsSpaceInsertsTheRuleConversion() throws {
        var settings = EngineSettings()
        settings.suggestions = false
        settings.autocorrect = false
        let plain = try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
        var g = Seeded(state: 3)
        for _ in 0..<3000 {
            let word = String((0..<Int.random(in: 1...10, using: &g)).map { _ in Self.letters[Int.random(in: 0..<Self.letters.count, using: &g)] })
            XCTAssertEqual(plain.suggest(word).candidates.first ?? "", Suggester.avroForm(plain.parser.convert(word)), word)
        }
    }

    /// Every committed candidate uses only Bangla script, ASCII, and the joiners Avro produces.
    func testCandidatesUseExpectedCharacters() {
        var g = Seeded(state: 11)
        for _ in 0..<3000 {
            let word = String((0..<Int.random(in: 1...10, using: &g)).map { _ in Self.letters[Int.random(in: 0..<Self.letters.count, using: &g)] })
            for c in Self.suggester.suggest(word).candidates {
                for u in c.unicodeScalars {
                    XCTAssertTrue((0x0980...0x09FF).contains(u.value) || u.isASCII || u.value == 0x200C || u.value == 0x200D || u.value == 0x0964 || u.value == 0x0965,
                                  "\(word) -> \(c) contains U+\(String(u.value, radix: 16))")
                }
            }
        }
    }

    /// A chosen candidate is learned: the same word typed again offers it first.
    func testLearningIsLocalAndPredictable() throws {
        let s = try Suggester(dataDirectory: TestData.dataDir, selections: SelectionStore(), loadDictionaryInBackground: false)
        let h = InputHandler(suggester: s)
        let field = Field()
        for k in Keys.parse("kono{down}{down}{space}") { _ = h.handle(k, bangla: true, client: field) }
        let chosen = String(field.text.dropLast())
        XCTAssertNotEqual(chosen, "কন")
        for k in Keys.parse("kono{space}") { _ = h.handle(k, bangla: true, client: field) }
        XCTAssertEqual(field.text, chosen + " " + chosen + " ")
    }

    /// Leading punctuation is converted in context, as Avro does (found by the differential test).
    func testLeadingPunctuationMatchesAvro() {
        for input in [".`", ".5", ".57", ".`ami", "`,", ".,`", "(ami)", "?ami", "ami.`", "..", "..."] {
            let (_, field) = Self.run(input.map { Event.char($0) } + [.space])
            XCTAssertEqual(field.text, Suggester.avroForm(Self.suggester.parser.convert(input)) + " ", input)
        }
    }

    /// Minimal regression cases found by the fuzzer and the edge-case audit.
    func testRegressionReplays() {
        // A lone ঃ joins the space before it into one visible character; the text itself is intact.
        let (failure, field) = Self.run([.space, .char(":"), .space])
        XCTAssertNil(failure)
        XCTAssertEqual(Array(field.text.unicodeScalars).map(\.value), [0x20, 0x0983, 0x20])
        // A lone ` converts to nothing: composing, nothing shown, and Space inserts only a space.
        XCTAssertNil(Self.run([.char("`")]).0)
        XCTAssertEqual(Self.run([.char("`"), .space]).1.text, " ")
        // ".`" is Avro's literal full stop; it used to vanish.
        XCTAssertEqual(Self.run([.char("."), .char("`"), .space]).1.text, ". ")
    }
}
