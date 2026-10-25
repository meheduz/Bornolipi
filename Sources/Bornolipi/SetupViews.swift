import Combine
import SwiftUI
import InstallKit

/// A paragraph that wraps instead of truncating.
struct Para: View {
    let text: String
    var font: Font = .body
    init(_ text: String, font: Font = .body) { self.text = text; self.font = font }
    var body: some View { Text(text).font(font).fixedSize(horizontal: false, vertical: true) }
}

struct RootView: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        Group {
            if model.setupComplete { HomeView() } else { AssistantView() }
        }
        .frame(width: 640, height: 520)
    }
}

// MARK: - Setup assistant

struct AssistantView: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            StepBar(current: model.step).padding(.vertical, 14)
            Divider()
            switch model.step {
            case .welcome: WelcomeStep()
            case .install: InstallStep()
            case .enable: EnableStep()
            case .tryIt: TryStep()
            case .done: DoneStep()
            }
        }
    }
}

/// One assistant screen: the content, any error, then a footer bar with the secondary action on the
/// left and the primary action on the right, in the same place on every screen.
struct StepPage<Content: View, Leading: View, Trailing: View>: View {
    @EnvironmentObject var model: SetupModel
    var centered = false
    @ViewBuilder let content: Content
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: centered ? .center : .leading, spacing: 16) { content }
                .padding(.horizontal, 44)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .topLeading)
            if let error = model.error {
                ErrorBanner(message: error).padding(.horizontal, 44).padding(.bottom, 16)
            }
            Divider()
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
    }
}

