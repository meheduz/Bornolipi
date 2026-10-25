import XCTest
@testable import BanglaEngine

/// Data/loanword-lexicon.tsv keys its counts by word, so the retriever builds from whatever dictionary it
/// is given: editing Data/dictionary.json changes only the words edited, and never turns the retriever off.
final class LoanwordLexiconTests: XCTestCase {
    struct Golden { let input: String; let words: [String]; let costs: [Double] }

    /// Retriever outputs recorded before the lexicon was keyed by word (Fixtures/loanword_golden.tsv).
    static let golden: [Golden] = {
        let text = try! String(contentsOf: TestData.fixtures.appendingPathComponent("loanword_golden.tsv"), encoding: .utf8)
        return text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let pairs = stride(from: 1, to: f.count, by: 2)
            return Golden(input: f[0], words: pairs.map { f[$0] }, costs: pairs.map { Double(f[$0 + 1])! })
        }
    }()

    func assertGolden(_ r: LoanwordRetriever, _ g: Golden, _ context: String = "", line: UInt = #line) {
        let got = r.generate(g.input)
        XCTAssertEqual(got.map(\.word), g.words, "\(g.input) \(context)", line: line)
        XCTAssertEqual(got.map(\.cost), g.costs, "\(g.input) \(context): scores are exact", line: line)
    }

    func testOutputsMatchTheFirstFormat() throws {
        let s = LoanwordRetrieverTests.on
        let r = try XCTUnwrap(s.loanwordRetriever, "\(s.loanwordError.map { "\($0)" } ?? "")")
        XCTAssertEqual(LoanwordLexiconTests.golden.count, 50)
        for g in LoanwordLexiconTests.golden { assertGolden(r, g) }
        XCTAssertEqual(r.staleCounts, 0, "every counted word is in the shipped dictionary")
    }

    // MARK: Edited dictionaries

    /// A copy of the retriever's data with Data/dictionary.json passed through `edit`, and the retriever
    /// built from it.
    func retriever(editingDictionary edit: (String) -> String) throws -> LoanwordRetriever {
        let dir = try temporaryData()
        let url = dir.appendingPathComponent("dictionary.json")
        let edited = edit(try String(contentsOf: url, encoding: .utf8))
        try edited.write(to: url, atomically: true, encoding: .utf8)
        return try LoanwordRetriever(dataDirectory: dir, dictionary: try WordIndex(dictionaryURL: url))
    }

    func temporaryData(lexicon: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bornolipi-lexicon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in ["dictionary.json", "loanword-lexicon.tsv", "loanword-costs-en.json", "loanword-costs-native.json", "loanword-english.txt"] {
            try FileManager.default.copyItem(at: TestData.dataDir.appendingPathComponent(name), to: dir.appendingPathComponent(name))
        }
        if let lexicon {
            try lexicon.write(to: dir.appendingPathComponent("loanword-lexicon.tsv"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testAddingDictionaryWords() throws {
        let shipped = try XCTUnwrap(LoanwordRetrieverTests.on.loanwordRetriever)
        // A new word, and মোবাইলে, an added OpenSubtitles word (`+` line) that becomes a dictionary word.
        let r = try retriever { text in
            XCTAssertTrue(text.hasPrefix(#"{"d":["#))
            XCTAssertFalse(text.contains(#""ব্লকচেইন""#) || text.contains(#""মোবাইলে""#))
            return #"{"d":["ব্লকচেইন","মোবাইলে","# + text.dropFirst(6)
        }
        XCTAssertEqual(r.count, shipped.count + 1, "মোবাইলে is kept once")
        XCTAssertEqual(r.staleCounts, 0)
        XCTAssertTrue(r.generate("blockchain").map(\.word).contains("ব্লকচেইন"))
        XCTAssertEqual(r.generate("mobile").filter { $0.word == "মোবাইলে" }.count, 1)
        for g in LoanwordLexiconTests.golden where !r.generate(g.input).map(\.word).contains("ব্লকচেইন") {
            assertGolden(r, g, "after adding words")
        }
    }

    func testRemovingADictionaryWord() throws {
        let r = try retriever { text in
            XCTAssertEqual(text.components(separatedBy: #","সরকার","#).count, 2)
            return text.replacingOccurrences(of: #","সরকার","#, with: ",")
        }
        XCTAssertEqual(r.staleCounts, 1, "the count of সরকার is left out")
        XCTAssertFalse(r.generate("sarkar").map(\.word).contains("সরকার"))
        XCTAssertTrue(r.generate("sarkar").map(\.word).contains("সরকারের"))
        for g in LoanwordLexiconTests.golden where !g.words.contains("সরকার") {
            assertGolden(r, g, "after removing a word")
        }
    }

    /// An edit that adds a counted word again, earlier in the file: the first copy is the dictionary word
    /// that is kept, and it keeps the word's count (the walk had given it to the later copy).
    func testAWordAddedAgainEarlierKeepsItsCount() throws {
        let shipped = try XCTUnwrap(LoanwordRetrieverTests.on.loanwordRetriever)
        let r = try retriever { text in
            XCTAssertEqual(text.components(separatedBy: #","সরকার","#).count, 2)
            return #"{"d":["সরকার","# + text.dropFirst(6)
        }
        XCTAssertEqual(r.count, shipped.count, "the second copy is dropped")
        XCTAssertEqual(r.staleCounts, 0)
        let before = shipped.generate("sarkar"), after = r.generate("sarkar")
        XCTAssertEqual(after.first { $0.word == "সরকার" }?.cost, before.first { $0.word == "সরকার" }?.cost, "সরকার keeps its count")
        XCTAssertEqual(after.map(\.word), before.map(\.word))
    }

    // MARK: The file

    func small(_ lexicon: String) throws -> LoanwordRetriever {
        let index = WordIndex()
        index.build(["আমি", "তুমি", "গান"])
        return try LoanwordRetriever(dataDirectory: try temporaryData(lexicon: lexicon), dictionary: index)
    }

    func testAnySmallDictionaryLoads() throws {
        let r = try small("# bornolipi.loanword-lexicon\t2\n=\tআমি\t3\n=\tকাল\t2\n+\tতুমি\t5\n+\tবই\t4\n")
        XCTAssertEqual(r.count, 4, "আমি তুমি গান, then বই (তুমি is a dictionary word)")
        XCTAssertEqual(r.staleCounts, 1, "কাল is not in this dictionary")
        XCTAssertEqual(r.generate("boi").first?.word, "বই")
    }

    func testMalformedLexiconsAreRefused() throws {
        let header = "# bornolipi.loanword-lexicon\t2\n"
        let cases: [(String, String)] = [
            ("# bornolipi.loanword-lexicon\t1\ndictionary\t3\t0123456789abcdef\n=\t0\t27\n", "first line"),   // the first format
            ("=\tআমি\t3\n", "first line"),
            (header + "=\tআমি\n", "line 2"),
            (header + "=\tআমি\t3\textra\n", "line 2"),
            (header + "# a comment\n=\tআমি\t0\n", "line 3"),
            (header + "=\tআমি\t-3\n", "line 2"),
            (header + "=\tআমি\t99999999999\n", "line 2"),
            (header + "=\tami\t3\n", "line 2"),
            (header + "=\t\t3\n", "line 2"),
            (header + "=\t0\t27\n", "line 2"),
            (header + "*\tআমি\t3\n", "line 2"),
            (header + "==\tআমি\t3\n", "line 2"),
            (header + "=\tআমি\t3\n=\tআমি\t4\n", "listed twice"),
            (header + "+\tবই\t3\n+\tবই\t4\n", "listed twice"),
            (header + "=\tকাল\t3\n+\tকাল\t4\n", "listed twice"),
        ]
        for (text, message) in cases {
            XCTAssertThrowsError(try small(text), text) { error in
                guard case LoanwordRetriever.LoadError.badFormat(let s) = error else { return XCTFail("\(text): \(error)") }
                XCTAssertTrue(s.contains(message), "\(text): \(s)")
            }
        }
    }
}
