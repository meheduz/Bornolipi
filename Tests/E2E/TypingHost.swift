// End-to-end typing test for the installed input method (run it with scripts/e2e-test.sh).
//
// The host opens a window with an NSTextView, an NSTextField and a WKWebView, selects
// Bornolipi and sends key events to its own window. AppKit hands them to the text input
// system, which forwards them to the input method process over IPC, exactly as for real typing.
// No Accessibility permission is needed because the events never leave this app.
//
//   TypingHost --out results.txt --data <Data dir>   run the tests
//   TypingHost --probe inputs.txt --mode <ID> --out results.tsv
//                                                    type each line with any input method and record the result
//   TypingHost --select <input source ID>            select an input source and exit
//   TypingHost --current                             print the current input source ID
import AppKit
import Carbon
import WebKit

let ourMode = "io.github.meheduz.inputmethod.Bornolipi.Phonetic"
var modeID = ourMode
var imeBundleID = "io.github.meheduz.inputmethod.Bornolipi"

// MARK: - Input sources

func inputSource(_ id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return list?.first
}

func currentSourceID() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

@discardableResult
func select(_ id: String) -> Bool {
    guard let s = inputSource(id) else { return false }
    return TISSelectInputSource(s) == noErr
}

// MARK: - Key events (US layout key codes)

struct Stroke {
    var code: UInt16
    var chars: String
    var ignoring: String
    var flags: NSEvent.ModifierFlags
}

