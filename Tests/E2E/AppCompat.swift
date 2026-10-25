// Types into real apps through the system keyboard path (CGEvent at the HID level, like a physical
// keyboard) with Bornolipi selected, and reads the result back with the Accessibility API.
// Needs Accessibility permission for the app that runs it. Run with scripts/app-compat-test.sh.
//
// Safety: before every key it checks that the target app is frontmost and stops otherwise, so keys
// never land in another app. It only types into scratch documents it opened itself.
import AppKit
import ApplicationServices
import Carbon

// Drives the installed Bornolipi keyboard, so it runs only when asked for explicitly with
// BORNOLIPI_KEYBOARD=release and BORNOLIPI_ALLOW_RELEASE=1. The run stops if Bornolipi's personal data or settings
// change (see releaseDataFingerprint); BORNOLIPI_SMOKE=1 runs a TextEdit check that teaches nothing.
let env = ProcessInfo.processInfo.environment
let targetsRelease = env["BORNOLIPI_KEYBOARD"] == "release" && env["BORNOLIPI_ALLOW_RELEASE"] == "1"
let imeBundle = "io.github.meheduz.inputmethod.Bornolipi"
let ourMode = imeBundle + ".Phonetic"
let smoke = env["BORNOLIPI_SMOKE"] == "1"

// MARK: Data guard

/// A fingerprint (file names, sizes and contents) of the release keyboard's personal data and
/// settings, compared around every app. Learned choices (selections.json and its backup) are left
/// out: the checks teach one on purpose, and scripts/app-compat-test.sh puts both files back.
func releaseDataFingerprint() -> String {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent("Library/Application Support/Bornolipi")
    var parts: [String] = []
    for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix("selections.json") {
        let data = (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
        parts.append("\(name):\(data.count):\(data.base64EncodedString())")
    }
    let prefs = home.appendingPathComponent("Library/Preferences/io.github.meheduz.inputmethod.Bornolipi.plist")
    parts.append("prefs:\((try? Data(contentsOf: prefs))?.base64EncodedString() ?? "none")")
    return parts.joined(separator: "|")
}
var log: [String] = []
func say(_ s: String) { print(s); log.append(s); fflush(stdout) }

// MARK: Input sources

func source(_ id: String) -> TISInputSource? {
    (TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource])?.first
}
func currentSource() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}
@discardableResult func select(_ id: String) -> Bool { source(id).map { TISSelectInputSource($0) == noErr } ?? false }

// MARK: Keys (US layout)

let codes: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
    "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
    "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ".": 47, ",": 43, " ": 49,
]
let named: [String: UInt16] = ["return": 36, "tab": 48, "esc": 53, "bs": 51, "left": 123, "right": 124, "down": 125, "up": 126]

struct Key { let code: UInt16; let flags: CGEventFlags }

func keys(_ script: String) -> [Key] {
    var out: [Key] = []
    var i = script.startIndex
    while i < script.endIndex {
        if script[i] == "{", let close = script[i...].firstIndex(of: "}") {
            var parts = script[script.index(after: i)..<close].split(separator: "+").map(String.init)
            let name = parts.removeLast()
            var f: CGEventFlags = []
            for p in parts { f.insert(p == "ctrl" ? .maskControl : p == "shift" ? .maskShift : p == "cmd" ? .maskCommand : .maskAlternate) }
            out.append(Key(code: named[name] ?? codes[Character(name)]!, flags: f))
            i = script.index(after: close)
            continue
        }
        let c = script[i]
        if let code = codes[c] { out.append(Key(code: code, flags: [])) }
        else if let code = codes[Character(c.lowercased())] { out.append(Key(code: code, flags: .maskShift)) }
        i = script.index(after: i)
    }
    return out
}

struct LostFocus: Error { let app: String }

