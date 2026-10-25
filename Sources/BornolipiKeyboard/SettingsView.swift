#if canImport(InputMethodKit)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BanglaEngine

struct SettingsView: View {
    @AppStorage("settings.tab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            DictionaryTab().tabItem { Label("Dictionary", systemImage: "character.book.closed") }.tag("dictionary")
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
            AutoCorrectTab().tabItem { Label("AutoCorrect", systemImage: "text.badge.checkmark") }.tag("autocorrect")
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }
        .frame(width: 560, height: 520)
    }
}

/// The personal dictionary and learned choices, for the views. Learning happens while the user
/// types elsewhere, so the lists are reloaded whenever a tab appears.
final class UserDataModel: ObservableObject {
    static let shared = UserDataModel()
    @Published private(set) var words: [String] = []
    @Published private(set) var learned: [(typed: String, word: String)] = []

    func reload() {
        words = Engine.shared.userWords
        learned = Engine.shared.learnedChoices.sorted { $0.key < $1.key }.map { (typed: $0.key, word: $0.value) }
    }

    func add(_ word: String) { Engine.shared.setUserWords(words + [word]); reload() }
    func remove(_ word: String) { Engine.shared.setUserWords(words.filter { $0 != word }); reload() }
    func forget(_ typed: String) { Engine.shared.forgetChoice(typed); reload() }
    func forgetAll() { Engine.shared.forgetLearnedChoices(); reload() }
}

