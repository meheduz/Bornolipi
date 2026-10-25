import XCTest

/// The independent set is a blind benchmark: none of its inputs may appear in a set that is tuned against.
final class EvaluationSetTests: XCTestCase {
    func testIndependentSetSharesNoInputWithTunedSets() throws {
        func inputs(_ name: String) throws -> Set<String> {
            let text = try String(contentsOf: TestData.repoRoot.appendingPathComponent("Tests/Evaluation/\(name).tsv"), encoding: .utf8)
            return Set(text.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { $0.split(separator: "\t").first.map(String.init) })
        }
        let blind = try inputs("independent")
        XCTAssertFalse(blind.isEmpty)
        for tuned in ["suggestions", "development", "heldout"] {
            XCTAssertEqual(blind.intersection(try inputs(tuned)), [], tuned)
        }
    }
}
