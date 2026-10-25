import AppKit
import InstallKit

/// State of the setup assistant and the status screen. It looks at macOS once a second, so the
/// assistant moves on by itself when the user adds the keyboard in System Settings.
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, install, enable, tryIt, done }

    @Published var step: Step = .welcome
    @Published private(set) var health: Keyboard.Health = .notInstalled
    @Published private(set) var isSelected = false
    /// Whether System Settings' list of keyboards to add includes Bornolipi (nil: cannot tell).
    @Published private(set) var listIncludesBornolipi: Bool?
    @Published private(set) var working = false
    @Published var error: String?
    /// The new keyboard is installed and waits for the running one to finish (see KeyboardRestart).
    @Published private(set) var keyboardRestartPending = false
    @Published var setupComplete: Bool {
        didSet { if !previewing { UserDefaults.standard.set(setupComplete, forKey: "setupComplete") } }
    }

    /// The keyboard this app carries (Contents/Resources/BornolipiKeyboard.app).
    let bundled: URL?
    let updates = UpdateChecker.shared
    private var timer: Timer?
    /// Set while showing one screen for a screenshot: the step does not move on by itself.
    private(set) var previewing = false

    init() {
        let env = ProcessInfo.processInfo.environment["BORNOLIPI_KEYBOARD_BUNDLE"].map { URL(fileURLWithPath: $0) }
        let inside = Bundle.main.resourceURL?.appendingPathComponent(Keyboard.bundleName)
        bundled = env ?? inside.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        setupComplete = UserDefaults.standard.bool(forKey: "setupComplete")
        refresh()
        // Reopened (for example after logging out to make macOS list the keyboard): continue where it stopped.
        if !setupComplete, health == .notEnabled { step = .enable }
        // Screenshots of one screen: BORNOLIPI_PREVIEW_STEP=welcome|install|enable|tryIt|done|home.
        // Nothing is saved while previewing, so screenshots never change the real app's state.
        if let preview = ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_STEP"] {
            previewing = true
            if preview == "home" { setupComplete = true } else if let s = Step.allCases.first(where: { "\($0)" == preview }) {
                setupComplete = false; step = s
            }
        }
        if setupComplete && health != .ready && ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_STEP"] == nil { setupComplete = false }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        health = Keyboard.health(available: bundled)
        isSelected = Keyboard.isSelected
        listIncludesBornolipi = KeyboardList.includesBornolipi
        guard !previewing else { return }
        if step == .install, health == .notEnabled || health == .ready { step = health == .ready ? .tryIt : .enable }
        if step == .enable, health == .ready { step = .tryIt }
        // The keyboard went missing or broke while waiting: go back and install it again.
        if step == .enable, health != .notEnabled, health != .ready { step = .install }
    }

    /// Install, update and repair are the same operation: put this app's keyboard in place.
    func install() {
        guard let bundled else { error = Keyboard.Failure.missingPackage.localizedDescription; return }
        working = true
        error = nil
        Task.detached {
            let failure: String?
            do { try Keyboard.install(from: bundled); failure = nil } catch { failure = error.localizedDescription }
            await MainActor.run {
                self.working = false
                self.error = failure
                self.refresh()
            }
            guard failure == nil else { return }
            let outcome = await KeyboardRestart.request(.whenSafe)
            await MainActor.run { self.keyboardRestartPending = outcome == .waiting || outcome == .noAnswer }
        }
    }

    /// Removes the keyboard off the main thread; `done` gets true on success. The status screen
    /// stays up (so its confirmation shows) until the user closes it.
    func uninstall(removeData: Bool, done: @escaping (Bool) -> Void) {
        guard !working else { error = "Please wait for the current installation to finish."; done(false); return }
        working = true
        error = nil
        Task.detached {
            let failure: String?
            do { try Keyboard.uninstall(removeData: removeData); failure = nil } catch { failure = error.localizedDescription }
            await MainActor.run {
                self.working = false
                self.error = failure.map { "Bornolipi could not be removed: \($0)" }
                self.refresh()
                done(failure == nil)
            }
        }
    }

    func useBornolipiNow() {
        if !Keyboard.select() { error = "Choose Bornolipi from the keyboard menu (ব) in the menu bar instead." }
        refresh()
    }

    /// Only from a button the user clicked. The keyboard commits any unfinished word, then quits; a
    /// keyboard too old to answer is asked to quit the standard way (it commits when it terminates).
    func restartKeyboard() {
        Task {
            if await KeyboardRestart.request(.now) == .noAnswer { Keyboard.stopKeyboard() }
            keyboardRestartPending = false
            Keyboard.select()
        }
    }

    static let reportURL = URL(string: "https://github.com/meheduz/Bornolipi/issues/new")!

    // MARK: Where this app is running from

    /// Opened straight from the disk image (or from a quarantined download, which macOS runs from a
    /// temporary copy). The app still works, but keeping it in Applications makes updates simpler.
    var runningFromDiskImage: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Copies the app to /Applications (or ~/Applications if that is not allowed), opens the copy
    /// and quits this one.
    func moveToApplications() {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let name = source.lastPathComponent
        let targets = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for dir in targets {
            let dest = dir.appendingPathComponent(name)
            if Bundle.main.bundlePath.contains("/AppTranslocation/") && fm.fileExists(atPath: dest.path) {
                // macOS runs a downloaded app from a temporary copy until it has been opened from its
                // folder once; the real app may already be in Applications. Never replace it from here.
                error = "Bornolipi is already in \(dir.path). Quit Bornolipi and open it from that folder."
                return
            }
            guard dest.resolvingSymlinksInPath() != source else { return }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Copy completely first; an existing copy is only replaced once the new one is whole.
                let stagingDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dest, create: true)
                defer { try? fm.removeItem(at: stagingDir) }
                let staged = stagingDir.appendingPathComponent(name)
                try fm.copyItem(at: source, to: staged)
                if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: staged) } else { try fm.moveItem(at: staged, to: dest) }
                NSWorkspace.shared.openApplication(at: dest, configuration: NSWorkspace.OpenConfiguration()) { app, openError in
                    DispatchQueue.main.async {
                        if app != nil && openError == nil { NSApp.terminate(nil) } else {
                            self.error = "Bornolipi was copied to \(dir.path) but could not be opened there. Open it from that folder."
                        }
                    }
                }
                return
            } catch {
                continue
            }
        }
        error = "Bornolipi could not be copied to Applications. Drag it there from the disk image instead."
    }

    // MARK: Diagnostics

    /// A plain-text report for support requests. It contains versions and states, nothing typed.
    var diagnostics: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let installed = Keyboard.version(of: Keyboard.installedURL)?.short ?? "none"
        let carried = bundled.flatMap(Keyboard.version(of:))?.short ?? "none"
        var arch = utsname()
        uname(&arch)
        let machine = withUnsafeBytes(of: &arch.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return """
        Bornolipi diagnostic report
        macOS: \(os) (\(machine))
        App: \(app) at \(Bundle.main.bundlePath)\(runningFromDiskImage ? " (running from the disk image)" : "")
        Keyboard carried by the app: \(carried)
        Keyboard installed: \(installed) at \(Keyboard.installedURL.path)
        State: \(health.summary)
        Keyboard list in System Settings includes Bornolipi: \(listIncludesBornolipi.map { $0 ? "yes" : "no" } ?? "unknown")
        Keyboard copy marked as downloaded: \(Keyboard.installedCopyIsQuarantined ? "yes" : "no")
        In use now: \(isSelected ? "yes" : "no")
        """
    }
}

extension Keyboard.Health {
    var summary: String {
        switch self {
        case .notInstalled: return "not installed"
        case .damaged(let why): return "damaged (\(why))"
        case .newerInstalled(let a, let b): return "version \(a) installed, newer than this app's \(b)"
        case .outdated(let a, let b): return a == b ? "an older build of \(a) is installed" : "version \(a) installed, \(b) available"
        case .notRegistered: return "installed but not registered with macOS"
        case .notEnabled: return "installed, not yet added in System Settings"
        case .ready: return "ready"
        }
    }
}
