import XCTest
@testable import InstallKit

final class MemoryStore: UpdatePreferenceStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class UpdateServiceTests: XCTestCase {
    private let current = Keyboard.Version(short: "0.1.0", build: 1)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var requests: [URLRequest] = []

    private func release(_ tag: String, notes: String = "Fixes") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": "https://github.com/meheduz/Bornolipi/releases/tag/\(tag)",
                                                     "draft": false, "prerelease": false, "body": notes])
    }
    private func service(_ store: MemoryStore, _ reply: @escaping () throws -> (Data, Int)) -> UpdateService {
        UpdateService(current: current, store: store, fetch: { [unowned self] r in self.requests.append(r); return try reply() },
                      now: { [unowned self] in self.clock })
    }

    // Preferences

    func testAutomaticChecksAreOnForNewInstallations() {
        XCTAssertTrue(service(MemoryStore()) { (Data(), 200) }.automaticChecks)
    }

    func testSavedChoicesAreKept() {
        let off = MemoryStore(); off.values[UpdateService.Keys.automatic] = false
        XCTAssertFalse(service(off) { (Data(), 200) }.automaticChecks, "a user who turned checks off stays off")
        let on = MemoryStore(); on.values[UpdateService.Keys.automatic] = true
        XCTAssertTrue(service(on) { (Data(), 200) }.automaticChecks)
        let s = service(MemoryStore()) { (Data(), 200) }
        s.automaticChecks = false
        XCTAssertFalse(s.automaticChecks)
    }

    func testDisabledMeansNeverDue() {
        let store = MemoryStore(); store.values[UpdateService.Keys.automatic] = false
        XCTAssertFalse(service(store) { (Data(), 200) }.automaticCheckIsDue)
    }

    // Timing

    func testAtMostOnceEvery24Hours() async {
        let store = MemoryStore()
        let s = service(store) { (self.release("v0.1.0"), 200) }
        XCTAssertTrue(s.automaticCheckIsDue, "first launch")
        _ = await s.check()
        XCTAssertFalse(s.automaticCheckIsDue, "right after a check")
        clock += 23 * 3600
        XCTAssertFalse(s.automaticCheckIsDue)
        clock += 3600
        XCTAssertTrue(s.automaticCheckIsDue, "24 hours later")
    }

    func testAFailedCheckAlsoWaits24Hours() async {
        let store = MemoryStore()
        let s = service(store) { throw URLError(.notConnectedToInternet) }
        _ = await s.check()
        XCTAssertFalse(s.automaticCheckIsDue, "offline does not mean retrying at every launch")
    }

    func testClockSetBackDoesNotBlockChecks() {
        let store = MemoryStore(); store.values[UpdateService.Keys.lastCheck] = clock.timeIntervalSince1970 + 1000
        XCTAssertTrue(service(store) { (Data(), 200) }.automaticCheckIsDue)
    }

    // Version detection

    func testNewerReleaseIsAnnounced() async {
        let s = service(MemoryStore()) { (self.release("v0.2.0", notes: "New words"), 200) }
        guard case .available(let r, let announce) = await s.check() else { return XCTFail() }
        XCTAssertEqual(r.version, "0.2.0")
        XCTAssertEqual(r.notes, "New words")
        XCTAssertEqual(r.page.absoluteString, "https://github.com/meheduz/Bornolipi/releases/tag/v0.2.0")
        XCTAssertTrue(announce)
    }

    func testSemanticVersionComparison() async {
        for (tag, newer) in [("v0.1.0", false), ("v0.0.9", false), ("v0.1.1", true), ("v0.10.0", true), ("v1.0.0", true), ("0.2.0", true)] {
            let outcome = await service(MemoryStore()) { (self.release(tag), 200) }.check()
            if newer { guard case .available = outcome else { return XCTFail(tag) } } else { XCTAssertEqual(outcome, .upToDate, tag) }
        }
    }

    // Later

    func testLaterSilencesThatVersionOnly() async {
        let store = MemoryStore()
        var tag = "v0.2.0"
        let s = service(store) { (self.release(tag), 200) }
        guard case .available(let r, true) = await s.check() else { return XCTFail() }
        s.remindLater(r)
        guard case .available(_, let again) = await s.check() else { return XCTFail() }
        XCTAssertFalse(again, "the same version is not announced again")
        tag = "v0.3.0"
        guard case .available(_, let newer) = await s.check() else { return XCTFail() }
        XCTAssertTrue(newer, "a newer version is")
    }

    // Failures

    func testFailuresAreReportedNotThrown() async {
        let offline = await service(MemoryStore()) { throw URLError(.notConnectedToInternet) }.check()
        XCTAssertEqual(offline, .failed(.offline))
        let missing = await service(MemoryStore()) { (Data(#"{"message":"Not Found"}"#.utf8), 404) }.check()
        XCTAssertEqual(missing, .noRelease, "an unpublished project is not an error")
        let server = await service(MemoryStore()) { (Data(), 503) }.check()
        XCTAssertEqual(server, .failed(.server(503)))
        let garbage = await service(MemoryStore()) { (Data("<html>".utf8), 200) }.check()
        XCTAssertEqual(garbage, .failed(.invalidMetadata))
        let foreign = await service(MemoryStore()) {
            (try! JSONSerialization.data(withJSONObject: ["tag_name": "v9.0.0", "html_url": "https://evil.example/x"]), 200)
        }.check()
        XCTAssertEqual(foreign, .failed(.invalidMetadata), "only this project's GitHub release pages are accepted")
    }

    // Privacy

    func testRequestCarriesNoIdentifiers() async {
        _ = await service(MemoryStore()) { (self.release("v0.1.0"), 200) }.check()
        let r = requests.first!
        XCTAssertEqual(r.url, ReleaseFeed.api)
        XCTAssertEqual(r.httpMethod ?? "GET", "GET")
        XCTAssertNil(r.httpBody)
        XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertEqual(Set(r.allHTTPHeaderFields?.keys ?? [:].keys), ["Accept", "User-Agent"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), "Bornolipi")
        XCTAssertNil(r.url?.query)
    }

    /// Found by audit: an offline automatic check used to erase a still-valid "update available".
    func testQuietFailureKeepsWhatWasShown() {
        enum Shown: Equatable { case idle, checking, available(String), upToDate }
        XCTAssertEqual(UpdateService.displayAfterQuietFailure(before: Shown.available("0.2.0"), checking: .checking, idle: .idle), .available("0.2.0"))
        XCTAssertEqual(UpdateService.displayAfterQuietFailure(before: Shown.upToDate, checking: .checking, idle: .idle), .upToDate)
        XCTAssertEqual(UpdateService.displayAfterQuietFailure(before: Shown.idle, checking: .checking, idle: .idle), .idle)
        XCTAssertEqual(UpdateService.displayAfterQuietFailure(before: Shown.checking, checking: .checking, idle: .idle), .idle)
    }
}
