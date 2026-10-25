import AppKit
import InstallKit

/// The Bornolipi app's update check (the keyboard itself has no network access). It reads GitHub's
/// latest-release document, at launch and then at most once a day while automatic checks are on
/// (the default; Settings can turn it off), or when the user clicks Check Now. A newer version is
/// offered with its release notes and a link to its GitHub release page; nothing is downloaded or
/// installed by the app. The rules live in InstallKit's UpdateService, where they are tested.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, noRelease
        case available(ReleaseInfo)
        case failed(String)
    }

    static let shared = UpdateChecker()
    @Published private(set) var state = State.idle
    @Published var automatic: Bool { didSet { service.automaticChecks = automatic } }
    private let service: UpdateService
    private var timer: Timer?

    init() {
        let version = Keyboard.Version(short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                                       build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0)
        service = UpdateService(current: version)
        automatic = service.automaticChecks
    }

    var currentVersion: Keyboard.Version {
        Keyboard.Version(short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                         build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0)
    }

    /// At launch: check in the background if due, and keep looking once an hour whether a day has passed.
    func startAutomaticChecks() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.shared.checkIfDue() }
        }
    }

    func checkIfDue() {
        guard service.automaticCheckIsDue, state != .checking else { return }
        run(announce: true)
    }

    /// The Check Now button: the result is shown in the status window.
    func check() {
        guard state != .checking else { return }
        run(announce: false)
    }

    private func run(announce: Bool) {
        let before = state
        state = .checking
        Task {
            let outcome = await service.check()
            switch outcome {
            case .available(let release, let notify):
                state = .available(release)
                if announce && notify { present(release) }
            case .upToDate: state = .upToDate
            case .noRelease: state = .noRelease
            // Automatic checks fail quietly and keep what was shown (an update found earlier stays).
            case .failed(let failure):
                state = announce ? UpdateService.displayAfterQuietFailure(before: before, checking: .checking, idle: .idle) : .failed(failure.message)
            }
        }
    }

    /// Screenshots only (BORNOLIPI_PREVIEW_STEP with BORNOLIPI_PREVIEW_UPDATE=1): the real alert with a clearly
    /// labelled sample release, without any network access. Never used outside preview mode.
    func presentPreviewSample() {
        let sample = ReleaseInfo(version: "0.1.1", page: URL(string: "https://github.com/meheduz/Bornolipi/releases")!,
                                 notes: "**Preview sample, not a real release.**\n\n- Fixed: an example of a fixed problem.\n- New: an example of a `new` feature.")
        present(sample, recordLater: false)
    }

    /// A native alert: version, release notes, Download Update and Later.
    private func present(_ release: ReleaseInfo, recordLater: Bool = true) {
        let alert = NSAlert()
        alert.messageText = "Bornolipi \(release.version) is available"
        alert.informativeText = "You have version \(currentVersion.short). Download the new disk image, drag Bornolipi to Applications and choose Replace. Your words and settings are kept."
        if !release.notes.isEmpty {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            text.isEditable = false
            // GitHub release notes are Markdown: inline styles and links render, line breaks are kept.
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let styled = (try? NSMutableAttributedString(AttributedString(markdown: release.notes, options: options), including: \.appKit))
                ?? NSMutableAttributedString(string: release.notes)
            let all = NSRange(location: 0, length: styled.length)
            styled.addAttribute(.foregroundColor, value: NSColor.textColor, range: all)
            styled.enumerateAttribute(.font, in: all) { value, range, _ in
                let bold = (value as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
                styled.addAttribute(.font, value: bold ? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize) : NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), range: range)
            }
            text.textStorage?.setAttributedString(styled)
            text.textContainerInset = NSSize(width: 4, height: 4)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"   // Escape means Later
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if recordLater { NSWorkspace.shared.open(release.page) }   // validated by ReleaseFeed: https://github.com/meheduz/Bornolipi/releases/...
        } else if recordLater {
            service.remindLater(release)
        }
    }
}
