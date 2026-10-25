import Foundation
import InstallKit

/// Developer and test hooks that run the same InstallKit calls as the buttons. People never need them.
///   --health | --install | --uninstall | --uninstall-with-data | --diagnose
enum DeveloperFlags {
    static func runIfRequested() {
        let args = CommandLine.arguments
        let bundled = ProcessInfo.processInfo.environment["BORNOLIPI_KEYBOARD_BUNDLE"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL?.appendingPathComponent(Keyboard.bundleName)
        func report() {
            print("health:", Keyboard.health(available: bundled).summary)
            print("keyboard list includes Bornolipi:", KeyboardList.includesBornolipi.map { "\($0)" } ?? "unknown")
        }
        do {
            if args.contains("--health") { report(); exit(0) }
            if args.contains("--install") { try Keyboard.install(from: bundled!); report(); exit(0) }
            if args.contains("--uninstall") { try Keyboard.uninstall(removeData: false); report(); exit(0) }
            if args.contains("--uninstall-with-data") { try Keyboard.uninstall(removeData: true); report(); exit(0) }
        } catch {
            print("error:", error.localizedDescription)
            exit(1)
        }
    }
}
