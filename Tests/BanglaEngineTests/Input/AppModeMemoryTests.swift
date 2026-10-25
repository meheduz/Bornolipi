import XCTest
@testable import BanglaEngine

final class AppModeMemoryTests: XCTestCase {
    func testRemembersPerApp() {
        var m = AppModeMemory()
        XCTAssertNil(m.mode(for: "com.apple.Safari"), "unknown apps use the default start mode")
        m.record(false, for: "com.apple.Safari")
        m.record(true, for: "com.apple.TextEdit")
        XCTAssertEqual(m.mode(for: "com.apple.Safari"), false)
        XCTAssertEqual(m.mode(for: "com.apple.TextEdit"), true)
        m.record(true, for: "com.apple.Safari")
        XCTAssertEqual(m.mode(for: "com.apple.Safari"), true)
        XCTAssertEqual(m.entries.count, 2, "one entry per app")
    }

    func testAppsWithoutUsableIdentifierAreNeverStored() {
        var m = AppModeMemory()
        for bad in [nil, "", "x", "no-dots", "has space.app", String(repeating: "a.", count: 200), "com.example.বাংলা"] {
            m.record(true, for: bad)
            XCTAssertNil(m.mode(for: bad))
        }
        XCTAssertTrue(m.entries.isEmpty)
    }

    func testCapacityKeepsTheMostRecent() {
        var m = AppModeMemory()
        for i in 0..<(AppModeMemory.capacity + 20) { m.record(i % 2 == 0, for: "com.example.app\(i)") }
        XCTAssertEqual(m.entries.count, AppModeMemory.capacity)
        XCTAssertNil(m.mode(for: "com.example.app0"), "the oldest are dropped")
        XCTAssertNotNil(m.mode(for: "com.example.app\(AppModeMemory.capacity + 19)"))
    }

    func testRoundTripAndForget() throws {
        var m = AppModeMemory()
        m.record(false, for: "com.microsoft.VSCode")
        let back = try JSONDecoder().decode(AppModeMemory.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        m.removeAll()
        XCTAssertNil(m.mode(for: "com.microsoft.VSCode"))
    }

    func testOffByDefault() throws {
        XCTAssertFalse(EngineSettings().rememberModePerApp)
        XCTAssertFalse(try JSONDecoder().decode(EngineSettings.self, from: Data("{}".utf8)).rememberModePerApp)
    }

    /// Found by review: focus changes inside one app must not undo the user's choice there.
    func testActivationOnlyChangesModeWhenTheAppChanges() {
        var m = AppModeMemory()
        m.record(false, for: "com.apple.TextEdit")
        XCTAssertEqual(m.modeOnActivation(of: "com.apple.TextEdit", lastApp: "com.apple.Notes", startInBangla: true), false)
        XCTAssertNil(m.modeOnActivation(of: "com.apple.TextEdit", lastApp: "com.apple.TextEdit", startInBangla: true),
                     "another field in the same app keeps the current mode")
        XCTAssertEqual(m.modeOnActivation(of: "com.apple.Notes", lastApp: "com.apple.TextEdit", startInBangla: true), true,
                       "an app without a remembered mode starts in the start mode")
        XCTAssertNil(m.modeOnActivation(of: nil, lastApp: "com.apple.TextEdit", startInBangla: true),
                     "an app without an identifier keeps the current mode")
        XCTAssertNil(m.modeOnActivation(of: "nodots", lastApp: nil, startInBangla: false))
    }
}
