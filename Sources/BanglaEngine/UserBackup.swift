import Foundation

/// Everything the user has customised, as one portable JSON document (Settings > About > Export).
/// Missing fields take their defaults, so older or hand-edited files still import.
public struct UserBackup: Codable, Equatable {
    public static let formatName = "bornolipi-backup"

    public var format = UserBackup.formatName
    public var version = 1
    public var settings: EngineSettings
    /// The personal dictionary.
    public var words: [String]
    /// Learned choices: typed roman word -> chosen Bangla word.
    public var learned: [String: String]

    public init(settings: EngineSettings, words: [String], learned: [String: String]) {
        self.settings = settings
        self.words = words
        self.learned = learned
    }

    enum CodingKeys: String, CodingKey { case format, version, settings, words, learned }

    public struct WrongFormat: Error, CustomStringConvertible {
        public let found: String
        public var description: String { "Not an Bornolipi backup (format: \(found))." }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        guard format == UserBackup.formatName else { throw WrongFormat(found: format.isEmpty ? "none" : format) }
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(EngineSettings.self, forKey: .settings) ?? EngineSettings()
        words = try c.decodeIfPresent([String].self, forKey: .words) ?? []
        learned = try c.decodeIfPresent([String: String].self, forKey: .learned) ?? [:]
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> UserBackup {
        try JSONDecoder().decode(UserBackup.self, from: data)
    }
}
