import XCTest
@testable import BanglaEngine

final class UserDataFileTests: XCTestCase {
    private var dir: URL!
    private var url: URL { dir.appendingPathComponent("words.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("UserDataFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func file() -> UserDataFile<[String]> { UserDataFile(url: url, format: "bornolipi.words") }
    private func siblings() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() }

    func testMissingFileLoadsNothingAndCanSave() {
        let f = file()
        XCTAssertNil(f.load())
        XCTAssertEqual(f.state, .missing)
        XCTAssertTrue(f.save(["আমি"]))
        XCTAssertEqual(file().load(), ["আমি"])
    }

    func testRoundTripUsesVersionedEnvelope() throws {
        XCTAssertTrue(file().save(["বাংলা", "ভাষা"]))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(json["format"] as? String, "bornolipi.words")
        XCTAssertEqual(json["version"] as? Int, 2)
        let f = file()
        XCTAssertEqual(f.load(), ["বাংলা", "ভাষা"])
        XCTAssertEqual(f.state, .loaded)
    }

    func testLegacyPlainFileMigratesAndKeepsBackup() throws {
        let legacy = try JSONEncoder().encode(["পুরনো"])
        try legacy.write(to: url)
        let f = file()
        XCTAssertEqual(f.load(), ["পুরনো"])
        XCTAssertEqual(f.state, .migrated(fromVersion: 1))
        XCTAssertTrue(f.save(["পুরনো", "নতুন"]))
        XCTAssertEqual(try Data(contentsOf: f.backupURL), legacy, "the plain file is kept as the backup")
        XCTAssertEqual(file().load(), ["পুরনো", "নতুন"])
    }

    func testDamagedFileIsCopiedBeforeItCanBeReplaced() throws {
        let damaged = Data("[\"আমি\", \"তুমি".utf8)   // truncated
        try damaged.write(to: url)
        let f = file()
        XCTAssertNil(f.load())
        guard case .recovered(let copy) = f.state else { return XCTFail("expected recovered, got \(f.state)") }
        XCTAssertEqual(try Data(contentsOf: copy), damaged)
        XCTAssertEqual(try Data(contentsOf: url), damaged, "the original is untouched until a save")
        XCTAssertTrue(f.save(["নতুন"]))
        XCTAssertEqual(try Data(contentsOf: copy), damaged, "the copy survives the save")
        XCTAssertEqual(file().load(), ["নতুন"])
    }

    func testDamagedFileIsNeverWrittenWhenNoCopyCanBeMade() throws {
        let damaged = Data("not json".utf8)
        try damaged.write(to: url)
        // A read-only folder: the copy cannot be written, so the original must stay the only copy.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let f = file()
        XCTAssertNil(f.load())
        guard case .protected = f.state else { return XCTFail("expected protected, got \(f.state)") }
        XCTAssertFalse(f.save(["x"]))
        XCTAssertFalse(f.remove())
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testFileFromNewerVersionIsNeverOverwritten() throws {
        let newer = Data(#"{"format":"bornolipi.words","version":99,"payload":{"words":["ভবিষ্যৎ"]}}"#.utf8)
        try newer.write(to: url)
        let f = file()
        XCTAssertNil(f.load())
        guard case .protected = f.state else { return XCTFail("expected protected, got \(f.state)") }
        XCTAssertFalse(f.save(["x"]))
        XCTAssertEqual(try Data(contentsOf: url), newer)
        XCTAssertEqual(try siblings(), ["words.json"], "no copies are made of a file that is fine, only newer")
    }

    func testBackupIsTakenOncePerSession() throws {
        XCTAssertTrue(file().save(["এক"]))
        let f = file()
        _ = f.load()
        XCTAssertTrue(f.save(["এক", "দুই"]))
        XCTAssertTrue(f.save(["এক", "দুই", "তিন"]))
        let backup = UserDataFile<[String]>(url: f.backupURL, format: "bornolipi.words")
        XCTAssertEqual(backup.load(), ["এক"], "the backup is the file as it was when the session started")
    }

    func testClearingRemovesFileButKeepsBackup() throws {
        XCTAssertTrue(file().save(["এক"]))
        let f = file()
        _ = f.load()
        XCTAssertTrue(f.remove())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(UserDataFile<[String]>(url: f.backupURL, format: "bornolipi.words").load(), ["এক"])
    }

    func testSelectionStoreMigratesLegacyChoices() throws {
        let sel = dir.appendingPathComponent("selections.json")
        try JSONEncoder().encode(["ami": "আমি"]).write(to: sel)
        let store = SelectionStore(url: sel)
        XCTAssertEqual(store["ami"], "আমি")
        store.record("tumi", "তুমি")
        XCTAssertEqual(SelectionStore(url: sel).all, ["ami": "আমি", "tumi": "তুমি"])
    }
}

/// Harder failure cases for user data: permissions, concurrency, full disks, older readers.
final class UserDataFileFailureTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("UserDataFileFailureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
    private func file(_ name: String = "words.json") -> UserDataFile<[String]> {
        UserDataFile(url: dir.appendingPathComponent(name), format: "bornolipi.words")
    }

    func testReadOnlyFolderKeepsDataAndReportsFailure() throws {
        let f = file()
        XCTAssertTrue(f.save(["এক"]))
        let before = try Data(contentsOf: f.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertFalse(f.save(["এক", "দুই"]), "an atomic write needs the folder; failure is reported")
        XCTAssertEqual(try Data(contentsOf: f.url), before)
        XCTAssertFalse(f.remove())
        XCTAssertEqual(try Data(contentsOf: f.url), before)
    }

    func testReadOnlyFileStillReadable() throws {
        let f = file()
        XCTAssertTrue(f.save(["এক"]))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: f.url.path)
        let g = file()
        XCTAssertEqual(g.load(), ["এক"])
        // An atomic write replaces the directory entry, which a read-only file does not prevent.
        XCTAssertTrue(g.save(["এক", "দুই"]))
        XCTAssertEqual(file().load(), ["এক", "দুই"])
    }

    func testUnreadableFileWithoutPermissionIsProtected() throws {
        let f = file()
        XCTAssertTrue(f.save(["এক"]))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.url.path) }
        let g = file()
        XCTAssertNil(g.load())
        guard case .protected = g.state else { return XCTFail("expected protected, got \(g.state)") }
        XCTAssertFalse(g.save(["x"]), "a file we cannot read is never replaced")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.url.path)
        XCTAssertEqual(file().load(), ["এক"])
    }

