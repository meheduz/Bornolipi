#if canImport(InputMethodKit)
import Foundation
import os

/// Diagnostics for compatibility problems with particular apps: which host app, which IMK callbacks,
/// whether a caret position was available. Never the text being typed. Debug messages are not kept
/// unless someone is watching:
///   log stream --level debug --predicate 'subsystem == "io.github.meheduz.inputmethod.Bornolipi"'
enum Log {
    static let imk = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BornolipiKeyboard", category: "imk")
}
#endif
