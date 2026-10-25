import XCTest
@testable import BanglaEngine

/// E10: Shift-held capitals follow Avro's case rules; Caps Lock without Shift types lowercase.
final class UppercaseInputTests: XCTestCase {
    func testShiftAndCapsLockAreDistinct() {
        let s = ConventionalSpellingTests.suggester
        func type(_ text: String, capsLock: Bool) -> String {
            let h = InputHandler(suggester: s), f = RecordingClient()
            for k in Keys.parse(text + "{space}", capsLock: capsLock) { _ = h.handle(k, bangla: true, client: f) }
            return f.text
        }
        XCTAssertEqual(type("sust", capsLock: true), type("sust", capsLock: false), "Caps Lock alone types lowercase")
        XCTAssertEqual(type("SUST", capsLock: false), "শূশট ", "Shift-held capitals use Avro's capital rules")
        XCTAssertEqual(type("sust", capsLock: false), "সুস্ত ")
    }
}