let keyCodes: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
    "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "`": 50,
]
let shiftedKeys: [Character: Character] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
]

func scalar(_ v: Int) -> String { String(Character(Unicode.Scalar(UInt32(v))!)) }

let namedKeys: [String: (UInt16, String)] = [
    "space": (49, " "), "return": (36, "\r"), "enter": (76, "\u{3}"), "tab": (48, "\t"), "esc": (53, "\u{1b}"),
    "bs": (51, "\u{7f}"), "up": (126, scalar(NSUpArrowFunctionKey)), "down": (125, scalar(NSDownArrowFunctionKey)),
    "left": (123, scalar(NSLeftArrowFunctionKey)), "right": (124, scalar(NSRightArrowFunctionKey)),
]

/// Parses "ami{space}{ctrl+shift+b}{down}" into key strokes.
func strokes(_ script: String, capsLock: Bool = false) -> [Stroke] {
    var out: [Stroke] = []
    var i = script.startIndex
    while i < script.endIndex {
        if script[i] == "{", let close = script[i...].firstIndex(of: "}") {
            let token = String(script[script.index(after: i)..<close])
            var parts = token.split(separator: "+").map(String.init)
            let key = parts.removeLast()
            var flags: NSEvent.ModifierFlags = []
            for p in parts {
                switch p {
                case "ctrl": flags.insert(.control)
                case "shift": flags.insert(.shift)
                case "opt": flags.insert(.option)
                case "cmd": flags.insert(.command)
                default: fatalError("unknown modifier \(p)")
                }
            }
            if let named = namedKeys[key] {
                let (code, chars) = named
                if [123, 124, 125, 126].contains(code) { flags.formUnion([.function, .numericPad]) }
                let typed = flags.contains(.control) && code == 49 ? "\u{0}" : chars
                out.append(Stroke(code: code, chars: typed, ignoring: chars, flags: flags))
            } else if key.count == 1, let c = key.first, let code = keyCodes[c] {
                out.append(Stroke(code: code, chars: String(c), ignoring: String(c), flags: flags))
            } else {
                fatalError("unknown key \(key)")
            }
            i = script.index(after: close)
            continue
        }
        let c = script[i]
        if c == " " {
            out.append(Stroke(code: 49, chars: " ", ignoring: " ", flags: []))
        } else if let code = keyCodes[c] {
            let chars = capsLock && c.isLetter ? c.uppercased() : String(c)
            out.append(Stroke(code: code, chars: chars, ignoring: String(c), flags: capsLock ? [.capsLock] : []))
        } else if c.isUppercase, let code = keyCodes[Character(c.lowercased())] {
            out.append(Stroke(code: code, chars: String(c), ignoring: String(c), flags: [.shift]))
        } else if let base = shiftedKeys[c], let code = keyCodes[base] {
            out.append(Stroke(code: code, chars: String(c), ignoring: String(c), flags: [.shift]))
        } else {
            fatalError("no key for \(c)")
        }
        i = script.index(after: i)
    }
    return out
}

/// How key events are made. Only CGEvent-backed NSEvents reach the input method: AppKit-made events
/// (NSEvent.keyEvent) are interpreted by the text view directly, and posting to our own process needs
/// Accessibility permission. Checked with Apple's Bangla Transliteration input method.
enum EventSource: String { case appkit, cgevent, post }
var eventSource = EventSource.cgevent

func cgFlags(_ f: NSEvent.ModifierFlags) -> CGEventFlags {
    var out: CGEventFlags = []
    if f.contains(.shift) { out.insert(.maskShift) }
    if f.contains(.control) { out.insert(.maskControl) }
    if f.contains(.option) { out.insert(.maskAlternate) }
    if f.contains(.command) { out.insert(.maskCommand) }
    if f.contains(.capsLock) { out.insert(.maskAlphaShift) }
    return out
}

func send(_ s: Stroke, to window: NSWindow) {
    if eventSource != .appkit {
        for down in [true, false] {
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: s.code, keyDown: down) else { continue }
            // Characters come from the key code, flags and keyboard layout. Setting them explicitly
            // (keyboardSetUnicodeString) makes the event bypass the input method.
            cg.flags = cgFlags(s.flags)
            if eventSource == .post {
                cg.postToPid(getpid())
            } else if let e = NSEvent(cgEvent: cg) {
                NSApp.sendEvent(e)
            }
        }
        return
    }
    let t = ProcessInfo.processInfo.systemUptime
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: s.flags, timestamp: t,
                                       windowNumber: window.windowNumber, context: nil, characters: s.chars,
                                       charactersIgnoringModifiers: s.ignoring, isARepeat: false, keyCode: s.code) else { continue }
        NSApp.sendEvent(e)
    }
}

/// Runs the app's event loop (and with it the input method IPC) for a while.
func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
    let end = Date(timeIntervalSinceNow: seconds)
    while Date() < end, !done() {
        if let e = NSApp.nextEvent(matching: .any, until: min(end, Date(timeIntervalSinceNow: 0.01)), inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    }
}

// MARK: - Clients that record what the input method does

final class LoggingTextView: NSTextView {
    var calls: [String] = []
    var lastCallTime: TimeInterval = 0

    private func note(_ s: String) { calls.append(s); lastCallTime = ProcessInfo.processInfo.systemUptime }
    private func text(_ any: Any) -> String { (any as? NSAttributedString)?.string ?? (any as? String) ?? "\(any)" }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        note("mark(\(text(string)))")
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        note("insert(\(text(string)))")
        super.insertText(string, replacementRange: replacementRange)
    }
    override func unmarkText() {
        note("unmark")
        super.unmarkText()
    }
}

// MARK: - Test runner

final class Runner: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let outURL: URL
    let shotsDir: String?
    let probeLines: [String]?
    let suggester: Suggester
    var report: [String] = []
    var failures = 0
    var passes = 0

    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 460),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let textView = LoggingTextView(frame: NSRect(x: 10, y: 250, width: 620, height: 200))
    let field = NSTextField(frame: NSRect(x: 10, y: 210, width: 400, height: 30))
    let secureField = NSSecureTextField(frame: NSRect(x: 420, y: 210, width: 210, height: 30))
    let webView = WKWebView(frame: NSRect(x: 10, y: 10, width: 620, height: 190))
    var fieldActions: [String] = []
    var webLoaded = false
    var previousSource = ""

    init(outURL: URL, dataDir: URL, shotsDir: String?, probeLines: [String]?) throws {
        self.outURL = outURL
        self.shotsDir = shotsDir
        self.probeLines = probeLines
        suggester = try Suggester(dataDirectory: dataDir, loadDictionaryInBackground: false)
    }

    func log(_ s: String) { report.append(s); print(s) }

    func check(_ name: String, _ got: String, _ want: String, detail: String = "") {
        if got == want { passes += 1; log("PASS \(name)") } else {
            failures += 1
            log("FAIL \(name)\n     got:  \(got.debugDescription)\n     want: \(want.debugDescription)" + (detail.isEmpty ? "" : "\n     \(detail)"))
        }
    }

    func top(_ word: String) -> String { suggester.suggest(word).candidates.first ?? "" }
    func sentence(_ words: [String]) -> String { words.map { top($0) + " " }.joined() }

    func applicationDidFinishLaunching(_ n: Notification) {
        window.title = "Bornolipi typing test"
        textView.font = .systemFont(ofSize: 18)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        field.font = .systemFont(ofSize: 18)
        field.target = self
        field.action = #selector(fieldAction(_:))
        webView.navigationDelegate = self
        for v in [textView, field, secureField, webView] as [NSView] { window.contentView?.addSubview(v) }
        webView.loadHTMLString(Runner.page, baseURL: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { self.run() }
    }

    @objc func fieldAction(_ sender: NSTextField) { fieldActions.append(sender.stringValue) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webLoaded = true }

    func js(_ code: String) -> Any? {
        var result: Any?
        var done = false
        webView.evaluateJavaScript(code) { r, e in result = r ?? e.map { "<js error: \($0.localizedDescription)>" }; done = true }
        pump(15, until: { done })
        return done ? result : "<js timed out>"
    }

    var imePID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: imeBundleID).first?.processIdentifier
    }

    /// On-screen windows owned by the input method process (candidate panel, mode HUD).
    func imeWindows() -> [CGRect] {
        guard let pid = imePID,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: b as CFDictionary)
        }
    }

    func finish() {
        select(previousSource)
        log("\n\(passes) passed, \(failures) failed")
        try? report.joined(separator: "\n").appending("\n").write(to: outURL, atomically: true, encoding: .utf8)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Typing helpers

    /// Clears the text view. A word still being composed lives in the input method too, so it is
    /// ended with Esc first; clearing only the view would leave the input method's buffer behind.
    func resetTextView() {
        if textView.hasMarkedText(), window.firstResponder === textView {
            send(strokes("{esc}")[0], to: window)
            pump(0.3, until: { !self.textView.hasMarkedText() })
        }
        textView.string = ""
        textView.calls = []
        window.makeFirstResponder(textView)
        pump(0.05)
    }

    /// Types into the key window. For the text view, waits for each key's IPC round trip.
    func type(_ script: String, capsLock: Bool = false, settle: TimeInterval = 0.25) {
        for s in strokes(script, capsLock: capsLock) {
            let before = textView.calls.count
            send(s, to: window)
            if window.firstResponder === textView {
                pump(0.3, until: { self.textView.calls.count > before })
            } else {
                pump(0.04)
            }
        }
        pump(settle)
    }

    func typeInTextView(_ name: String, _ script: String, want: String, marked: Bool = false, capsLock: Bool = false) {
        resetTextView()
        type(script, capsLock: capsLock)
        check(name, textView.string, want, detail: "calls: " + textView.calls.joined(separator: " "))
        if textView.hasMarkedText() != marked {
            failures += 1
            log("FAIL \(name): marked text expected \(marked), got \(textView.hasMarkedText())")
        }
    }

    // MARK: The tests

    func run() {
        previousSource = currentSourceID()
        log("previous input source: \(previousSource)")
        // With cooperative activation (macOS 14+) the frontmost app may not yield at once; keep asking.
        for _ in 0..<20 where !NSApp.isActive {
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
            window.makeKeyAndOrderFront(nil)
            pump(0.5, until: { NSApp.isActive })
        }
        if !NSApp.isActive {
            // macOS may refuse programmatic activation; a click on the window always works.
            window.title = "Click this window to start the Bornolipi typing test"
            window.orderFrontRegardless()
            log("waiting up to 60 s for a click on the test window")
            pump(60, until: { NSApp.isActive })
            window.title = "Bornolipi typing test (please do not type)"
        }
        pump(3, until: { NSApp.isActive && self.webLoaded })
        log("host active: \(NSApp.isActive), key window: \(window.isKeyWindow)")
        guard NSApp.isActive else { log("FAIL host app could not become active; no events would reach the input method"); failures += 1; finish(); return }

        resetTextView()
        // Selecting a third-party input method needs it to be enabled in System Settings first.
        if currentSourceID() != modeID, !select(modeID) {
            log("FAIL could not select \(modeID). Add it in System Settings > Keyboard > Text Input first.")
            failures += 1; finish(); return
        }
        pump(2, until: { self.imePID != nil })
        log("current input source: \(currentSourceID()), input method pid: \(imePID.map(String.init) ?? "not running")")
        // The input method loads its dictionary in the background right after launch.
        pump(1.5)

        // Warm-up: a key must reach the input method. Plain insertion of "a" means the text view
        // handled the key itself and the input method never saw it.
        var answered = false
        for _ in 0..<10 where !answered {
            resetTextView()
            type("a", settle: 0.3)
            answered = textView.hasMarkedText() || textView.calls.contains { $0 != "insert(a)" }
            send(strokes("{esc}")[0], to: window)
            pump(0.2)
        }
        if !answered {
            log("WARN keys did not reach the input method (calls: \(textView.calls)); event source: \(eventSource.rawValue)")
            if probeLines == nil { failures += 1; finish(); return }
        }

        if let lines = probeLines { probe(lines); finish(); return }

        typingTests()
        candidateWindowTest()
        modeTests()
        robustnessTests()
        latencyAndStress()
        fieldTests()
        webTests()          // last: a stalled web content process must not disturb the other groups
        secureFieldTest()
        switchSourceWhileComposing()   // last: switching back to a third-party input method may be refused
        finish()
    }

    /// Types each line and records what the input method produced, with no expectations.
    /// Output: input, final text, whether marked text was left, the client calls made.
    func probe(_ lines: [String]) {
        log("input\ttext\tmarked\tcalls")
        for line in lines where !line.isEmpty {
            resetTextView()
            type(line, settle: 0.3)
            let row = [line, textView.string, textView.hasMarkedText() ? "marked" : "-", textView.calls.joined(separator: " ")]
            log(row.map { $0.replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\n", with: "\\n") }.joined(separator: "\t"))
        }
    }

    func typingTests() {
        log("\n== NSTextView")
        typeInTextView("composition shows marked text", "ami", want: "আমি", marked: true)
        typeInTextView("space commits", "ami ", want: "আমি ")
        typeInTextView("sentence", "ami banglay gan gai ", want: "আমি বাংলায় গান গাই ")
        typeInTextView("sentence matches engine", "amar sOnar bangla ami tOmay bhalobashi ",
                       want: sentence(["amar", "sOnar", "bangla", "ami", "tOmay", "bhalobashi"]))
        typeInTextView("conjuncts", "biggan kOrmo shikkha ", want: sentence(["biggan", "kOrmo", "shikkha"]))
        typeInTextView("digits", "2024 ", want: "২০২৪ ")
        typeInTextView("punctuation", "ami, tumi. ", want: "আমি, তুমি। ")
        typeInTextView("return commits then newline", "ami{return}", want: "আমি\n")
        typeInTextView("tab commits then tab", "ami{tab}", want: "আমি\t")
        typeInTextView("esc keeps English", "ami{esc}", want: "ami")
        typeInTextView("backspace edits composition", "amra{bs}{bs} ", want: top("am") + " ")
        typeInTextView("ctrl-delete discards word", "amar{ctrl+bs}", want: "")
        typeInTextView("backspace outside composition", "ami {bs}", want: "আমি")
        typeInTextView("space outside composition", "  ", want: "  ")
        typeInTextView("caps lock ignored", "ami ", want: "আমি ", capsLock: true)
        typeInTextView("left arrow commits", "ami{left}", want: "আমি")
        typeInTextView("cmd shortcut commits first", "ami{cmd+z}", want: "আমি")
        let kal = suggester.suggest("kal").candidates
        if kal.count > 2 {
            typeInTextView("down picks 2nd candidate", "kal{down} ", want: kal[1] + " ")
            typeInTextView("up wraps to last", "bari{up} ", want: suggester.suggest("bari").candidates.last! + " ")
        } else {
            failures += 1; log("FAIL engine gave too few candidates for kal: \(kal)")
        }
        typeInTextView("learned choice comes first", "kal ", want: (kal.count > 1 ? kal[1] : "?") + " ")

        // A client can drop the composition itself (NSTextInputContext.discardMarkedText). The input
        // method has to forget the word as well, or the next key continues the old one.
        resetTextView()
        type("ami", settle: 0.2)
        textView.inputContext?.discardMarkedText()
        pump(0.3)
        let afterDiscard = textView.calls.joined(separator: " ")
        textView.string = ""
        textView.calls = []
        type("tumi ", settle: 0.3)
        check("discardMarkedText resets the composition", textView.string, "তুমি ",
              detail: "calls after discard: \(afterDiscard) | then: " + textView.calls.joined(separator: " "))
    }

    func candidateWindowTest() {
        log("\n== Candidate window")
        resetTextView()
        type("bhalo", settle: 0.4)
        let shown = imeWindows()
        var caret = NSRect.zero
        if textView.hasMarkedText() {
            caret = textView.firstRect(forCharacterRange: textView.markedRange(), actualRange: nil)
        }
        // CGWindow bounds are top-left based; convert the caret to the same coordinates.
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let caretTop = screenH - caret.maxY, caretBottom = screenH - caret.minY
        log("caret (top-left coords): x \(Int(caret.minX)) y \(Int(caretTop))..\(Int(caretBottom)); input method windows: \(shown.map { "\($0.integral)" })")
        if let panel = shown.first(where: { $0.height > 40 }) {
            let below = panel.minY >= caretBottom - 1 && panel.minY <= caretBottom + 30
            let above = panel.maxY <= caretTop + 1 && panel.maxY >= caretTop - 30
            let aligned = abs(panel.minX - caret.minX) < 40
            if (below || above) && aligned { passes += 1; log("PASS candidate panel is next to the caret") } else {
                failures += 1; log("FAIL candidate panel not next to the caret")
            }
            if let dir = shotsDir {
                let r = panel.union(CGRect(x: caret.minX - 20, y: caretTop - 20, width: 300, height: 1)).insetBy(dx: -20, dy: -20)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-R\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", dir + "/candidates.png"]
                try? p.run(); p.waitUntilExit()
            }
        } else {
            failures += 1; log("FAIL no candidate panel on screen while composing")
        }
        send(strokes("{space}")[0], to: window)
        pump(0.4)
        if imeWindows().contains(where: { $0.height > 40 }) { failures += 1; log("FAIL candidate panel still visible after commit") } else {
            passes += 1; log("PASS candidate panel hides after commit")
        }
    }

    func modeTests() {
        log("\n== Bangla / English switching")
        typeInTextView("ctrl-shift-space toggles to English and back", "{ctrl+shift+b}hello {ctrl+shift+b}ami ", want: "hello আমি ")
        typeInTextView("toggle commits the composition", "ami{ctrl+shift+b}{ctrl+shift+b}", want: "আমি")
    }

    func robustnessTests() {
        log("\n== Robustness")
        var script = "", want = ""
        for _ in 0..<20 { script += "ami{ctrl+shift+b}ami{ctrl+shift+b}"; want += "আমিami" }
        typeInTextView("20 rapid Bangla/English switches", script, want: want)

        // Focus moves to another field while a word is being composed: the word must be committed.
        resetTextView()
        type("ami", settle: 0.2)
        window.makeFirstResponder(field)
        pump(0.5)
        check("focus change commits the word", textView.string, "আমি", detail: "calls: " + textView.calls.joined(separator: " "))
        if textView.hasMarkedText() { failures += 1; log("FAIL marked text left behind after a focus change") }
        field.stringValue = ""

        // The app is hidden (switching to another app) while composing.
        resetTextView()
        type("tumi", settle: 0.2)
        NSApp.hide(nil)
        pump(0.6)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        pump(0.8)
        check("switching apps commits the word", textView.string, "তুমি", detail: "calls: " + textView.calls.joined(separator: " "))
        if textView.hasMarkedText() { failures += 1; log("FAIL marked text left behind after switching apps") }
        typeInTextView("typing works after returning", "bhalo ", want: top("bhalo") + " ")
    }

    func secureFieldTest() {
        log("\n== Password field")
        secureField.stringValue = ""
        window.makeFirstResponder(secureField)
        pump(0.3)
        type("ami", settle: 0.3)
        // macOS turns input methods off in secure fields; the letters arrive as typed.
        check("password field gets plain letters", secureField.stringValue, "ami")
        secureField.stringValue = ""
    }

    func switchSourceWhileComposing() {
        log("\n== Input source change while composing")
        resetTextView()
        type("ami", settle: 0.2)
        select(previousSource)
        pump(0.6)
        check("switching away commits the word", textView.string, "আমি", detail: "calls: " + textView.calls.joined(separator: " "))
        if textView.hasMarkedText() { failures += 1; log("FAIL marked text left behind after switching away") }
        select(modeID)
        pump(0.6)
    }

    func latencyAndStress() {
        log("\n== Latency and stress")
        resetTextView()
        var samples: [Double] = []
        for s in strokes("bishwobidyaloyer ") {
            let before = textView.calls.count
            let t0 = ProcessInfo.processInfo.systemUptime
            send(s, to: window)
            pump(0.5, until: { self.textView.calls.count > before })
            if textView.calls.count > before { samples.append((textView.lastCallTime - t0) * 1000) }
        }
        samples.sort()
        if !samples.isEmpty {
            log(String(format: "key -> marked text round trip: median %.2f ms, max %.2f ms (%d keys)", samples[samples.count / 2], samples.last!, samples.count))
        }
        let words = "ami tomake bhalobashi amar sOnar bangla ekhane shobai bhalo ache ajke akash khub sundor".split(separator: " ").map(String.init)
        var script = ""
        for _ in 0..<4 { script += words.joined(separator: " ") + " " }
        resetTextView()
        let t0 = Date()
        for s in strokes(script) { send(s, to: window); pump(0.002) }
        pump(1.0)
        let ms = Date().timeIntervalSince(t0) * 1000
        check("fast typing \(script.count) keys loses nothing", textView.string, String(repeating: sentence(words), count: 4))
        log(String(format: "%d keys in %.0f ms", script.count, ms))
    }

    func fieldTests() {
        log("\n== NSTextField (field editor)")
        field.stringValue = ""
        fieldActions = []
        window.makeFirstResponder(field)
        pump(0.1)
        type("ami banglay ", settle: 0.3)
        check("text field typing", field.stringValue, "আমি বাংলায় ")
        field.stringValue = ""
        window.makeFirstResponder(field)
        pump(0.1)
        type("tumi{return}", settle: 0.3)
        check("return in text field sends the committed word", fieldActions.last ?? "<no action>", "তুমি")
    }

    func webTests() {
        log("\n== WKWebView (web text fields)")
        window.makeFirstResponder(webView)
        _ = js("document.getElementById('ta').focus(); log.length = 0; 1")
        pump(0.2)
        type("ami banglay gan gai ", settle: 0.4)
        check("textarea typing", "\(js("document.getElementById('ta').value") ?? "nil")", "আমি বাংলায় গান গাই ")
        let events = js("JSON.stringify(log.filter(e => e[1].startsWith('composition')).slice(0, 6))") as? String ?? ""
        log("composition events (first 6): \(events)")
        if events.contains("compositionend") { passes += 1; log("PASS page sees composition events") } else {
            failures += 1; log("FAIL page saw no compositionend event")
        }
        _ = js("document.getElementById('chat').focus(); sent.length = 0; 1")
        pump(0.2)
        type("ami{return}", settle: 0.4)
        let sent = js("JSON.stringify(sent)") as? String ?? ""
        check("enter in a send-on-enter chat box sends the committed word", sent, "[\"আমি\"]",
              detail: "chat box now holds " + (js("document.getElementById('chat').value") as? String ?? "?").debugDescription)
    }

    static let page = """
    <!doctype html><meta charset="utf-8">
    <textarea id="ta" style="width:580px;height:70px;font-size:18px"></textarea><br>
    <input id="chat" style="width:580px;font-size:18px">
    <script>
    window.log = []; window.sent = [];
    for (const id of ['ta', 'chat']) {
      const el = document.getElementById(id);
      for (const t of ['compositionstart', 'compositionupdate', 'compositionend'])
        el.addEventListener(t, e => log.push([id, t, e.data]));
      el.addEventListener('keydown', e => log.push([id, 'keydown', e.key, e.keyCode, e.isComposing]));
    }
    document.getElementById('chat').addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.isComposing) { sent.push(e.target.value); e.target.value = ''; e.preventDefault(); }
    });
    </script>
    """
}

@main
struct TypingHostMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--select"), i + 1 < args.count { exit(select(args[i + 1]) ? 0 : 1) }
        if args.contains("--current") { print(currentSourceID()); exit(0) }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let out = URL(fileURLWithPath: value("--out") ?? "e2e-results.txt")
        let data = URL(fileURLWithPath: value("--data") ?? "Data")
        if let m = value("--mode") {
            modeID = m
            // Input mode IDs extend their input method's bundle ID, e.g. com.apple.inputmethod.TransliterationIM.bn.
            if m != ourMode, let s = inputSource(m), let p = TISGetInputSourceProperty(s, kTISPropertyBundleID) {
                imeBundleID = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }
        }
        if let e = value("--events").flatMap(EventSource.init(rawValue:)) { eventSource = e }
        let probe = value("--probe").flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?
            .components(separatedBy: "\n")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        do {
            let runner = try Runner(outURL: out, dataDir: data, shotsDir: value("--shots"), probeLines: probe)
            app.delegate = runner
            app.run()
        } catch {
            try? "FAIL could not load engine data: \(error)\n".write(to: out, atomically: true, encoding: .utf8)
            exit(2)
        }
    }
}