/// The app in front right now: the owner of the topmost normal window, from the window server.
/// (NSWorkspace.frontmostApplication only updates while a run loop runs, and running one here makes
/// macOS apply the input source selection to this tool instead of the target app.)
func frontmost() -> pid_t? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
        if let pid = w[kCGWindowOwnerPID as String] as? pid_t { return pid }
    }
    return nil
}

/// Types into `pid` only; throws as soon as another app is in front.
func type(_ script: String, into pid: pid_t, name: String, gap: TimeInterval = 0.06) throws {
    let src = CGEventSource(stateID: .hidSystemState)
    for k in keys(script) {
        guard frontmost() == pid else { throw LostFocus(app: NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: k.code, keyDown: down)
            e?.flags = k.flags
            e?.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: gap)
    }
    Thread.sleep(forTimeInterval: 0.4)
}

// MARK: Reading back

func axValue(_ e: AXUIElement, _ attr: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
}

func focusedElement(_ pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    // Chrome and Electron build their accessibility tree only when asked. (Native apps are left alone:
    // AXEnhancedUserInterface changes how they behave.)
    let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    if bundle == "com.google.Chrome" { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    if bundle.hasPrefix("com.todesktop") || bundle == "com.microsoft.VSCode" {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
    guard let f = axValue(app, kAXFocusedUIElementAttribute) else { return nil }
    return (f as! AXUIElement)
}

func text(_ pid: pid_t) -> String? {
    guard let e = focusedElement(pid) else { return nil }
    return axValue(e, kAXValueAttribute) as? String
}

func windowTitle(_ pid: pid_t) -> String {
    let app = AXUIElementCreateApplication(pid)
    guard let w = axValue(app, kAXFocusedWindowAttribute) else { return "" }
    return axValue(w as! AXUIElement, kAXTitleAttribute) as? String ?? ""
}

/// Screen rect (top-left coordinates) of the caret in the focused element, if the app reports it.
func caretRect(_ pid: pid_t) -> CGRect? {
    guard let e = focusedElement(pid), let range = axValue(e, kAXSelectedTextRangeAttribute) else { return nil }
    var out: AnyObject?
    guard AXUIElementCopyParameterizedAttributeValue(e, kAXBoundsForRangeParameterizedAttribute as CFString, range, &out) == .success,
          let v = out else { return nil }
    var r = CGRect.zero
    AXValueGetValue(v as! AXValue, .cgRect, &r)
    return r
}

func imeWindows() -> [CGRect] {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: imeBundle).first?.processIdentifier,
          let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b as CFDictionary)
    }
}

// MARK: The checks, per app

struct Target {
    let name: String
    let bundle: String
    let open: () -> Void
    /// Clears the text area before each check (select all + delete), or nil to type after what is there.
    var clear: String? = "{cmd+a}{bs}"
    /// Text before the typed text that should be ignored (e.g. a shell prompt).
    var webChat = false
    /// Run after the checks (e.g. delete the scratch note it created).
    var cleanup: ((pid_t) throws -> Void)? = nil
}

var passes = 0, failures = 0, skipped = 0
func check(_ app: String, _ what: String, _ ok: Bool, _ detail: String) {
    if ok { passes += 1; say("  PASS \(what)") } else { failures += 1; say("  FAIL \(what): \(detail)") }
}

