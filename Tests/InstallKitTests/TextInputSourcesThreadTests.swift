import XCTest
@testable import InstallKit

/// The setup app installs, updates and uninstalls off the main thread, but Text Input Sources must
/// be used on it: on macOS 27 TISCreateInputSourceList right after TISRegisterInputSource stopped the
/// app with a main-queue assertion (crash report of Update Now, 2026-10-24). Tests never register a
/// keyboard, so this checks the hop to the main thread from a background thread, without deadlock.
final class TextInputSourcesThreadTests: XCTestCase {
    func testQueriesFromABackgroundThreadRunOnTheMainThread() {
        let done = expectation(description: "background queries")
        var ranOnMain: [Bool] = []
        DispatchQueue.global().async {
            _ = Keyboard.sources()       // read-only: lists input sources
            _ = Keyboard.isSelected
            Keyboard.onMain { ranOnMain.append(Thread.isMainThread) }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(ranOnMain, [true])
    }
}
