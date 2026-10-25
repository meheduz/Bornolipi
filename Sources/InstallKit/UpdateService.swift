import Foundation

/// Where update preferences live. UserDefaults in the app; an in-memory store in tests.
public protocol UpdatePreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: UpdatePreferenceStore {}

/// The update check's rules, without UI or networking of its own, so every decision is testable.
///
/// - Automatic checks are on unless the user turned them off (a saved choice is always kept).
/// - At most one automatic check per 24 hours, counted from the last attempt, successful or not.
/// - Only GitHub's "latest release" document for this project is read (`ReleaseFeed`); nothing is
///   downloaded or installed, and the request carries no identifiers.
/// - A version the user answered Later to is not announced again; a newer one is.
public final class UpdateService {
    public enum Keys {
        public static let automatic = "checkForUpdates"
        public static let lastCheck = "lastUpdateCheck"
        public static let dismissed = "dismissedUpdateVersion"
    }

    public static let interval: TimeInterval = 24 * 3600

    public enum Outcome: Equatable {
        /// A newer release. `announce` is false when the user already answered Later to this version.
        case available(ReleaseInfo, announce: Bool)
        case upToDate
        /// The project has no published release yet (GitHub answers 404).
        case noRelease
        /// No connection, a server error, or a document that is not one of this project's releases.
        case failed(Failure)
    }

    public enum Failure: Equatable {
        case offline, server(Int), invalidMetadata
        public var message: String {
            switch self {
            case .offline: return "Couldn't connect. Check the internet connection and try again."
            case .server: return "GitHub didn't answer as expected. Try again later."
            case .invalidMetadata: return "The release information couldn't be read. Try again later."
            }
        }
    }

    /// Returns the response body and HTTP status, or throws when there is no connection.
    public typealias Fetch = (URLRequest) async throws -> (Data, Int)

    private let store: UpdatePreferenceStore
    private let fetch: Fetch
    private let current: Keyboard.Version
    private let now: () -> Date

    public init(current: Keyboard.Version, store: UpdatePreferenceStore = UserDefaults.standard,
                fetch: @escaping Fetch = UpdateService.urlSessionFetch, now: @escaping () -> Date = Date.init) {
        self.current = current
        self.store = store
        self.fetch = fetch
        self.now = now
    }

    /// On unless the user saved Off. Existing saved choices (either way) are kept as they are.
    public var automaticChecks: Bool {
        get { store.object(forKey: Keys.automatic) as? Bool ?? true }
        set { store.set(newValue, forKey: Keys.automatic) }
    }

    /// True when automatic checks are on and the last attempt was 24 hours ago or more.
    public var automaticCheckIsDue: Bool {
        guard automaticChecks else { return false }
        guard let last = store.object(forKey: Keys.lastCheck) as? Double else { return true }
        let elapsed = now().timeIntervalSince1970 - last
        return elapsed >= UpdateService.interval || elapsed < 0   // a clock set back does not block checks forever
    }

    /// Checks now (the Check Now button, or a due automatic check).
    public func check() async -> Outcome {
        store.set(now().timeIntervalSince1970, forKey: Keys.lastCheck)
        let data: Data, status: Int
        do {
            (data, status) = try await fetch(UpdateService.request)
        } catch {
            return .failed(.offline)
        }
        switch status {
        case 200: break
        case 404: return .noRelease
        default: return .failed(.server(status))
        }
        do {
            guard let release = try ReleaseFeed.newer(than: current, from: data) else { return .upToDate }
            return .available(release, announce: store.object(forKey: Keys.dismissed) as? String != release.version)
        } catch {
            return .failed(.invalidMetadata)
        }
    }

    /// What to show after an automatic check failed quietly: whatever was shown before it started
    /// (an update found earlier stays visible), or `idle` when nothing had been shown yet.
    public static func displayAfterQuietFailure<State: Equatable>(before: State, checking: State, idle: State) -> State {
        before == checking ? idle : before
    }

    /// The user chose Later: this version is not announced again (a newer one will be).
    public func remindLater(_ release: ReleaseInfo) {
        store.set(release.version, forKey: Keys.dismissed)
    }

    /// A plain GET with no cookies, cache or identifying headers.
    public static var request: URLRequest {
        var r = URLRequest(url: ReleaseFeed.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("Bornolipi", forHTTPHeaderField: "User-Agent")
        r.httpShouldHandleCookies = false
        return r
    }

    public static let urlSessionFetch: Fetch = { request in
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
