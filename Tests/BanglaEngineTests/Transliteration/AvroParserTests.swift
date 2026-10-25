import XCTest
@testable import BanglaEngine

final class AvroParserTests: XCTestCase {
    /// 400+ input/output pairs taken from the OpenBangla reference implementation's test-suite.
    func testReferencePairs() throws {
        let url = TestData.fixtures.appendingPathComponent("avro_reference.json")
        let pairs = try JSONDecoder().decode([[String]].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(pairs.count, 400)
        var failures: [String] = []
        for p in pairs {
            let got = TestData.parser.convert(p[0])
            if got != p[1] { failures.append("\(p[0]) -> \(got) (want \(p[1]))") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) mismatches:\n" + failures.joined(separator: "\n"))
    }

    /// Pairs from other upstream test suites (jsAvroPhonetic, pyAvroPhonetic, rupantor, okkhor, riti,
    /// iAvro, libavrophonetic); each entry records its source file and line.
    func testUpstreamPairs() throws {
        let url = TestData.fixtures.appendingPathComponent("avro_upstream_extra.json")
        let pairs = try JSONDecoder().decode([[String]].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(pairs.count, 30)
        let bad = pairs.filter { TestData.parser.convert($0[0]) != $0[1] }.map { "\($0[0]) (\($0[2]))" }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    func testCommonWords() {
        let p = TestData.parser
        XCTAssertEqual(p.convert("ami banglay gan gai"), "আমি বাংলায় গান গাই")
        XCTAssertEqual(p.convert("amar sOnar bangla"), "আমার সোনার বাংলা")
        XCTAssertEqual(p.convert("biggan"), "বিজ্ঞান")
        XCTAssertEqual(p.convert("123"), "১২৩")
    }

    func testSplitWord() {
        XCTAssertEqual(SplitWord("(ami),"), SplitWord("(ami),"))
        let s = SplitWord("\"ami\".")
        XCTAssertEqual(s.preceding, "\"")
        XCTAssertEqual(s.word, "ami")
        XCTAssertEqual(s.trailing, "\".")
        XCTAssertEqual(SplitWord("...").word, "")
    }
}
