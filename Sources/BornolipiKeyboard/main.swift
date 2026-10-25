// Entry point of the Bornolipi input method.
//
// macOS launches this app in the background when the input source is selected.
// The command line flags are used by the installer scripts:
//   BornolipiKeyboard --install     register and enable the input source
//   BornolipiKeyboard --uninstall   disable the input source
//   BornolipiKeyboard --status      show what macOS has registered
//   BornolipiKeyboard --version

import Foundation

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit
import Carbon

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print(AppInfo.version)
    exit(0)
}
if arguments.contains("--install") { exit(InputSourceInstaller.install()) }
if arguments.contains("--uninstall") { exit(InputSourceInstaller.uninstall()) }
if arguments.contains("--status") { exit(InputSourceInstaller.status()) }

final class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
        guard let name else {
            NSLog("Bornolipi: InputMethodConnectionName missing from Info.plist")
            NSApp.terminate(nil)
            return
        }
        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        _ = Engine.shared   // start loading the dictionary right away
        if CommandLine.arguments.contains("--settings") { SettingsWindowController.shared.show() }
        // macOS 26+ may switch away from this input method without deactivateServer (rime/squirrel#1140).
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceChanged), name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        KeyboardLifecycle.shared.start()
    }

    /// Quitting for any other reason also keeps the unfinished word.
    func applicationWillTerminate(_ notification: Notification) {
        InputController.active?.finishAfterSourceChange()
    }

    @objc func sourceChanged() {
        if !KeyboardLifecycle.bornolipiSelected() {
            KeyboardLifecycle.shared.finishTyping()
            KeyboardLifecycle.shared.sourceChangedAway()
        }
    }

    /// Opening the app again (Finder, Spotlight) shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

#else
print("BornolipiKeyboard is a macOS input method. Use `swift run bangla-convert` to try the engine on this platform.")
#endif
