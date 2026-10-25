import Foundation

/// What happened when a user data file was loaded.
public enum UserDataState: Equatable {
    case missing
    case loaded
    case migrated(fromVersion: Int)
    /// Unreadable; a verified copy was kept and the file may be replaced.
    case recovered(copy: URL)
    /// Unreadable or from a newer version; it is left alone and nothing is saved.
    case protected(reason: String)
}

/// One file of the user's own data (personal words, learned choices), stored as
/// `{"format": ..., "version": 2, "payload": ...}`. Older plain files (version 1) still load.
///
/// The rules that keep data from being lost:
/// - Writes are atomic: a crash leaves the old file or the new one, never half of either.
/// - A file that cannot be read is never written over until a byte-identical copy of it exists
///   next to it (`<name>.unreadable-<date>`). If that copy cannot be made, nothing is written.
/// - A file from a newer version of Bornolipi is never written over.
/// - The first save in each session first keeps the previous good file as `<name>.backup`.
public final class UserDataFile<Payload: Codable> {
    public typealias State = UserDataState

    public static var currentVersion: Int { 2 }
    public let url: URL
    public let format: String
    public private(set) var state = State.missing
    public var canSave: Bool { if case .protected = state { return false } else { return true } }
    private var backedUp = false
    /// Load, save and remove are serialized, so callers on different threads never interleave.
    private let lock = NSLock()

    public init(url: URL, format: String) {
        self.url = url
        self.format = format
    }

    private struct Header: Codable { var format: String; var version: Int }
    private struct Envelope: Codable { var format: String; var version: Int; var payload: Payload }

    /// Reads the file. Returns nil when there is nothing usable; `state` says why.
    public func load() -> Payload? {
        lock.lock(); defer { lock.unlock() }
        removeAbandonedTemporaryFiles()
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { state = .missing; return nil }
        guard let data = try? Data(contentsOf: url) else {
            state = .protected(reason: "\(url.lastPathComponent) could not be opened")
            return nil
        }
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(Header.self, from: data), header.format == format {
            guard header.version <= Self.currentVersion else {
                state = .protected(reason: "\(url.lastPathComponent) was saved by a newer version of Bornolipi")
                return nil
            }
            if let envelope = try? decoder.decode(Envelope.self, from: data) {
                state = .loaded
                return envelope.payload
            }
        } else if let legacy = try? decoder.decode(Payload.self, from: data) {
            state = .migrated(fromVersion: 1)
            return legacy
        }
        state = keepCopy(of: data)
        return nil
    }

    /// Saves atomically. Returns false (and changes nothing) when the file is protected or the write fails.
    @discardableResult
    public func save(_ payload: Payload) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard canSave else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try backUpOnce()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Envelope(format: format, version: Self.currentVersion, payload: payload))
            try data.write(to: url, options: .atomic)
            UserDataFile.ownerOnly(url)
            if case .recovered = state {} else { state = .loaded }
            return true
        } catch {
            return false
        }
    }

    /// Deletes the file (the user cleared this data). Protected files are left alone.
    @discardableResult
    public func remove() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard canSave else { return false }
        do {
            try backUpOnce()
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            state = .missing
            return true
        } catch {
            return false
        }
    }

    public var backupURL: URL { url.appendingPathExtension("backup") }

    /// Before the first change in a session, the file as it was is kept as `<name>.backup`.
    private func backUpOnce() throws {
        guard !backedUp else { return }
        guard state == .loaded || state == .migrated(fromVersion: 1),
              let current = try? Data(contentsOf: url) else { backedUp = true; return }
        try current.write(to: backupURL, options: .atomic)
        UserDataFile.ownerOnly(backupURL)
        backedUp = true   // only once the copy exists: a failed backup is retried on the next save
    }

    /// Writes a copy of an unreadable file and reads it back. Only a verified copy makes the
    /// original replaceable; otherwise the original stays the only copy and is never written.
    /// A byte-identical copy from an earlier load is reused, so repeated loads add no copies.
    private func keepCopy(of data: Data) -> State {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".unreadable-"
        let existing = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for name in existing {
            let copy = dir.appendingPathComponent(name)
            if (try? Data(contentsOf: copy)) == data { return .recovered(copy: copy) }
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for n in 1...20 {
            let copy = dir.appendingPathComponent(prefix + stamp + (n == 1 ? "" : "-\(n)"))
            do {
                try data.write(to: copy, options: .withoutOverwriting)
                UserDataFile.ownerOnly(copy)
            } catch CocoaError.fileWriteFileExists {
                continue   // another copy already has this name; it is never overwritten
            } catch {
                return .protected(reason: "\(url.lastPathComponent) is damaged and could not be copied")
            }
            guard (try? Data(contentsOf: copy)) == data else {
                return .protected(reason: "\(url.lastPathComponent) is damaged and a copy could not be verified")
            }
            return .recovered(copy: copy)
        }
        return .protected(reason: "\(url.lastPathComponent) is damaged and could not be copied")
    }

    /// An atomic write goes through a temporary file next to the target (Foundation names it
    /// `<name>.sb-<8 hex>-<6 characters>`). If the process dies mid-write, that file stays behind;
    /// the target itself is untouched. Only files with exactly that name, at least ten minutes old
    /// (so never one being written right now), are removed. Nothing else is touched.
    private func removeAbandonedTemporaryFiles() {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".sb-"
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix(prefix) && UserDataFile.isAtomicTemporaryName(String(name.dropFirst(prefix.count))) {
            let path = dir.appendingPathComponent(name)
            guard let modified = (try? fm.attributesOfItem(atPath: path.path))?[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) > UserDataFile.abandonedAfter else { continue }
            try? fm.removeItem(at: path)
        }
    }

    static var abandonedAfter: TimeInterval { 600 }

    /// Personal words and choices are readable by their owner only (rw-------).
    public static func ownerOnly(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// "c08bef06-6IlFK1": 8 lowercase hex digits, a hyphen, 6 letters or digits.
    static func isAtomicTemporaryName(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 8, parts[1].count == 6 else { return false }
        return parts[0].allSatisfy { $0.isHexDigit && !$0.isUppercase } && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
