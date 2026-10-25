#if canImport(Carbon) && canImport(AppKit)
import AppKit
import Carbon

/// The list of keyboards that System Settings offers under Keyboard > Input Sources > +.
///
/// That pane keeps its own copy of macOS's keyboard list in its cache folder. On macOS 27 that copy
/// can go stale: written once and not refreshed for keyboards installed later, even after logging out
/// or restarting (seen on the development Mac). Then Bornolipi is installed and known to macOS but cannot be
/// added. Bornolipi only reads this copy, to explain the situation to the user; it never changes it.
public enum KeyboardList {
    static var folder: URL {
        // The per-user Darwin cache folder (/var/folders/…/C), not ~/Library/Caches.
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        let dir = n > 0 ? String(cString: buffer) : NSTemporaryDirectory()
        return URL(fileURLWithPath: dir).appendingPathComponent("com.apple.Keyboard-Settings.extension", isDirectory: true)
    }

    static let listFile = "com.apple.IntlDataCache.le.kbdx"

    /// Whether the pane's list includes Bornolipi: true, false, or nil when it cannot be told (the pane
    /// has never been opened, or the file cannot be read).
    public static var includesBornolipi: Bool? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(listFile)) else { return nil }
        return contains(data, Keyboard.modeID)
    }

    static func contains(_ data: Data, _ text: String) -> Bool {
        data.range(of: Data(text.utf8)) != nil
    }
}

extension Keyboard {
    /// Makes Bornolipi the keyboard in use (only possible once the user has added it).
    @discardableResult
    public static func select() -> Bool {
        onMain {
            let filter = [kTISPropertyInputSourceID as String: modeID] as CFDictionary
            guard let s = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first else { return false }
            return TISSelectInputSource(s) == noErr
        }
    }

}
#endif

#if canImport(Carbon) && canImport(AppKit)
extension Keyboard {
    /// True when the installed keyboard carries the "downloaded from the internet" mark that macOS
    /// adds to downloads (the copy inherits it from the app). Read only: Bornolipi never removes it. macOS
    /// may then ask the user to approve the keyboard in Privacy & Security before it can start.
    public static var installedCopyIsQuarantined: Bool {
        let info = NSDictionary(contentsOf: installedURL.appendingPathComponent("Contents/Info.plist"))
        guard let executable = info?["CFBundleExecutable"] as? String else { return false }
        return getxattr(installedURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path,
                        "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }
}
#endif
