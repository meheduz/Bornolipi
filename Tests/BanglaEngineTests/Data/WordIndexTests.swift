import XCTest
@testable import BanglaEngine

final class WordIndexTests: XCTestCase {
    func words(_ json: String) throws -> [String] {
        var out: [String] = []
        try WordIndex.forEachWord(in: Data(json.utf8)) { out.append($0) }
        return out
    }

    func testReaderKeepsFileOrder() throws {
        XCTAssertEqual(try words(#"{"b": ["x", "y"], "a": ["z"]}"#), ["x", "y", "z"])
        XCTAssertEqual(try words(#" { "k" : [ "দ" ,"দু" ] } "#), ["দ", "দু"])
    }

    func testReaderHandlesEmptyAndEscapes() throws {
        XCTAssertEqual(try words("{}"), [])
        XCTAssertEqual(try words(#"{"a": []}"#), [])
        XCTAssertEqual(try words(#"{"a": ["কা", "a\"b", "c\\d"]}"#), ["কা", "a\"b", "c\\d"])
    }

    func testReaderRejectsOtherShapes() {
        for bad in ["", "[", #"["x"]"#, #"{"a": "x"}"#, #"{"a": ["x""#, #"{"a": ["x"] "b": []}"#, #"{"a": [1]}"#] {
            XCTAssertThrowsError(try words(bad), bad)
        }
    }

    func testRealDictionaryMatchesFoundationParser() throws {
        let url = TestData.dataDir.appendingPathComponent("dictionary.json")
        let ours = try words(String(contentsOf: url, encoding: .utf8))
        let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [String]]
        XCTAssertEqual(ours.count, reference.values.reduce(0) { $0 + $1.count })
        XCTAssertEqual(Set(ours), Set(reference.values.joined()))
    }

    func testTiesFollowInsertionOrder() {
        let index = WordIndex()
        index.build(["ষ", "স", "শা"])
        XCTAssertEqual(index.matches(for: "শ", limit: 5), ["ষ", "স"], "same distance and length: file order")
        index.build(["স", "ষ"])
        XCTAssertEqual(index.matches(for: "শ", limit: 5), ["স", "ষ"])
    }

    func testCompletionsShortestFirst() {
        let index = WordIndex()
        index.build(["কলমদানি", "কলম", "কলমি", "কল", "কলা"])
        XCTAssertEqual(index.completions(for: "কল", limit: 2), ["কলম", "কলা"], "equal length: file order")
        XCTAssertEqual(index.completions(for: "কলম", limit: 5), ["কলমি", "কলমদানি"])
        XCTAssertEqual(index.completions(for: "ক", limit: 5), [], "one letter is too short to complete")
    }

    func testEmptyIndex() {
        let index = WordIndex()
        XCTAssertEqual(index.count, 0)
        XCTAssertEqual(index.matches(for: "কল", limit: 3), [])
        XCTAssertEqual(index.completions(for: "কল", limit: 3), [])
    }
}