private struct GeneralTab: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Typing") {
                Toggle("Start in Bangla mode", isOn: $store.settings.startInBangla)
                Toggle("Bangla digits (123 becomes ১২৩)", isOn: $store.settings.banglaDigits)
                Picker("Characters \u{09DC} \u{09DD} \u{09DF}", selection: $store.settings.normalization) {
                    Text("As Avro Keyboard writes them").tag(Normalization.avro)
                    Text("Unicode NFC (letter + nukta)").tag(Normalization.nfc)
                }
                Text("Both look the same. Avro's form matches text typed with Avro Keyboard; NFC is the form the web standards recommend.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Suggestions") {
                Toggle("Dictionary suggestions", isOn: $store.settings.suggestions)
                Toggle("Offer longer words that start with what I typed", isOn: $store.settings.completions)
                    .disabled(!store.settings.suggestions)
                Toggle("Suggest English loanwords (beta)", isOn: $store.settings.loanwordSuggestions)
                    .disabled(!store.settings.suggestions)
                Text("Adds up to three known words for English and informal spellings after Bornolipi's own suggestions. Space still inserts what Avro types.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Offer the typed English text as a candidate", isOn: $store.settings.includeEnglish)
                Toggle("Backspace right after an autocorrection reopens the word", isOn: $store.settings.undoAutocorrect)
                Stepper("Candidates shown: \(store.settings.maxCandidates)",
                        value: $store.settings.maxCandidates, in: 2...9)
                Stepper("Candidate text size: \(store.settings.candidateTextSize) pt",
                        value: $store.settings.candidateTextSize, in: EngineSettings.candidateTextSizes)
            }
            Section("Bangla and English") {
                Toggle("Remember Bangla or English for each app", isOn: $store.settings.rememberModePerApp)
                Text("When on, each app starts in the mode you last chose there. Only the app's identifier is kept, on this Mac.")
                    .font(.footnote).foregroundStyle(.secondary)
                if store.settings.rememberModePerApp {
                    Button("Forget Remembered Apps") { AppModes.shared.forgetAll() }
                }
            }
            Section("Learning") {
                Toggle("Remember the word I pick for what I typed", isOn: $store.settings.learnChoices)
                Text("Choices stay on this Mac, in \((AppInfo.supportDirectory.path as NSString).abbreviatingWithTildeInPath). Nothing is sent anywhere. See the Dictionary tab to review or delete them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("AutoCorrect") {
                Toggle("Replace common misspellings automatically", isOn: $store.settings.autocorrect)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DictionaryTab: View {
    @ObservedObject var data = UserDataModel.shared
    @State private var entry = ""
    @State private var confirmForget = false

    /// What "Add" would store: roman text is converted, Bangla is kept as written.
    private var preview: String {
        let t = entry.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "" }
        if t.unicodeScalars.allSatisfy({ $0.isASCII }), let s = Engine.shared.suggester {
            return s.parser.convert(t)   // the word is added because the dictionary lacks it
        }
        return t
    }

    var body: some View {
        Form {
            ForEach(Engine.shared.dataNotices, id: \.self) { notice in
                Label { Text(notice).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Section("My words") {
                HStack {
                    TextField("New word", text: $entry, prompt: Text("meheduz, or paste Bangla"))
                        .onSubmit(add)
                    Button("Add", action: add).disabled(preview.isEmpty)
                }
                if !preview.isEmpty {
                    Text("Adds: \(preview)").foregroundStyle(.secondary)
                }
                Text("Your words are suggested before dictionary words, for names and terms the dictionary lacks.")
                    .font(.footnote).foregroundStyle(.secondary)
                if data.words.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(data.words, id: \.self) { word in
                    HStack {
                        Text(word).font(.system(size: 15))
                        Spacer()
                        Button(role: .destructive) { data.remove(word) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete \(word)")
                            .buttonStyle(.borderless)
                            .help("Remove \(word)")
                    }
                }
            }
            Section("Learned choices (\(data.learned.count))") {
                if data.learned.isEmpty {
                    Text("Nothing learned yet. When you pick a candidate other than the first, it is remembered for that typed word.")
                        .foregroundStyle(.secondary)
                }
                ForEach(data.learned, id: \.typed) { item in
                    HStack {
                        Text(item.typed).font(.system(.body, design: .monospaced))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("becomes")
                        Text(item.word).font(.system(size: 15))
                        Spacer()
                        Button(role: .destructive) { data.forget(item.typed) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Forget \(item.typed)")
                            .buttonStyle(.borderless)
                            .help("Forget this choice")
                    }
                }
                if !data.learned.isEmpty {
                    Button("Forget all learned choices…") { confirmForget = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { data.reload() }
        .confirmationDialog("Forget all \(data.learned.count) learned choices?", isPresented: $confirmForget) {
            Button("Forget All", role: .destructive) { data.forgetAll() }
        }
    }

    private func add() {
        let word = preview
        guard !word.isEmpty else { return }
        data.add(word)
        entry = ""
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Switch between Bangla and English") {
                HStack {
                    ShortcutField(shortcut: $store.settings.toggleShortcut)
                    Button("Reset") { store.settings.toggleShortcut = .defaultToggle }
                }
                Text("You can also switch with the macOS input menu, or with the system shortcut for the previous input source (⌃Space by default). Click the shortcut, then press the new keys. Esc cancels.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("While typing a word") {
                keyRow("Space", "Commit the selected candidate")
                keyRow("↑ ↓", "Choose another candidate")
                keyRow("Return, Tab", "Commit and pass the key on")
                keyRow("Esc", "Keep the English text as typed")
                keyRow("Delete", "Remove the last letter")
                keyRow("⌃ Delete", "Discard the whole word")
                keyRow("Click", "Commit that candidate")
            }
        }
        .formStyle(.grouped)
    }

    private func keyRow(_ key: String, _ what: String) -> some View {
        HStack { Text(key).font(.system(.body, design: .monospaced)); Spacer(); Text(what).foregroundStyle(.secondary) }
    }
}

private struct ShortcutField: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press the new shortcut…" : shortcut.display) {
            recording ? stop() : start()
        }
        .frame(minWidth: 150)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let mods = event.modifierFlags.rawValue & Shortcut.mask
            if mods == 0 { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct AutoCorrectTab: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var typed = ""
    @State private var replacement = ""

    private var keys: [String] { store.settings.userAutocorrect.keys.sorted() }

    var body: some View {
        Form {
            Section("Add an entry") {
                TextField("When I type", text: $typed, prompt: Text("amr"))
                TextField("Treat it as", text: $replacement, prompt: Text("amar"))
                Button("Add") {
                    let t = typed.trimmingCharacters(in: .whitespaces)
                    let r = replacement.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !r.isEmpty else { return }
                    store.settings.userAutocorrect[t] = r
                    typed = ""; replacement = ""
                }
                Text("Both sides are phonetic text, for example “amr” becomes “amar”.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your entries") {
                if keys.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(keys, id: \.self) { key in
                    HStack {
                        Text(key).font(.system(.body, design: .monospaced))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("becomes")
                        Text(store.settings.userAutocorrect[key] ?? "").font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            store.settings.userAutocorrect[key] = nil
                        } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove \(key)")
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    @State private var message = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("ব").font(.system(size: 48))
                    Text("Bornolipi").font(.title2.bold())
                    Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
                    Text("Type Bangla. Naturally. A free, open-source, Avro-compatible phonetic keyboard. The keyboard never connects to the internet.")
                        .multilineTextAlignment(.center)
                    Text("Rule table, dictionary and autocorrect data come from the OpenBangla project (MPL-2.0).")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Link("Source code and license", destination: URL(string: "https://github.com/meheduz/Bornolipi")!)
                }
                .frame(maxWidth: .infinity)
            }
            Section("Backup") {
                HStack {
                    Button("Export Settings and Words…", action: export)
                    Button("Import…", action: importBackup)
                }
                Text("One file with your settings, personal words and learned choices.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset Everything…", role: .destructive) { confirmReset = true }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings and delete your personal words and learned choices?",
                            isPresented: $confirmReset) {
            Button("Reset Everything", role: .destructive) {
                Engine.shared.resetAll()
                UserDataModel.shared.reload()
                message = "Everything is back to the defaults."
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Bornolipi Backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Engine.shared.backup().encoded().write(to: url, options: .atomic)
            UserDataFile<[String]>.ownerOnly(url)   // personal words and choices: owner-only, like the data files
            message = "Saved \(url.lastPathComponent)."
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            Engine.shared.restore(try UserBackup.decode(Data(contentsOf: url)))
            UserDataModel.shared.reload()
            message = "Imported \(url.lastPathComponent)."
        } catch {
            message = "Could not import: \(error)"
        }
    }
}
#endif
