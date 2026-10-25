#if canImport(InputMethodKit)
import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// ~/Library/Application Support/Bornolipi, or BORNOLIPI_SUPPORT_DIR for tests and previews.
    static var supportDirectory: URL {
        if let dev = ProcessInfo.processInfo.environment["BORNOLIPI_SUPPORT_DIR"] {
            return URL(fileURLWithPath: dev, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.object(forInfoDictionaryKey: "BornolipiDataFolder") as? String ?? "Bornolipi"
        return base.appendingPathComponent(folder, isDirectory: true)
    }

    /// Where the JSON data lives: inside the app bundle, or BORNOLIPI_DATA_DIR while developing.
    static var dataDirectory: URL {
        if let dev = ProcessInfo.processInfo.environment["BORNOLIPI_DATA_DIR"] {
            return URL(fileURLWithPath: dev)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("Data", isDirectory: true)
    }
}
#endif
