import SwiftUI

/// Bornolipi.app: the app people open. It installs the keyboard it carries, guides them through
/// turning it on, and later checks, repairs, updates and removes it.
@main
struct BornolipiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = SetupModel()

    init() { DeveloperFlags.runIfRequested() }

    var body: some Scene {
        Window("Bornolipi", id: "main") {
            RootView().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Screenshots: BORNOLIPI_PREVIEW_APPEARANCE=light|dark overrides the system appearance for this app only.
    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_STEP"] != nil {
            NSApp.activate(ignoringOtherApps: true)
            if ProcessInfo.processInfo.environment["BORNOLIPI_PREVIEW_UPDATE"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { UpdateChecker.shared.presentPreviewSample() }
            }
        } else {
            Task { @MainActor in UpdateChecker.shared.startAutomaticChecks() }   // never blocks startup
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

