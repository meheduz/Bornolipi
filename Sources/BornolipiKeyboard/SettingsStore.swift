#if canImport(InputMethodKit)
import Foundation
import BanglaEngine

/// Settings persisted as one JSON blob in UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "settings.v1"

    @Published var settings: EngineSettings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: SettingsStore.key),
           let s = try? JSONDecoder().decode(EngineSettings.self, from: data) {
            settings = s
        } else {
            // Settings that cannot be read are kept aside once, so saving new settings never loses them.
            if let raw = UserDefaults.standard.data(forKey: SettingsStore.key),
               UserDefaults.standard.data(forKey: SettingsStore.key + ".unreadable") == nil {
                UserDefaults.standard.set(raw, forKey: SettingsStore.key + ".unreadable")
            }
            settings = EngineSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: SettingsStore.key)
        }
    }
}
#endif