    func testConcurrentWritersAlwaysLeaveAValidFile() {
        let a = file(), b = file()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            _ = (i % 2 == 0 ? a : b).save((0...(i % 17)).map { "শব্দ\($0)" })
        }
        let reader = file()
        XCTAssertNotNil(reader.load(), "whichever write landed last, the file is complete")
        XCTAssertEqual(reader.state, .loaded)
    }

    func testOlderPlainReaderCannotReadNewFormat() throws {
        // Documents the one-way migration: a pre-versioning reader sees version 2 as unreadable.
        // Released versions all use UserDataFile, so this only affects development builds.
        XCTAssertTrue(file().save(["এক"]))
        XCTAssertNil(try? JSONDecoder().decode([String].self, from: Data(contentsOf: dir.appendingPathComponent("words.json"))))
    }

    func testLargePersonalDictionaryRoundTrips() {
        let words = (0..<50_000).map { "শব্দ\($0)" }
        XCTAssertTrue(file().save(words))
        XCTAssertEqual(file().load()?.count, 50_000)
    }

    func testEmptyAndWhitespaceFilesAreTreatedAsDamagedNotEmpty() throws {
        for (i, content) in ["", "   \n", "null", "{}"].enumerated() {
            let url = dir.appendingPathComponent("w\(i).json")
            try Data(content.utf8).write(to: url)
            let f = UserDataFile<[String]>(url: url, format: "bornolipi.words")
            XCTAssertNil(f.load())
            guard case .recovered = f.state else { return XCTFail("\(content.debugDescription): \(f.state)") }
        }
    }

    /// D1: loading a damaged file again reuses its verified copy instead of making another.
    func testRepeatedLoadsOfDamagedFileReuseOneCopy() throws {
        let url = dir.appendingPathComponent("words.json")
        let damaged = Data("[\"এক".utf8)
        try damaged.write(to: url)
        var states: [UserDataState] = []
        for _ in 0..<5 { let f = file(); XCTAssertNil(f.load()); states.append(f.state) }
        let copies = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".unreadable-") }
        XCTAssertEqual(copies.count, 1, "one copy, however often the file is loaded")
        for st in states { guard case .recovered = st else { return XCTFail("\(st)") } }
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(copies[0])), damaged)
        XCTAssertEqual(try Data(contentsOf: url), damaged, "the original stays until a save")
    }

    /// D1: a different damaged version gets its own copy; earlier copies are never overwritten.
    func testDifferentDamageGetsItsOwnCopy() throws {
        let url = dir.appendingPathComponent("words.json")
        try Data("[\"এক".utf8).write(to: url)
        _ = file().load()
        try Data("[\"দুই".utf8).write(to: url)
        _ = file().load()
        let copies = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".unreadable-") }.sorted()
        XCTAssertEqual(copies.count, 2)
        let contents = try copies.map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
        XCTAssertEqual(Set(contents), ["[\"এক", "[\"দুই"])
    }

    /// D2: only abandoned temporary files of an atomic write are removed, and only when old.
    func testAbandonedTemporaryFilesAreCleanedUpSafely() throws {
        XCTAssertTrue(file().save(["এক"]))
        let fm = FileManager.default
        let old = Date().addingTimeInterval(-3600)
        let names = ["words.json.sb-c08bef06-6IlFK1",   // abandoned, old: removed
                     "words.json.sb-a1b2c3d4-ZZZZZZ",   // abandoned but recent: kept (could be in use)
                     "words.json.sb-notatemp",          // not Foundation's pattern: kept
                     "words.json.backup.sb-c08bef06-6IlFK1", // another file's temporary: kept
                     "notes.txt"]
        for n in names { try Data("x".utf8).write(to: dir.appendingPathComponent(n)) }
        for n in [names[0], names[2], names[3], names[4]] {
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent(n).path)
        }
        XCTAssertEqual(file().load(), ["এক"])
        let left = Set(try fm.contentsOfDirectory(atPath: dir.path))
        XCTAssertFalse(left.contains(names[0]))
        for n in names.dropFirst() { XCTAssertTrue(left.contains(n), "\(n) kept") }
        XCTAssertTrue(UserDataFile<[String]>.isAtomicTemporaryName("c08bef06-6IlFK1"))
        XCTAssertFalse(UserDataFile<[String]>.isAtomicTemporaryName("C08BEF06-6IlFK1"))
        XCTAssertFalse(UserDataFile<[String]>.isAtomicTemporaryName("c08bef06-6IlFK1x"))
    }

    /// D3: one instance used from many threads at once stays consistent (calls are serialized).
    func testOneInstanceFromManyThreads() {
        let f = file()
        DispatchQueue.concurrentPerform(iterations: 300) { i in
            switch i % 3 {
            case 0: _ = f.save((0...(i % 13)).map { "শব্দ\($0)" })
            case 1: _ = f.load()
            default: _ = f.canSave
            }
        }
        let reader = file()
        XCTAssertNotNil(reader.load())
        XCTAssertEqual(reader.state, .loaded)
        XCTAssertTrue(f.canSave)
    }

    func testFilesAreOwnerOnly() throws {
        let nested = dir.appendingPathComponent("support/words.json")
        let f = UserDataFile<[String]>(url: nested, format: "bornolipi.words")
        XCTAssertTrue(f.save(["এক"]))
        _ = UserDataFile<[String]>(url: nested, format: "bornolipi.words").load()
        let again = UserDataFile<[String]>(url: nested, format: "bornolipi.words")
        _ = again.load()
        XCTAssertTrue(again.save(["এক", "দুই"]))   // makes the session backup too
        func mode(_ u: URL) throws -> Int { (try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as! NSNumber).intValue }
        XCTAssertEqual(try mode(nested), 0o600)
        XCTAssertEqual(try mode(again.backupURL), 0o600)
        XCTAssertEqual(try mode(nested.deletingLastPathComponent()), 0o700)
    }

    func testAFailedBackupIsRetriedOnTheNextSave() throws {
        XCTAssertTrue(file().save(["প্রথম"]))
        let f = file()
        XCTAssertEqual(f.load(), ["প্রথম"])
        // A directory where the backup goes makes the backup write fail.
        try FileManager.default.createDirectory(at: f.backupURL, withIntermediateDirectories: false)
        XCTAssertFalse(f.save(["দ্বিতীয়"]))
        XCTAssertEqual(file().load(), ["প্রথম"], "the good file is not replaced without a backup")
        try FileManager.default.removeItem(at: f.backupURL)
        XCTAssertTrue(f.save(["দ্বিতীয়"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.backupURL.path), "the previous good file was backed up")
    }
}
