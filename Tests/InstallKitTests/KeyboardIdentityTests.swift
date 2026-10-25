import XCTest
@testable import InstallKit

final class KeyboardIdentityTests: XCTestCase {
    func testReleaseDefaults() {
        let r = KeyboardIdentity.resolve([:], mainBundleID: "com.apple.dt.xctest.tool", mainBundleName: "xctest")
        XCTAssertEqual(r.id, "io.github.meheduz.inputmethod.Bornolipi")
        XCTAssertEqual(r.bundle, "BornolipiKeyboard.app")
        XCTAssertEqual(r.dataFolder, "Bornolipi")
    }

    func testSetupAppNamesTheKeyboardItCarries() {
        let info: [String: Any] = ["BornolipiKeyboardBundleID": "io.github.meheduz.inputmethod.TestBornolipi",
                                   "BornolipiKeyboardBundleName": "TestBornolipiKeyboard.app", "BornolipiDataFolder": "TestBornolipi"]
        let r = KeyboardIdentity.resolve(info, mainBundleID: "io.github.meheduz.TestBornolipi", mainBundleName: "Bornolipi Test.app")
        XCTAssertEqual(r.id, "io.github.meheduz.inputmethod.TestBornolipi")
        XCTAssertEqual(r.bundle, "TestBornolipiKeyboard.app")
        XCTAssertEqual(r.dataFolder, "TestBornolipi")
    }

    func testKeyboardUsesItsOwnBundle() {
        let info: [String: Any] = ["InputMethodConnectionName": "TestBornolipi_Connection", "BornolipiDataFolder": "TestBornolipi"]
        let r = KeyboardIdentity.resolve(info, mainBundleID: "io.github.meheduz.inputmethod.TestBornolipi", mainBundleName: "TestBornolipiKeyboard.app")
        XCTAssertEqual(r.id, "io.github.meheduz.inputmethod.TestBornolipi")
        XCTAssertEqual(r.bundle, "TestBornolipiKeyboard.app")
    }

    func testTestsRunWithTheReleaseIdentityAndChannel() {
        // The test runner is neither app, so the release values apply.
        XCTAssertEqual(Keyboard.bundleID, KeyboardIdentity.releaseBundleID)
        XCTAssertEqual(KeyboardRestart.Channel.keyboard.request.rawValue, "io.github.meheduz.Bornolipi.keyboard.restart")
    }

    /// Found before real-keyboard testing: the release ID is a prefix of the test ID.
    func testSourceOwnershipIsExact() {
        let release = "io.github.meheduz.inputmethod.Bornolipi", test = "io.github.meheduz.inputmethod.TestBornolipi"
        XCTAssertTrue(KeyboardIdentity.owns(sourceID: release, bundleID: release))
        XCTAssertTrue(KeyboardIdentity.owns(sourceID: release + ".Phonetic", bundleID: release))
        XCTAssertFalse(KeyboardIdentity.owns(sourceID: test, bundleID: release), "the release keyboard does not own Bornolipi Test")
        XCTAssertFalse(KeyboardIdentity.owns(sourceID: test + ".Phonetic", bundleID: release))
        XCTAssertFalse(KeyboardIdentity.owns(sourceID: release + ".Phonetic", bundleID: test))
        XCTAssertTrue(KeyboardIdentity.owns(sourceID: test + ".Phonetic", bundleID: test))
    }
}

/// scripts/build.sh writes the release identity into both Info.plists; it must be exactly the one the
/// code falls back to. (A separate test identity in the same macOS account is not built: macOS can route
/// a test ID to the release keyboard; `testSourceOwnershipIsExact` covers that.)
final class BuildScriptIdentityTests: XCTestCase {
    func testBuildScriptWritesTheReleaseIdentity() throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/build.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        var values: [String: [String]] = [:]
        let re = try NSRegularExpression(pattern: #"(?<![A-Za-z_])([A-Z_]+)="([^"]*)""#)
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            values[String(text[Range(m.range(at: 1), in: text)!]), default: []].append(String(text[Range(m.range(at: 2), in: text)!]))
        }
        let expected = ["NAME": "Bornolipi", "APP_ID": "io.github.meheduz.Bornolipi", "IME_ID": KeyboardIdentity.releaseBundleID,
                        "CONNECTION": "Bornolipi_Connection", "DATA_FOLDER": "Bornolipi", "IME_BUNDLE": "BornolipiKeyboard.app",
                        "IME_EXEC": "BornolipiKeyboard"]
        for (key, value) in expected {
            XCTAssertEqual(values[key], [value], "\(key) is assigned once, to the release value")
        }
        let fallback = KeyboardIdentity.resolve([:], mainBundleID: nil, mainBundleName: "Bornolipi.app")
        XCTAssertEqual(fallback.id, expected["IME_ID"])
        XCTAssertEqual(fallback.bundle, expected["IME_BUNDLE"])
        XCTAssertEqual(fallback.dataFolder, expected["DATA_FOLDER"])
    }
}