/// Title and one line of explanation at the top of a screen.
struct StepHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Para(title, font: .title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Para(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

struct StepBar: View {
    let current: SetupModel.Step
    private let names = ["Welcome", "Install", "Turn On", "Try It", "Done"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SetupModel.Step.allCases, id: \.rawValue) { step in
                let done = step.rawValue < current.rawValue
                HStack(spacing: 5) {
                    Image(systemName: done ? "checkmark.circle.fill" : (step == current ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(done || step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)   // the bar is read as "Step n of 5"
                    Text(names[step.rawValue])
                        .fontWeight(step == current ? .semibold : .regular)
                        .foregroundStyle(step.rawValue <= current.rawValue ? .primary : .secondary)
                }
                if step != .done { Rectangle().fill(.quaternary).frame(width: 20, height: 1) }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(SetupModel.Step.allCases.count): \(names[current.rawValue])")
    }
}

struct WelcomeStep: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        StepPage(centered: true) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Welcome to Bornolipi").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Type Bangla. Naturally.").font(.title3).foregroundStyle(.secondary)
            }
            Para("Write Bangla in any app using English letters, the same way as with Avro Phonetic.")
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 12) {
                Text("ami banglay gan gai").font(.system(.body, design: .monospaced))
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("আমি বাংলায় গান গাই").font(.title3)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("For example, ami banglay gan gai becomes আমি বাংলায় গান গাই")
            Text("Setup takes about two minutes. Nothing you type leaves your Mac.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
        } leading: {
            if model.runningFromDiskImage {
                Text("Bornolipi is running from the disk image.").foregroundStyle(.secondary)
                Button("Move to Applications") { model.moveToApplications() }
            }
        } trailing: {
            Button("Set Up") { model.step = .install }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }
}

struct InstallStep: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        StepPage {
            StepHeader(title: "Installing the keyboard",
                       subtitle: "Bornolipi is installed for your account only, so no administrator password is needed.")
            VStack(alignment: .leading, spacing: 12) {
                Check(done: copied, working: model.working && !copied, text: "Copy the keyboard")
                Check(done: installed, working: model.working && copied, text: "Register it with macOS")
            }
        } leading: {
            if model.working {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
            }
        } trailing: {
            if !model.working && (model.error != nil || !installed) {
                Button("Try Again") { model.install() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else if installed {
                Button("Continue") { model.step = model.health == .ready ? .tryIt : .enable }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            guard !model.previewing else { return }
            switch model.health {
            case .ready, .notEnabled: model.refresh()
            default: model.install()
            }
        }
    }

    private var isDamaged: Bool { if case .damaged = model.health { return true } else { return false } }
    private var copied: Bool { model.health != .notInstalled && !isDamaged }
    private var installed: Bool { model.health == .notEnabled || model.health == .ready }
}

struct EnableStep: View {
    @EnvironmentObject var model: SetupModel
    @State private var waited = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let showsHelpForPreview = ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_HELP"] != nil

    var body: some View {
        StepPage {
            StepHeader(title: "Turn on the keyboard",
                       subtitle: "macOS asks you to do this once, so that no app can add a keyboard without your consent. This window continues by itself when you are done.")
            VStack(alignment: .leading, spacing: 10) {
                Numbered(1, "Click Open Keyboard Settings.")
                Numbered(2, "Next to Input Sources, click Edit…")
                Numbered(3, "Click + at the bottom left, then choose Bangla.")
                Numbered(4, "Select Bornolipi and click Add.")
            }
            if model.listIncludesBornolipi == false { StaleListFix() } else if waited >= 20 || showsHelpForPreview { NotListedHelp() }
        } leading: {
            ProgressView().controlSize(.small)
            Text("Waiting for Bornolipi to be added…").foregroundStyle(.secondary)
        } trailing: {
            Button("Open Keyboard Settings") { Keyboard.openKeyboardSettings() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .onReceive(tick) { _ in waited += 1 }
    }
}

/// Shown as soon as System Settings' keyboard list is known to lack Bornolipi.
struct StaleListFix: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        HelpBox(title: "Bornolipi isn't in the keyboard list yet",
                detail: "Bornolipi is installed, but System Settings is showing an older list of keyboards. Restart System Settings, then click + and look under Bangla again. If Bornolipi still doesn't appear, log out and back in, or report the problem.")
    }
}

/// Shown after a while on the "Turn On" step: what to do when Bornolipi is missing from the list.
struct NotListedHelp: View {
    var body: some View {
        HelpBox(title: "Don't see Bornolipi in the list?",
                detail: "System Settings reads the list when it opens, so it can miss a keyboard installed while it was open. Restart it, then look under Bangla again. Still missing? Log out and back in (Apple menu > Log Out), then open Bornolipi again.")
    }
}

struct HelpBox: View {
    @EnvironmentObject var model: SetupModel
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(title).font(.headline) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Para(detail).foregroundStyle(.secondary).padding(.leading, 28)
            HStack {
                Button("Restart System Settings") { Keyboard.restartKeyboardSettings() }
                Button("Repair Installation") { model.install() }.disabled(model.working)
                Button("Report a Problem") { NSWorkspace.shared.open(SetupModel.reportURL) }
            }
            .padding(.leading, 28).padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TryStep: View {
    @EnvironmentObject var model: SetupModel
    @State private var text = ""
    @FocusState private var focused: Bool
    private var typedBangla: Bool { text.unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) } }

    var body: some View {
        StepPage {
            StepHeader(title: "Try it", subtitle: "Make sure everything works before you start.")
            VStack(alignment: .leading, spacing: 10) {
                Numbered(1, "Choose Bornolipi from the input menu (ব) in the menu bar, or press Control-Space.")
                Numbered(2, "Type ami banglay likhi in the box below, then press Space.")
            }
            TextField("Type here", text: $text, axis: .vertical)
                .font(.system(size: 20))
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .accessibilityLabel("Practice text box")
            feedback
        } leading: {
            Button("Skip") { model.step = .done }
        } trailing: {
            Button("Continue") { model.step = .done }
                .buttonStyle(.borderedProminent).disabled(!typedBangla).keyboardShortcut(.defaultAction)
        }
        .onAppear { focused = true }
    }

    @ViewBuilder private var feedback: some View {
        if typedBangla {
            Label("Bornolipi is working", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
        } else if !model.isSelected {
            HStack(spacing: 10) {
                Label("Bornolipi is not selected yet", systemImage: "keyboard").foregroundStyle(.secondary)
                Button("Use Bornolipi Now") { model.useBornolipiNow(); focused = true }
            }
        } else if text.count >= 12 && Keyboard.installedCopyIsQuarantined {
            VStack(alignment: .leading, spacing: 8) {
                Para("macOS may be waiting for you to allow the keyboard, because it came from the internet. Open Privacy & Security, scroll down, and click Open Anyway next to BornolipiKeyboard. Then type here again.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security") { Keyboard.openPrivacySettings() }
            }
        } else if text.count >= 12 {
            HStack(spacing: 10) {
                Para("Still English letters? Bornolipi may be in English mode (press Control-Shift-B), or it may need a restart.")
                    .foregroundStyle(.secondary)
                Button("Restart Keyboard") { model.restartKeyboard(); text = "" }
            }
        } else {
            Label("Bornolipi is selected", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        }
    }
}

struct DoneStep: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        StepPage(centered: true) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.green).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("You're all set").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Bornolipi is ready in every app.").font(.title3).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                tip(["Space"], "Finish a word")
                tip(["↑", "↓"], "Choose another suggestion")
                tip(["esc"], "Keep the English letters")
                tip(["⌃", "⇧", "B"], "Switch between Bangla and English")
                tip(["⌃", "Space"], "Switch to your other keyboard")
            }
            .padding(.vertical, 6)
            Text("Open Bornolipi at any time to check, repair, update or remove the keyboard.")
                .font(.callout).foregroundStyle(.secondary)
        } leading: {
            EmptyView()
        } trailing: {
            Button("Done") { model.setupComplete = true }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    private func tip(_ keys: [String], _ meaning: String) -> some View {
        GridRow {
            HStack(spacing: 4) { ForEach(keys, id: \.self) { KeyCap($0) } }
                .gridColumnAlignment(.trailing)
            Text(meaning)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status and management

struct HomeView: View {
    @EnvironmentObject var model: SetupModel
    @ObservedObject private var updates: UpdateChecker
    @State private var confirmUninstall = false
    @State private var removeData = false
    @State private var uninstalled = false
    @State private var copied = false
    @State private var trashError: String?
    @State private var showNotes = false

    init() { _updates = ObservedObject(wrappedValue: UpdateChecker.shared) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bornolipi").font(.title2.weight(.semibold))
                        Text("Version \(updates.currentVersion.short)").foregroundStyle(.secondary)
                    }
                }
                StatusCard()
                if model.keyboardRestartPending {
                    GroupBox {
                        HStack {
                            Para("The updated keyboard takes over the next time you switch to another keyboard. To use it now, finish what you are typing, then restart the keyboard. If Bornolipi then types English letters in an app that was open, quit and reopen that app.")
                            Spacer()
                            Button("Restart Keyboard") { model.restartKeyboard() }
                        }
                        .padding(4)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button("Keyboard Settings…") { Keyboard.openKeyboardPreferences() }.disabled(model.health != .ready && model.health != .notEnabled)
                            Button("Input Sources…") { Keyboard.openKeyboardSettings() }
                            Spacer()
                            if model.working { ProgressView().controlSize(.small) }
                            Button("Repair") { model.install() }.disabled(model.working || model.bundled == nil)
                            Button("Run Setup Again") { model.step = .welcome; model.setupComplete = false }.disabled(model.working)
                        }
                        Divider()
                        HStack(spacing: 8) {
                            Toggle("Check for updates automatically", isOn: $updates.automatic)
                            Spacer()
                            updateText
                            Button("Check Now") { updates.check() }.disabled(updates.state == .checking)
                        }
                        Text("Once a day, Bornolipi reads the latest version number and release notes from github.com. Nothing about you or your Mac is sent, and nothing is downloaded until you choose to.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
                if let error = model.error { ErrorBanner(message: error) }
            }
            .padding(.horizontal, 28).padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy Diagnostic Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnostics, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .help("Copies versions and status (never anything you typed) to paste into a support request.")
                Button("Report a Problem") { NSWorkspace.shared.open(SetupModel.reportURL) }
                Spacer()
                Button("Uninstall…", role: .destructive) { confirmUninstall = true }.disabled(model.working)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .sheet(isPresented: $confirmUninstall) { uninstallSheet }
        .sheet(isPresented: $showNotes) { notesSheet }
    }

    @ViewBuilder private var notesSheet: some View {
        if case .available(let release) = updates.state {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bornolipi \(release.version)").font(.title3.weight(.semibold))
                ScrollView { Text(release.notes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 260)
                Text("To update, download the new disk image, drag Bornolipi to Applications and choose Replace. Your words and settings are kept.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close") { showNotes = false }.keyboardShortcut(.cancelAction)
                    Button("Download") { NSWorkspace.shared.open(release.page); showNotes = false }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 520)
        }
    }

    @ViewBuilder private var updateText: some View {
        switch updates.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate: Text("Bornolipi is up to date.").foregroundStyle(.secondary)
        case .noRelease: Text("No release has been published yet.").foregroundStyle(.secondary)
        case .available(let release):
            Text("Version \(release.version) is available.")
            if !release.notes.isEmpty { Button("Release Notes…") { showNotes = true } }
            Button("Download") { NSWorkspace.shared.open(release.page) }
        case .failed(let why): Text("Couldn't check.").foregroundStyle(.secondary).help(why)
        }
    }

    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if uninstalled {
                Para("Bornolipi was removed", font: .title3.bold())
                Text("If it is still listed in the input menu, remove it in Keyboard settings: Input Sources, Edit…, select it, then click −.")
                HStack {
                    Button("Open Keyboard Settings") { Keyboard.openKeyboardSettings() }
                    Spacer()
                    Button("Move This App to Trash") {
                        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
                            DispatchQueue.main.async {
                                if let error { trashError = "Could not move Bornolipi to the Trash (\(error.localizedDescription)). Drag it from Applications to the Trash." }
                                else { NSApp.terminate(nil) }
                            }
                        }
                    }
                    Button("Close") { confirmUninstall = false; uninstalled = false; model.setupComplete = model.health == .ready }
                        .keyboardShortcut(.defaultAction)
                }
                if let trashError { Text(trashError).foregroundStyle(.red).font(.footnote) }
            } else {
                Para("Remove Bornolipi?", font: .title3.bold())
                Text("The keyboard is removed from your Mac.")
                Toggle("Also delete my personal words, learned choices and settings", isOn: $removeData)
                Text(removeData ? "They cannot be recovered." : "They are kept, so reinstalling later picks them up.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { confirmUninstall = false }.keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) { model.uninstall(removeData: removeData) { uninstalled = $0 } }
                        .disabled(model.working)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct StatusCard: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title).foregroundStyle(color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    action
                }
                Spacer()
            }
            .padding(6)
        }
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch model.health {
        case .ready: return "checkmark.circle.fill"
        case .notEnabled, .outdated, .newerInstalled: return "exclamationmark.circle.fill"
        default: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch model.health {
        case .ready: return .green
        case .notEnabled, .outdated, .newerInstalled: return .orange
        default: return .red
        }
    }

    private var title: String {
        switch model.health {
        case .ready: return "The keyboard is installed and turned on"
        case .notEnabled: return "The keyboard is not turned on"
        case .outdated: return "An update for the keyboard is ready"
        case .newerInstalled: return "This copy of Bornolipi is older than the installed keyboard"
        case .notInstalled: return "The keyboard is not installed"
        case .notRegistered: return "macOS does not know about the keyboard yet"
        case .damaged: return "The keyboard needs repair"
        }
    }

    private var detail: String {
        switch model.health {
        case .ready: return model.isSelected ? "It is in use now." : "Choose Bornolipi from the input menu in the menu bar, or press Control-Space, or click Use Bornolipi Now."
        case .notEnabled:
            return model.listIncludesBornolipi == false
                ? "Bornolipi isn't showing up in your keyboard list yet. Open Run Setup Again for help."
                : "Add it in Keyboard settings: Input Sources, Edit…, +, Bangla, Bornolipi, Add."
        case .outdated(let a, let b): return "Version \(a) is installed; this app includes \(b). Your words and settings are kept."
        case .newerInstalled(let a, let b): return "The keyboard (\(a)) is newer than this app (\(b)). Download the latest Bornolipi to manage it."
        case .notInstalled: return "Install it to start typing Bangla."
        case .notRegistered: return "Repair registers it again."
        case .damaged(let why): return why + " Repair puts a fresh copy in place; your words and settings are kept."
        }
    }

    @ViewBuilder private var action: some View {
        switch model.health {
        case .ready: if !model.isSelected { Button("Use Bornolipi Now") { model.useBornolipiNow() } }
        case .notEnabled:
            HStack {
                Button("Open Keyboard Settings") { Keyboard.openKeyboardSettings() }
            }
        case .outdated: Button("Update Now") { model.install() }.buttonStyle(.borderedProminent).disabled(model.working)
        case .newerInstalled: EmptyView()
        default: Button(model.health == .notInstalled ? "Install" : "Repair") { model.install() }
            .buttonStyle(.borderedProminent).disabled(model.working || model.bundled == nil)
        }
    }
}

// MARK: - Small pieces

struct Check: View {
    let done: Bool
    var working = false
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if working { ProgressView().controlSize(.small) } else {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)   // the row's value says done or not done
                }
            }
            .frame(width: 18)
            Text(text).foregroundStyle(done || working ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : (working ? "in progress" : "not done"))
    }
}

/// A key as drawn on the keyboard, for the shortcut list.
struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.callout.weight(.medium))
            .frame(minWidth: 16)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.tertiary))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

struct Numbered: View {
    let n: Int, english: String
    init(_ n: Int, _ english: String) { self.n = n; self.english = english }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 22, height: 22).background(Circle().fill(.quaternary)).accessibilityHidden(true)
            Para(english)
        }
        .accessibilityLabel("Step \(n): \(english)")
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label { Para(message) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