func run(_ t: Target, html: URL) throws {
    say("\n== \(t.name)")
    let dataBefore = releaseDataFingerprint()
    defer {
        if releaseDataFingerprint() != dataBefore { say("  ABORT the release keyboard's data changed during \(t.name)"); abortRun("release data changed") }
    }
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundle) != nil else {
        skipped += 1; say("  SKIP not installed"); return
    }
    t.open()
    var pid: pid_t?
    for _ in 0..<40 {
        Thread.sleep(forTimeInterval: 0.5)
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: t.bundle).first else { continue }
        if frontmost() == app.processIdentifier { pid = app.processIdentifier; break }
        app.activate(options: [.activateAllWindows])
    }
    guard let pid else { skipped += 1; say("  SKIP could not bring it to the front"); return }
    Thread.sleep(forTimeInterval: 2.5)   // documents and pages finish loading
    guard select(ourMode) else { failures += 1; say("  FAIL could not select Bornolipi"); return }
    Thread.sleep(forTimeInterval: 0.8)
    say("  input source: \(currentSource())")
    guard currentSource() == ourMode else { abortRun("selected source is \(currentSource()), not \(ourMode)") }

    func fresh() throws { if let c = t.clear { try type(c, into: pid, name: t.name) } }
    func value() -> String { (text(pid) ?? "<no text>").trimmingCharacters(in: .init(charactersIn: "\n")) }
    // Apps may add a trailing space or capitalise an English word; neither is the keyboard's doing.
    func ends(_ want: String) -> (Bool, String) {
        let v = value()
        let ok = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(want.lowercased())
        return (ok, "text ends with \(String(v.suffix(40)).debugDescription)")
    }

    do {
        // macOS switches the app's input context to the new source asynchronously: wait until a
        // probe key really comes back as Bangla before testing.
        var ready = false
        for _ in 0..<8 where !ready {
            try fresh()
            try type("a ", into: pid, name: t.name)
            ready = value().contains("আ")
            // Safari converts nothing for the first key after another process changes the input
            // source, so retry without selecting again.
            if !ready { Thread.sleep(forTimeInterval: 1) }
        }
        guard ready else { failures += 1; say("  FAIL keys never reached Bornolipi (text \(value().suffix(20).debugDescription))"); select("com.apple.keylayout.US"); return }
        if smoke {
            try fresh()
            try type("ami ", into: pid, name: t.name)
            let r = ends("আমি"); check(t.name, "smoke: ami + Space through Bornolipi", r.0, r.1)
            select("com.apple.keylayout.US")
            return
        }
        try fresh()
        try type("ami banglay gan gai ", into: pid, name: t.name)
        var r = ends("আমি বাংলায় গান গাই"); check(t.name, "sentence composes and commits", r.0 || value().contains("আমি বাংলায় গান গাই"), r.1)

        try fresh()
        try type("bhalo", into: pid, name: t.name)
        let caret = caretRect(pid), panels = imeWindows().filter { $0.height > 40 }
        if let c = caret, let p = panels.first {
            let near = abs(p.minX - c.minX) < 80 && (p.minY >= c.maxY - 2 && p.minY < c.maxY + 60 || p.maxY <= c.minY + 2 && p.maxY > c.minY - 60)
            check(t.name, "candidate window next to the caret", near, "caret \(c.integral), window \(p.integral)")
        } else {
            say("  note: candidate window \(panels.isEmpty ? "not on screen" : "on screen"); caret \(caret.map { "\($0.integral)" } ?? "not reported by the app")")
        }
        try type(" ", into: pid, name: t.name)
        r = ends("ভালো"); check(t.name, "word committed with Space", r.0, r.1)

        // Learned choices can change the first candidate, so compare Space with ↓ Space directly.
        try fresh()
        try type("mon ", into: pid, name: t.name)
        let first = value().trimmingCharacters(in: .whitespacesAndNewlines)
        try fresh()
        try type("mon{down} ", into: pid, name: t.name)
        let picked = value().trimmingCharacters(in: .whitespacesAndNewlines)
        check(t.name, "↓ picks another candidate", picked != first && picked.unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) },
              "Space gave \(first.suffix(10).debugDescription), ↓ Space gave \(picked.suffix(10).debugDescription)")

        // An informal spelling: Space keeps Avro's বারি, the word meant (বাড়ি) is offered right after it.
        try fresh()
        try type("bari{down} ", into: pid, name: t.name)
        let r0 = ends("বাড়ি"); check(t.name, "informal spelling offered next (bari, ↓: বাড়ি)", r0.0, r0.1)

        try fresh()
        try type("amix{bs} ", into: pid, name: t.name)
        r = ends("আমি"); check(t.name, "Delete edits the word", r.0, r.1)

        try fresh()
        try type("ami{left}{right}tumi ", into: pid, name: t.name)
        r = ends("আমিতুমি"); check(t.name, "arrow keys commit before moving", r.0, r.1)

        try fresh()
        try type("{ctrl+shift+b}hello {ctrl+shift+b}ami ", into: pid, name: t.name)
        r = ends("hello আমি"); check(t.name, "Control-Shift-B switches to English and back", r.0, r.1)

        // Avro default kept; Esc; leading punctuation in context.
        try fresh()
        try type("sust ", into: pid, name: t.name)
        r = ends("সুস্ত"); check(t.name, "Space keeps the Avro conversion (sust)", r.0, r.1)
        try fresh()
        try type("ami{esc} ", into: pid, name: t.name)
        r = ends("ami"); check(t.name, "Esc gives back the English letters", r.0, r.1)
        try fresh()
        try type(".5 ", into: pid, name: t.name)
        r = ends(".৫"); check(t.name, "leading punctuation as Avro (.5)", r.0, r.1)

        // Autocorrect undo: Backspace right after a correction reopens the word; Space keeps the Avro form.
        try fresh()
        try type("computer ", into: pid, name: t.name)
        let corrected = value().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("কম্পিউটার")
        try type("{bs}", into: pid, name: t.name)
        let reopened = value()
        try type(" ", into: pid, name: t.name)
        r = ends("চম্পুতের")
        check(t.name, "autocorrect undo (Backspace reopens, Space keeps the exact form)",
              corrected && r.0 && !value().contains("কম্পিউটার"),
              "corrected \(corrected), after Backspace \(String(reopened.suffix(20)).debugDescription), \(r.1)")
        try fresh()
        try type("computer {left}{bs}", into: pid, name: t.name)
        check(t.name, "no undo after the caret moved", !value().contains("চম্পুতের"), "text \(String(value().suffix(20)).debugDescription)")

        // Leaving the app mid-word commits it exactly once.
        try fresh()
        try type("kemon", into: pid, name: t.name)
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate(options: [])
            Thread.sleep(forTimeInterval: 1.2)
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
            for _ in 0..<20 where frontmost() != pid { Thread.sleep(forTimeInterval: 0.2) }
            Thread.sleep(forTimeInterval: 0.6)
            let v = value()
            check(t.name, "switching apps mid-word commits it once", v.components(separatedBy: "কেমন").count - 1 == 1 && !v.contains("kemon"),
                  "text \(String(v.suffix(20)).debugDescription)")
        }

        if t.webChat {
            openWith(t.bundle, chatPage)()                        // a page whose focused field sends on Enter
            Thread.sleep(forTimeInterval: 2.5)
            try type("ami{return}", into: pid, name: t.name)
            let title = windowTitle(pid)
            check(t.name, "Return in a send-on-Enter chat box sends the word", title.contains("sent:আমি"), "page title \(title.debugDescription)")
        } else {
            try fresh()
            try type("ami{return}tumi ", into: pid, name: t.name)
            let v = value()
            check(t.name, "Return commits the word, then makes a new line", v.contains("আমি\n") && v.trimmingCharacters(in: .whitespaces).hasSuffix("তুমি"), "text \(v.suffix(20).debugDescription)")
        }
        if let cleanup = t.cleanup { try cleanup(pid) }
    } catch let e as LostFocus {
        failures += 1
        say("  STOP \(e.app) came to the front; no more keys sent to \(t.name)")
    } catch {
        failures += 1; say("  ERROR \(error)")
    }
    select("com.apple.keylayout.US")
}

