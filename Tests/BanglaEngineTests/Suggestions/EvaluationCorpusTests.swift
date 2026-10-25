import XCTest
@testable import BanglaEngine

/// The evaluation corpus as a quality floor: see `swift run bangla-eval` for the full table.
final class EvaluationCorpusTests: XCTestCase {
    func testCorpusRecallAndNoFalsePositives() throws {
        let corpus = TestData.dataDir.deletingLastPathComponent().appendingPathComponent("Tests/Evaluation/suggestions.tsv")
        let s = ConventionalSpellingTests.suggester
        var expected = 0, top3 = 0, falsePositives: [String] = []
        for line in try String(contentsOf: corpus, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let c = s.suggest(f[0]).candidates
            if f[4] == "mustNot" { if c.contains(f[1]) { falsePositives.append(f[0]) }; continue }
            expected += 1
            if c.prefix(3).contains(f[1]) { top3 += 1 }
        }
        XCTAssertEqual(falsePositives, [])
        XCTAssertGreaterThanOrEqual(Double(top3) / Double(expected), 0.95, "top-3 recall \(top3)/\(expected)")
    }
}

/// Proper nouns (Data/propernouns.json): offered after the exact conversion, measured on a held-out
/// set built separately from the data.
final class ProperNounTests: XCTestCase {
    let s = ConventionalSpellingTests.suggester

    func testOfferedAfterTheExactConversion() {
        for (input, want) in [("sreemangal", "শ্রীমঙ্গল"), ("keraniganj", "কেরানীগঞ্জ"), ("karnaphuli", "কর্ণফুলী"), ("savar", "সাভার")] {
            let c = s.suggest(input).candidates
            XCTAssertTrue(c.contains(want), "\(input): \(c)")
            XCTAssertEqual(c.first, s.suggest(input).candidates.first)
        }
    }

    func testEverydayWordsGetNoPlaceNames() throws {
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: TestData.dataDir.appendingPathComponent("propernouns.json"))) as! [String: Any]
        let names = Set((file["entries"] as! [[String: Any]]).flatMap { $0["bangla"] as! [String] })
        for word in ["ami", "tumi", "kemon", "bhalo", "achi", "kotha", "kichu", "ekhon", "keno", "jani", "boli", "korbo", "dekho", "shob", "onek"] {
            let extra = s.suggest(word).candidates.filter { names.contains($0) }
            XCTAssertEqual(extra, [], "\(word) gets place or institution names")
        }
    }

    func testHeldOutRecallFloor() throws {
        let corpus = TestData.repoRoot.appendingPathComponent("Tests/Evaluation/heldout.tsv")
        var n = 0, top3 = 0
        for line in try String(contentsOf: corpus, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            n += 1
            if s.suggest(f[0]).candidates.prefix(3).contains(f[1]) { top3 += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(top3) / Double(n), 0.70, "held-out top-3 \(top3)/\(n)")
    }
}
