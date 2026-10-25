import XCTest
@testable import BanglaEngine

final class CandidateTextSizeTests: XCTestCase {
    func testOlderSettingsGetTheDefaultAndValuesAreClamped() throws {
        let old = try JSONDecoder().decode(EngineSettings.self, from: Data(#"{"suggestions":true}"#.utf8))
        XCTAssertEqual(old.candidateTextSize, 17)
        XCTAssertEqual(try JSONDecoder().decode(EngineSettings.self, from: Data(#"{"candidateTextSize":99}"#.utf8)).candidateTextSize, 28)
        XCTAssertEqual(try JSONDecoder().decode(EngineSettings.self, from: Data(#"{"candidateTextSize":2}"#.utf8)).candidateTextSize, 13)
        XCTAssertEqual(try JSONDecoder().decode(EngineSettings.self, from: Data(#"{"candidateTextSize":"big"}"#.utf8)).candidateTextSize, 17,
                       "an unreadable value falls back instead of resetting all settings")
        var s = EngineSettings()
        s.candidateTextSize = 22
        XCTAssertEqual(try JSONDecoder().decode(EngineSettings.self, from: JSONEncoder().encode(s)).candidateTextSize, 22)
    }
}