// MARK: Main

func abortRun(_ why: String) -> Never {
    say("  ABORT: \(why)")
    select(previous)
    say("\n\(passes) passed, \(failures) failed, \(skipped) skipped (ABORTED)")
    try? log.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
    exit(3)
}

guard AXIsProcessTrusted() else { print("Needs Accessibility permission (System Settings > Privacy & Security > Accessibility)."); exit(2) }
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app-compat.txt")
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bp-appcompat", isDirectory: true)
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
let page = scratch.appendingPathComponent("test.html")
try? """
<!doctype html><meta charset="utf-8"><title>Bornolipi test</title>
<textarea id="ta" autofocus style="width:90%;height:120px;font-size:20px"></textarea>
""".write(to: page, atomically: true, encoding: .utf8)
let chatPage = scratch.appendingPathComponent("chat.html")
try? """
<!doctype html><meta charset="utf-8"><title>Chat test</title>
<input id="chat" autofocus style="width:90%;font-size:20px">
<script>
document.getElementById('chat').addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.isComposing) { document.title = 'sent:' + e.target.value; e.target.value = ''; e.preventDefault(); }
});
</script>
""".write(to: chatPage, atomically: true, encoding: .utf8)
let doc = scratch.appendingPathComponent("scratch.txt")
try? "".write(to: doc, atomically: true, encoding: .utf8)
// Terminal runs `cat`, so typed lines are only echoed, never executed.
let catScript = scratch.appendingPathComponent("type-here.command")
try? "#!/bin/sh\nclear\nexec cat\n".write(to: catScript, atomically: true, encoding: .utf8)
chmod(catScript.path, 0o755)
let previous = currentSource()

