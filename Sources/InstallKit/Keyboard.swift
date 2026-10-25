#if canImport(Carbon) && canImport(AppKit)
import AppKit
import Carbon
import Security

/// Installs, checks, repairs and removes the Bornolipi input method for the current user, using
/// only supported macOS mechanisms. macOS does not let any program switch on another developer's input
/// method, so turning it on is left to the user in System Settings; `health` detects when they have.
public enum Keyboard {
    public static var bundleID: String { KeyboardIdentity.bundleID }
    public static var modeID: String { bundleID + ".Phonetic" }
    public static var bundleName: String { KeyboardIdentity.bundleName }

    /// ~/Library/Input Methods/BornolipiKeyboard.app (per user, no administrator password needed).
    public static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
    }

    /// Personal words, learned choices and settings.
    public static var dataLocations: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Library/Application Support", isDirectory: true).appendingPathComponent(KeyboardIdentity.dataFolder, isDirectory: true),
                home.appendingPathComponent("Library/Preferences/\(bundleID).plist")]
    }

    public enum Health: Equatable {
        case notInstalled
        /// Files are missing or broken; Repair fixes it. The text says what is wrong.
        case damaged(String)
        /// An older keyboard is installed than the one this app carries.
        case outdated(installed: String, available: String)
        /// A newer keyboard is installed than the one this app carries (an old copy of the app).
        case newerInstalled(installed: String, available: String)
        /// Copied, but macOS does not know about it yet.
        case notRegistered
        /// Known to macOS but not added in System Settings.
        case notEnabled
        case ready
    }

    public struct Version: Comparable, CustomStringConvertible {
        public let short: String
        public let build: Int
        public var description: String { short }
        public init(short: String, build: Int) { self.short = short; self.build = build }
        public static func < (a: Version, b: Version) -> Bool {
            let pa = a.short.split(separator: ".").map { Int($0) ?? 0 }, pb = b.short.split(separator: ".").map { Int($0) ?? 0 }
            for i in 0..<max(pa.count, pb.count) where (i < pa.count ? pa[i] : 0) != (i < pb.count ? pb[i] : 0) {
                return (i < pa.count ? pa[i] : 0) < (i < pb.count ? pb[i] : 0)
            }
            return a.build < b.build
        }
    }

    public static func version(of bundle: URL) -> Version? {
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let short = info["CFBundleShortVersionString"] as? String else { return nil }
        return Version(short: short, build: Int(info["CFBundleVersion"] as? String ?? "") ?? 0)
    }

    // MARK: Checking

    /// What is wrong with the installed copy, if anything.
    public static func problem(with bundle: URL) -> String? {
        let fm = FileManager.default
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else {
            return "The keyboard's information file is missing."
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else { return "A different program is installed in its place." }
        guard fm.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/BornolipiKeyboard").path) else {
            return "The keyboard program is missing."
        }
        for file in ["AvroPhonetic.json", "dictionary.json", "autocorrect.json", "suffix.json"]
        where !fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/Data/\(file)").path) {
            return "The keyboard's word list is missing."
        }
        var code: SecStaticCode?
        if SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) != errSecSuccess { return "The keyboard cannot be checked." }
        if let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) != errSecSuccess {
            return "The keyboard's files have been changed or damaged."
        }
        return nil
    }

    /// The last code check, keyed by the bundle's file dates: checking the signature takes tens of
    /// milliseconds, and the app looks at the health once a second.
    private static var checked: (key: String, problem: String?)?

    private static func cachedProblem(with url: URL) -> String? {
        let fm = FileManager.default
        let key = ["", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources", "Contents/Resources/Data"].map {
            ((try? fm.attributesOfItem(atPath: url.appendingPathComponent($0).path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }.map { String($0) }.joined(separator: "|")
        if let checked, checked.key == key { return checked.problem }
        let problem = problem(with: url)
        checked = (key, problem)
        return problem
    }

    /// True if something (even a broken symbolic link) is at `url`; FileManager.fileExists follows links.
    static func entryExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    public static func health(available bundled: URL?) -> Health {
        let url = installedURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled }
        if let problem = cachedProblem(with: url) { return .damaged(problem) }
        if let bundled, let have = version(of: url), let new = version(of: bundled) {
            if have < new { return .outdated(installed: have.short, available: new.short) }
            if new < have { return .newerInstalled(installed: have.short, available: new.short) }
        }
        let found = sources()
        guard found.contains(where: { id($0) == modeID }) else { return .notRegistered }
        return isEnabled(found) ? .ready : .notEnabled
    }

    /// True while Bornolipi is the input source in use.
    public static var isSelected: Bool {
        onMain {
            let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            return KeyboardIdentity.owns(sourceID: id(s))
        }
    }

    // MARK: Changing

    public enum Failure: LocalizedError {
        case missingPackage, olderPackage, copy(String), register(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .missingPackage: return "The keyboard is missing from this app. Please download Bornolipi again."
            case .olderPackage: return "A newer Bornolipi keyboard is already installed. Download the latest Bornolipi app to repair it."
            case .copy(let why): return "The keyboard could not be copied: \(why)"
            case .register(let status): return "macOS did not accept the keyboard (error \(status)). Restarting the Mac usually helps."
            }
        }
    }

    /// Copies `bundled` into place (replacing an older or broken copy in one step, so a failure never
    /// leaves half a keyboard) and registers it. Personal data lives elsewhere and is kept.
    /// A running keyboard is not stopped: it keeps the files it already loaded, and the caller hands
    /// over with `KeyboardRestart.request(.whenSafe)` so nothing the user is typing is lost.
    public static func install(from bundled: URL) throws {
        let fm = FileManager.default
        guard problem(with: bundled) == nil else { throw Failure.missingPackage }
        let dest = installedURL
        if fm.fileExists(atPath: dest.path), let have = version(of: dest), let new = version(of: bundled), new < have {
            throw Failure.olderPackage
        }
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Staged in a temporary folder on the same volume, not in Input Methods, so an interrupted
            // copy never leaves a second keyboard where macOS looks for them.
            let stagingDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dest, create: true)
            defer { try? fm.removeItem(at: stagingDir) }
            let staging = stagingDir.appendingPathComponent(dest.lastPathComponent)
            try fm.copyItem(at: bundled, to: staging)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staging)
            } else {
                if entryExists(dest) { try fm.removeItem(at: dest) }   // a broken link in the way
                try fm.moveItem(at: staging, to: dest)
            }
        } catch {
            throw Failure.copy(error.localizedDescription)
        }
        checked = nil
        try register()
    }

    /// Tells macOS about the installed keyboard and asks it to enable it. macOS ignores the enable
    /// request for other developers' input methods (the user adds it in System Settings), but honours
    /// it on versions that allow it.
    public static func register() throws {
        try onMain(registerOnMain)
    }

    private static func registerOnMain() throws {
        let status = TISRegisterInputSource(installedURL as CFURL)
        guard status == noErr else { throw Failure.register(status) }
        let found = sources()
        if !isEnabled(found) {
            for s in found.sorted(by: { id($0) != bundleID && id($1) == bundleID }) { _ = TISEnableInputSource(s) }
        }
        // LaunchServices marks a newly registered app "launch-disabled" until it has started it once.
        // Start the keyboard in the background now (macOS would start it anyway when it is used).
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: installedURL, configuration: config)
    }

    /// Reinstalls the keyboard this app carries and registers it again.
    public static func repair(from bundled: URL) throws {
        try install(from: bundled)
    }

    /// Quits the running keyboard; macOS starts it again when it is needed.
    public static func stopKeyboard() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while running.contains(where: { !$0.isTerminated }), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        for app in running where !app.isTerminated { app.forceTerminate() }
    }

    /// Removes the keyboard and, if asked, the user's personal words, learned choices and settings.
    public static func uninstall(removeData: Bool) throws {
        onMain { for s in sources() { _ = TISDisableInputSource(s) } }
        stopKeyboard()
        let fm = FileManager.default
        if entryExists(installedURL) { try fm.removeItem(at: installedURL) }
        checked = nil
        guard removeData else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        for url in dataLocations where fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    /// Opens System Settings at Keyboard, where input sources are added.
    public static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings at Privacy & Security, where macOS shows "Open Anyway" for apps it held back.
    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
    }

    /// Quits System Settings (as Command-Q does) and opens it again at Keyboard. Its list of keyboards
    /// that can be added is read when it starts, so a keyboard registered while it was open is missing.
    public static func restartKeyboardSettings() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        for app in running { app.terminate() }
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(5)
            while running.contains(where: { !$0.isTerminated }), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.async { openKeyboardSettings() }
        }
    }

    /// Opens the keyboard's own settings window (personal words, shortcuts and so on).
    public static func openKeyboardPreferences() {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--settings"]
        config.activates = true
        NSWorkspace.shared.openApplication(at: installedURL, configuration: config)
    }

    // MARK: Text Input Sources

    /// Text Input Sources must be used on the main thread: macOS 27 stops the process (a libdispatch
    /// queue assertion) when they are called elsewhere, as from the setup app's background install.
    static func onMain<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    static func sources() -> [TISInputSource] {
        onMain {
            guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else { return [] }
            return list.filter { KeyboardIdentity.owns(sourceID: id($0)) }
        }
    }

    static func id(_ s: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    static func flag(_ s: TISInputSource, _ key: CFString) -> Bool {
        guard let p = TISGetInputSourceProperty(s, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
    }

    /// The input method itself, not just its mode, is enabled: only then can it be chosen.
    static func isEnabled(_ found: [TISInputSource]) -> Bool {
        found.contains { id($0) == bundleID && flag($0, kTISPropertyInputSourceIsEnabled) }
            && found.contains { id($0) == modeID && flag($0, kTISPropertyInputSourceIsEnabled) }
    }
}
#endif
