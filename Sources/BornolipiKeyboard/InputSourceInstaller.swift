#if canImport(InputMethodKit)
import Foundation
import InstallKit

/// Command line flags for developers (`scripts/dev-install.sh`). People use the Bornolipi app.
enum InputSourceInstaller {
    static func install() -> Int32 {
        do { try Keyboard.register() } catch { print(error.localizedDescription); return 1 }
        return status()
    }

    /// Exit status: 0 ready, 1 not registered or not installed, 2 waiting for the user to add it.
    static func status() -> Int32 {
        switch Keyboard.health(available: nil) {
        case .ready: print("ready: Bornolipi is enabled"); return 0
        case .notEnabled: print("registered; add it in System Settings > Keyboard > Text Input > Input Sources"); return 2
        case .notRegistered: print("not registered"); return 1
        case .notInstalled: print("not installed in \(Keyboard.installedURL.path)"); return 1
        case .damaged(let why): print("damaged: \(why)"); return 1
        case .outdated, .newerInstalled: return 0
        }
    }

    static func uninstall() -> Int32 {
        do { try Keyboard.uninstall(removeData: false) } catch { print(error.localizedDescription); return 1 }
        return 0
    }
}
#endif