func openWith(_ bundle: String, _ url: URL?, args: [String] = []) -> () -> Void {
    {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        cfg.arguments = args
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)!
        if let url { NSWorkspace.shared.open([url], withApplicationAt: app, configuration: cfg) }
        else { NSWorkspace.shared.openApplication(at: app, configuration: cfg) }
    }
}

let only = Set(CommandLine.arguments.dropFirst(2))
var targets: [Target] = [
    Target(name: "TextEdit", bundle: "com.apple.TextEdit", open: openWith("com.apple.TextEdit", doc)),
    Target(name: "Safari", bundle: "com.apple.Safari", open: openWith("com.apple.Safari", page), webChat: true),
    Target(name: "Google Chrome", bundle: "com.google.Chrome", open: openWith("com.google.Chrome", page), webChat: true),
    Target(name: "Firefox", bundle: "org.mozilla.firefox", open: openWith("org.mozilla.firefox", page), webChat: true),
    Target(name: "Cursor (VS Code engine)", bundle: "com.todesktop.230313mzl4w4u92", open: openWith("com.todesktop.230313mzl4w4u92", doc)),
    Target(name: "Terminal", bundle: "com.apple.Terminal", open: openWith("com.apple.Terminal", catScript), clear: nil),
    Target(name: "Xcode", bundle: "com.apple.dt.Xcode", open: openWith("com.apple.dt.Xcode", doc)),
    // Notes: a new scratch note (⌘N), deleted again afterwards (⌘⌫ moves it to Recently Deleted).
    Target(name: "Notes", bundle: "com.apple.Notes", open: {
        openWith("com.apple.Notes", nil)()
        Thread.sleep(forTimeInterval: 3)
        if let n = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first, frontmost() == n.processIdentifier {
            try? type("{cmd+n}", into: n.processIdentifier, name: "Notes")
        }
    }, cleanup: { pid in
        try type("{cmd+a}{bs}Bornolipi test{cmd+bs}", into: pid, name: "Notes")
    }),
    Target(name: "Microsoft Word", bundle: "com.microsoft.Word", open: openWith("com.microsoft.Word", nil)),
]
if !only.isEmpty { targets = targets.filter { only.contains($0.name) } }
// No NSApplication here: a GUI process would get the input source selection for its own windows.
guard targetsRelease else { print("This types with your installed Bornolipi keyboard: run it with BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1"); exit(2) }
guard source(ourMode) != nil else { print("\(ourMode) is not enabled; add it in System Settings first"); exit(2) }
if smoke { targets = targets.filter { $0.name == "TextEdit" } }
for t in targets { try? run(t, html: page) }
select(previous)
say("\n\(passes) passed, \(failures) failed, \(skipped) skipped")
try? log.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
