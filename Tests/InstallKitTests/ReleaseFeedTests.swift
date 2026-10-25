import XCTest
@testable import InstallKit

final class ReleaseFeedTests: XCTestCase {
    private let current = Keyboard.Version(short: "0.1.0", build: 1)
    private func doc(tag: String = "v0.2.0", url: String = "https://github.com/meheduz/Bornolipi/releases/tag/v0.2.0",
                     draft: Bool = false, pre: Bool = false, body: String = "Fixes") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": pre, "body": body])
    }

    func testNewerReleaseIsOfferedWithNotes() throws {
        let r = try ReleaseFeed.newer(than: current, from: doc())
        XCTAssertEqual(r?.version, "0.2.0")
        XCTAssertEqual(r?.notes, "Fixes")
    }

    func testSameOrOlderIsNotOffered() throws {
        XCTAssertNil(try ReleaseFeed.newer(than: current, from: doc(tag: "v0.1.0")))
        XCTAssertNil(try ReleaseFeed.newer(than: current, from: doc(tag: "0.0.9")))
    }

    func testDraftsAndPrereleasesAreNotOffered() throws {
        XCTAssertNil(try ReleaseFeed.newer(than: current, from: doc(draft: true)))
        XCTAssertNil(try ReleaseFeed.newer(than: current, from: doc(pre: true)))
    }

    func testOtherProjectsAndHostsAreRejected() {
        for url in ["https://github.com/someone/Bornolipi/releases/tag/v9.0.0", "https://evil.example/meheduz/Bornolipi/releases/x",
                    "http://github.com/meheduz/Bornolipi/releases/tag/v9.0.0", "https://github.com/meheduz/Bornolipi/archive/v9.zip"] {
            XCTAssertThrowsError(try ReleaseFeed.newer(than: current, from: doc(url: url)), url)
        }
    }

    func testMalformedVersionsAreRejected() {
        for tag in ["v1.0", "v1.0.0-beta", "v1.0.0.0", "latest", "v99999.0.0", "v1..0"] {
            XCTAssertThrowsError(try ReleaseFeed.newer(than: current, from: doc(tag: tag)), tag)
        }
        XCTAssertThrowsError(try ReleaseFeed.newer(than: current, from: Data("not json".utf8)))
    }

    func testNotesAreLimited() throws {
        let r = try ReleaseFeed.newer(than: current, from: doc(body: String(repeating: "x", count: 10_000)))
        XCTAssertEqual(r?.notes.count, ReleaseFeed.notesLimit)
    }
}
