#if canImport(InputMethodKit)
import Foundation
import Combine
import BanglaEngine

/// Process-wide engine: one dictionary, one set of settings, one Bangla/English mode, and the user's
/// own data (personal dictionary and learned choices), kept in ~/Library/Application Support/Bornolipi.
final class Engine {
    static let shared = Engine()

    let suggester: Suggester?
    private(set) var isBangla: Bool
    private var cancellable: AnyCancellable?
    let wordsFile = UserDataFile<[String]>(url: AppInfo.supportDirectory.appendingPathComponent("words.json"), format: "bornolipi.words")

    private init() {
        let store = SettingsStore.shared
        isBangla = store.settings.startInBangla
        let selections = SelectionStore(url: AppInfo.supportDirectory.appendingPathComponent("selections.json"))
        do {
            let s = try Suggester(dataDirectory: AppInfo.dataDirectory, settings: store.settings, selections: selections)
            if let words = wordsFile.load() { s.setUserWords(words) }
            s.onDictionaryReady = { InputController.active?.dictionaryBecameReady() }
            suggester = s
            cancellable = store.$settings.sink { [weak s] new in s?.settings = new }
        } catch {
            NSLog("Bornolipi: could not load data from \(AppInfo.dataDirectory.path): \(error)")
            suggester = nil
        }
    }

    /// Switches Bangla/English; with per-app memory on, remembers the choice for `app`.
    func toggleMode(in app: String? = nil) {
        isBangla.toggle()
        if SettingsStore.shared.settings.rememberModePerApp { AppModes.shared.record(isBangla, for: app) }
    }

    /// An app became active: with per-app memory on, use its remembered mode (or the start mode).
    /// Only a switch to a different, identifiable app changes the mode: IMK also activates on
    /// every focus change inside an app, which must not undo a choice the user just made there.
    func appActivated(_ app: String?) {
        let settings = SettingsStore.shared.settings
        guard settings.rememberModePerApp,
              let mode = AppModes.shared.memory.modeOnActivation(of: app, lastApp: lastActivatedApp, startInBangla: settings.startInBangla)
        else { return }
        lastActivatedApp = AppModeMemory.identifier(app)
        isBangla = mode
    }
    private var lastActivatedApp: String?

    // MARK: User data

    var userWords: [String] { suggester?.userWords ?? [] }

    func setUserWords(_ words: [String]) {
        guard let suggester else { return }
        suggester.setUserWords(words)
        if suggester.userWords.isEmpty { wordsFile.remove() } else { wordsFile.save(suggester.userWords) }
    }

    /// Problems with saved data that the user should know about (shown in Settings).
    var dataNotices: [String] {
        [wordsFile.state, suggester?.selections.file?.state].compactMap { (state: UserDataState?) -> String? in
            switch state {
            case .recovered(let copy)?: return "A damaged data file was replaced. The original was kept as \(copy.lastPathComponent) in \(copy.deletingLastPathComponent().path)."
            case .protected(let reason)?: return "\(reason). It has been left unchanged, so changes made now are not saved."
            default: return nil
            }
        }
    }

    var learnedChoices: [String: String] { suggester?.selections.all ?? [:] }
    func forgetChoice(_ typed: String) { suggester?.selections.remove(typed) }
    func forgetLearnedChoices() { suggester?.selections.removeAll() }

    func backup() -> UserBackup {
        UserBackup(settings: SettingsStore.shared.settings, words: userWords, learned: learnedChoices)
    }

    func restore(_ backup: UserBackup) {
        SettingsStore.shared.settings = backup.settings
        setUserWords(backup.words)
        if backup.learned.isEmpty { forgetLearnedChoices() } else { suggester?.selections.replaceAll(backup.learned) }
    }

    /// Back to a fresh install: default settings, no personal words, nothing learned.
    func resetAll() {
        restore(UserBackup(settings: EngineSettings(), words: [], learned: [:]))
    }
}

/// Per-app modes, kept in the keyboard's preferences on this Mac only.
final class AppModes {
    static let shared = AppModes()
    private static let key = "appModes.v1"
    private(set) var memory: AppModeMemory

    private init() {
        memory = UserDefaults.standard.data(forKey: AppModes.key).flatMap { try? JSONDecoder().decode(AppModeMemory.self, from: $0) } ?? AppModeMemory()
    }

    func record(_ bangla: Bool, for app: String?) {
        memory.record(bangla, for: app)
        save()
    }

    func forgetAll() {
        memory.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: AppModes.key) }
    }
}
#endif
