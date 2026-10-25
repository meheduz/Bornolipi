import Foundation

/// The Bangla/English part of Bornolipi's input menu. Bornolipi is one input source; Bangla and English are
/// its own typing modes, so the menu bar icon stays Bornolipi's. macOS asks for the menu on its own
/// schedule (on activation and after some keys) and shows a cached copy, so the menu cannot show
/// the mode reliably (tested on macOS 27: after Control-Shift-B the menu kept its old text). Its
/// items therefore name a mode explicitly instead of toggling or marking one, so a cached menu can
/// never mislead; the বাং/EN bubble shows the mode on every switch.
public struct ModeMenuItem: Equatable {
    public let title: String
    /// The mode this item selects.
    public let bangla: Bool
}

public enum ModeMenu {
    public static let items = [ModeMenuItem(title: "Bangla", bangla: true), ModeMenuItem(title: "English", bangla: false)]

    /// A disabled line naming the shortcut and where the mode is shown.
    public static func hint(_ shortcut: Shortcut) -> String { "Switch with \(shortcut.display) (the বাং/EN bubble shows the mode)" }

    /// Choosing an item: the mode to switch to, or nil when it is already in use (nothing changes;
    /// the bubble still shows the mode).
    public static func choose(_ item: ModeMenuItem, current bangla: Bool) -> Bool? {
        item.bangla == bangla ? nil : item.bangla
    }
}
