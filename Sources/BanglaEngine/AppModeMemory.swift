import Foundation

/// Remembers Bangla or English per app, for users who turn that on. Only apps where the user
/// switched mode are stored (by bundle identifier, never anything typed), newest first, at most
/// `capacity` of them. Apps without an identifier are never remembered.
public struct AppModeMemory: Codable, Equatable {
    public static let capacity = 100
    /// Newest first: (bundle identifier, Bangla?).
    public private(set) var entries: [Entry] = []

    public struct Entry: Codable, Equatable {
        public let app: String
        public let bangla: Bool
    }

    public init() {}

    /// The remembered mode for `app`, or nil when there is none (use the default start mode).
    public func mode(for app: String?) -> Bool? {
        guard let app = AppModeMemory.identifier(app) else { return nil }
        return entries.first { $0.app == app }?.bangla
    }

    /// Records the mode the user chose in `app`.
    public mutating func record(_ bangla: Bool, for app: String?) {
        guard let app = AppModeMemory.identifier(app) else { return }
        entries.removeAll { $0.app == app }
        entries.insert(Entry(app: app, bangla: bangla), at: 0)
        if entries.count > AppModeMemory.capacity { entries.removeLast(entries.count - AppModeMemory.capacity) }
    }

    public mutating func removeAll() { entries = [] }

    /// What to do when IMK activates the keyboard for `app` (it does so on every focus change):
    /// the mode to switch to, or nil to leave the current mode alone. Only a switch to a different,
    /// identifiable app changes the mode, so focus changes inside an app keep the user's choice.
    public func modeOnActivation(of app: String?, lastApp: String?, startInBangla: Bool) -> Bool? {
        guard let id = AppModeMemory.identifier(app), id != lastApp else { return nil }
        return mode(for: id) ?? startInBangla
    }

    /// A usable bundle identifier: reverse-DNS characters only, of a sane length.
    public static func identifier(_ app: String?) -> String? {
        guard let app, (3...200).contains(app.count), app.contains("."),
              app.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }) else { return nil }
        return app
    }
}
