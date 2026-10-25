import Foundation
@testable import BanglaEngine

enum TestData {
    /// The repository root, located relative to this file (Tests/BanglaEngineTests/Support/).
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// Repo-level Data directory: the rules and dictionaries that ship with the keyboard.
    static let dataDir = repoRoot.appendingPathComponent("Data")
    /// Test fixtures: reference conversions and other expected results.
    static let fixtures = repoRoot.appendingPathComponent("Tests/BanglaEngineTests/Fixtures")

    static let parser: AvroParser = {
        try! AvroParser(grammarURL: dataDir.appendingPathComponent("AvroPhonetic.json"))
    }()
}
