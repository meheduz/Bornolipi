import XCTest
@testable import InstallKit

final class KeyboardRestartTests: XCTestCase {
    func testKeyboardNeverQuitsWhileBornolipiIsInUseUnlessAsked() {
        let inUse = KeyboardRestart.decide(.whenSafe, bornolipiSelected: true)
        XCTAssertFalse(inUse.quit)
        XCTAssertTrue(inUse.quitOnSourceChange)
        XCTAssertEqual(inUse.reply, .waiting)

        let idle = KeyboardRestart.decide(.whenSafe, bornolipiSelected: false)
        XCTAssertTrue(idle.quit)
        XCTAssertEqual(idle.reply, .quitting)

        let asked = KeyboardRestart.decide(.now, bornolipiSelected: true)
        XCTAssertTrue(asked.commitFirst, "a user-requested restart commits the unfinished word first")
        XCTAssertTrue(asked.quit)
    }

    /// The real message path, on a private channel so no installed keyboard ever sees it.
    @MainActor
    private func roundTrip(answer: KeyboardRestart.Reply?, stopsRunning: Bool) async -> KeyboardRestart.Outcome {
        var running = true
        let channel = KeyboardRestart.Channel(prefix: "io.github.meheduz.Bornolipi.test.\(UUID().uuidString)") { running }
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: channel.request, object: nil, queue: .main) { note in
            guard let answer, let token = note.object as? String else { return }
            KeyboardRestart.answer(token: token, answer, on: channel)
            if stopsRunning { running = false }
        }
        defer { center.removeObserver(observer) }
        return await KeyboardRestart.request(.whenSafe, on: channel, timeout: 1)
    }

    func testOutcomes() async {
        let restarted = await roundTrip(answer: .quitting, stopsRunning: true)
        XCTAssertEqual(restarted, .restarted)
        let waiting = await roundTrip(answer: .waiting, stopsRunning: false)
        XCTAssertEqual(waiting, .waiting)
        let silent = await roundTrip(answer: nil, stopsRunning: false)
        XCTAssertEqual(silent, .noAnswer, "an old keyboard that never answers is reported, not killed")
        let saidQuitButDidNot = await roundTrip(answer: .quitting, stopsRunning: false)
        XCTAssertEqual(saidQuitButDidNot, .noAnswer)
    }

    @MainActor
    func testNotRunning() async {
        let channel = KeyboardRestart.Channel(prefix: "io.github.meheduz.Bornolipi.test.none") { false }
        let outcome = await KeyboardRestart.request(.now, on: channel)
        XCTAssertEqual(outcome, .notRunning)
    }
}
