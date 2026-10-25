#if canImport(Carbon) && canImport(AppKit)
import XCTest
@testable import InstallKit

final class VersionTests: XCTestCase {
    func v(_ s: String, _ b: Int = 0) -> Keyboard.Version { Keyboard.Version(short: s, build: b) }

    func testOrdering() {
        XCTAssertLessThan(v("0.1.0"), v("0.2.0"))
        XCTAssertLessThan(v("0.9"), v("0.10"))
        XCTAssertLessThan(v("1.0"), v("1.0.1"))
        XCTAssertLessThan(v("1.0", 3), v("1.0", 4))
        XCTAssertFalse(v("1.0.0") < v("1.0"))
    }

    func testDamageDetection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ik-\(UUID().uuidString)/X.app")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        XCTAssertNotNil(Keyboard.problem(with: dir), "missing bundle")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "com.example.other"] as NSDictionary).write(to: dir.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(Keyboard.problem(with: dir), "A different program is installed in its place.")
    }
}
#endif

#if canImport(Carbon) && canImport(AppKit)
final class KeyboardListTests: XCTestCase {
    func testDetectsTheModeIDInTheCacheBytes() {
        XCTAssertTrue(KeyboardList.contains(Data("\0\u{1}io.github.meheduz.inputmethod.Bornolipi.Phonetic\0".utf8), Keyboard.modeID))
        XCTAssertFalse(KeyboardList.contains(Data("io.example.inputmethod.Other.Phonetic".utf8), Keyboard.modeID))
    }
}
#endif

final class KeyboardListFileTests: XCTestCase {
    func testListFileIsReadNotRequired() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let list = dir.appendingPathComponent(KeyboardList.listFile)
        XCTAssertNil(KeyboardList.includesBornolipi(listAt: list), "no list yet: cannot tell")
        try Data("\0io.example.inputmethod.Other.Phonetic\0".utf8).write(to: list)
        XCTAssertEqual(KeyboardList.includesBornolipi(listAt: list), false, "a stale list is reported as missing Bornolipi")
        try Data("\0io.github.meheduz.inputmethod.Bornolipi.Phonetic\0".utf8).write(to: list)
        XCTAssertEqual(KeyboardList.includesBornolipi(listAt: list), true)
    }

    func testOnlyTheModeCounts() {
        // The input method's own ID can be listed without its mode; only the mode can be added.
        XCTAssertFalse(KeyboardList.contains(Data("io.github.meheduz.inputmethod.Bornolipi\0".utf8), Keyboard.modeID))
    }
}
