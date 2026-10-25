import Foundation

/// Which keyboard this build is. Read from the running bundle's Info.plist, which scripts/build.sh
/// fills in with the release identity; the defaults are the same release values. A bundle with
/// another identity keeps its own restart channel and owns only its own input sources.
public enum KeyboardIdentity {
    public static let releaseBundleID = "io.github.meheduz.inputmethod.Bornolipi"

    static func resolve(_ info: [String: Any], mainBundleID: String?, mainBundleName: String) -> (id: String, bundle: String, dataFolder: String) {
        let isKeyboard = info["InputMethodConnectionName"] != nil
        let id = info["BornolipiKeyboardBundleID"] as? String ?? (isKeyboard ? mainBundleID : nil) ?? releaseBundleID
        let bundle = info["BornolipiKeyboardBundleName"] as? String ?? (isKeyboard ? mainBundleName : "BornolipiKeyboard.app")
        let folder = info["BornolipiDataFolder"] as? String ?? "Bornolipi"
        return (id, bundle, folder)
    }

    private static let resolved = resolve(Bundle.main.infoDictionary ?? [:], mainBundleID: Bundle.main.bundleIdentifier,
                                          mainBundleName: Bundle.main.bundleURL.lastPathComponent)
    /// The keyboard's bundle identifier, which is also its input source ID.
    public static var bundleID: String { resolved.id }
    /// The keyboard's bundle name in ~/Library/Input Methods.
    public static var bundleName: String { resolved.bundle }
    /// The folder in ~/Library/Application Support with the keyboard's personal words and choices.
    public static var dataFolder: String { resolved.dataFolder }
    public static var isTestIdentity: Bool { bundleID != releaseBundleID }

    /// Whether an input source ID belongs to the keyboard `bundleID`: the keyboard itself or one of
    /// its modes ("<id>.Phonetic"). A plain prefix test is wrong: the release ID is a prefix of the
    /// old test ID (…inputmethod.Bornolipi / …inputmethod.BornolipiTest).
    public static func owns(sourceID: String, bundleID: String = KeyboardIdentity.bundleID) -> Bool {
        sourceID == bundleID || sourceID.hasPrefix(bundleID + ".")
    }
}
