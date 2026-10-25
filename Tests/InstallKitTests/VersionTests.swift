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
