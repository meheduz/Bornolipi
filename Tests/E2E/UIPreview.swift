// Renders the input method's windows (candidate panel, mode HUD, every Settings tab) in light and
// dark mode and saves a screenshot of each, so the UI can be reviewed without typing in an app.
// Run it with scripts/ui-preview.sh; it uses a scratch support directory, never the user's data.
import AppKit
import BanglaEngine

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    let out: String
    init(out: String) { self.out = out }

    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.async { self.run() }
    }

    func pump(_ seconds: TimeInterval) {
        let end = Date(timeIntervalSinceNow: seconds)
        while Date() < end {
            if let e = NSApp.nextEvent(matching: .any, until: min(end, Date(timeIntervalSinceNow: 0.02)), inMode: .default, dequeue: true) {
                NSApp.sendEvent(e)
            }
        }
    }

    func capture(_ windowNumber: Int, _ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(windowNumber)", "\(out)/\(name).png"]
        try? p.run()
        p.waitUntilExit()
        print("\(name).png")
    }

    func run() {
        Engine.shared.setUserWords(["মেহেদূজ", "সুইফট"])
        let list = CandidateList(candidates: ["বাংলা", "বাঙলা", "বাংলায়", "বাংলাদেশ", "বাংলাভাষা"], selected: 1, typed: "bangla")
        let caret = NSRect(x: 420, y: 640, width: 1, height: 20)
        for (appearance, tag) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            CandidatePanel.shared.show(list, near: caret, clientLevel: 0)
            pump(0.6)
            capture(CandidatePanel.shared.windowNumber, "candidates-\(tag)")
            CandidatePanel.shared.hide()
            SettingsStore.shared.settings.candidateTextSize = 24
            CandidatePanel.shared.show(list, near: caret, clientLevel: 0)
            pump(0.6)
            capture(CandidatePanel.shared.windowNumber, "candidates-24pt-\(tag)")
            CandidatePanel.shared.hide()
            SettingsStore.shared.settings.candidateTextSize = 17
            HUD.shared.flash("বাং", near: caret)
            pump(0.4)
            capture(HUD.shared.windowNumber, "hud-\(tag)")
            for tab in ["general", "dictionary", "shortcuts", "autocorrect", "about"] {
                UserDefaults.standard.set(tab, forKey: "settings.tab")
                SettingsWindowController.shared.show()
                pump(0.8)
                capture(SettingsWindowController.shared.windowNumber, "settings-\(tab)-\(tag)")
            }
        }
        exit(0)
    }
}

@main
struct UIPreviewMain {
    static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "."
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PreviewDelegate(out: out)
        app.delegate = delegate
        app.run()
    }
}
