#if canImport(AppKit)
import AppKit

/// How the app hands a freshly installed keyboard over to the running one without losing what the
/// user is typing. The app never decides when the keyboard may stop; it asks, and the keyboard answers:
///
/// - `whenSafe`: the keyboard quits only while Bornolipi is not the selected input source (so no word
///   can be in progress) and answers "quitting". Otherwise it answers "waiting", and quits by itself
///   the moment the user switches to another input source.
/// - `now` (only after the user clicks a Restart button): the keyboard first commits any unfinished
///   word into the document, then quits.
///
/// macOS starts the keyboard again, from the new files, the next time it is used. The messages are
/// distributed notifications, which stay within the user's login session.
public enum KeyboardRestart {
    /// The pair of message names, and how to tell whether anyone is listening. Tests use their own.
    public struct Channel {
        public let request: Notification.Name
        public let reply: Notification.Name
        let isRunning: () -> Bool
        public init(prefix: String, isRunning: @escaping () -> Bool) {
            request = Notification.Name(prefix + ".restart")
            reply = Notification.Name(prefix + ".restartReply")
            self.isRunning = isRunning
        }
        /// The release keeps its original names; a test identity gets its own, so test builds can
        /// never ask the real keyboard to restart.
        public static let keyboard = Channel(prefix: KeyboardIdentity.isTestIdentity ? KeyboardIdentity.bundleID + ".restartChannel" : "io.github.meheduz.Bornolipi.keyboard") {
            !NSRunningApplication.runningApplications(withBundleIdentifier: Keyboard.bundleID).isEmpty
        }
    }

    public enum Mode: String { case whenSafe, now }
    public enum Reply: String { case quitting, waiting }

    /// The keyboard's rule. It may quit only when no word can be in progress (Bornolipi is not the
    /// selected input source) or when the user asked for a restart, after committing the word.
    public struct Decision: Equatable {
        public let reply: Reply
        public let commitFirst: Bool
        public let quit: Bool
        public let quitOnSourceChange: Bool
    }

    public static func decide(_ mode: Mode, bornolipiSelected: Bool) -> Decision {
        switch (mode, bornolipiSelected) {
        case (.now, _): return Decision(reply: .quitting, commitFirst: true, quit: true, quitOnSourceChange: false)
        case (.whenSafe, false): return Decision(reply: .quitting, commitFirst: false, quit: true, quitOnSourceChange: false)
        case (.whenSafe, true): return Decision(reply: .waiting, commitFirst: false, quit: false, quitOnSourceChange: true)
        }
    }

    public enum Outcome: Equatable {
        /// No keyboard was running; the new one is used from the next keystroke.
        case notRunning
        /// The keyboard quit; the new one is used from the next keystroke.
        case restarted
        /// Bornolipi is in use; the new keyboard takes over when the user switches input source or restarts it.
        case waiting
        /// The running keyboard does not answer (a version from before this protocol).
        case noAnswer
    }

    /// Asks the running keyboard to restart and waits up to `timeout` seconds for its answer.
    @MainActor
    public static func request(_ mode: Mode, on channel: Channel = .keyboard, timeout: TimeInterval = 3) async -> Outcome {
        guard channel.isRunning() else { return .notRunning }
        let token = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        let reply: Reply? = await withCheckedContinuation { continuation in
            var finished = false
            var observer: NSObjectProtocol?
            func finish(_ value: Reply?) {
                guard !finished else { return }
                finished = true
                if let observer { center.removeObserver(observer) }
                continuation.resume(returning: value)
            }
            observer = center.addObserver(forName: channel.reply, object: token, queue: .main) { note in
                finish((note.userInfo?["reply"] as? String).flatMap(Reply.init(rawValue:)))
            }
            center.postNotificationName(channel.request, object: token, userInfo: ["mode": mode.rawValue], deliverImmediately: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
        switch reply {
        case .waiting: return .waiting
        case .quitting:
            let deadline = Date().addingTimeInterval(timeout)
            while channel.isRunning(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
            return channel.isRunning() ? .noAnswer : .restarted
        case nil: return .noAnswer
        }
    }

    /// The keyboard's side: answers a request.
    public static func answer(token: String, _ reply: Reply, on channel: Channel = .keyboard) {
        DistributedNotificationCenter.default().postNotificationName(
            channel.reply, object: token, userInfo: ["reply": reply.rawValue], deliverImmediately: true)
    }
}
#endif
