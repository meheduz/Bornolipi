import XCTest
@testable import BanglaEngine

/// The loanword setting's lifecycle: turning it off frees the retriever, turning it on rebuilds it,
/// and a build that finishes after the setting was turned off is not kept.
final class LoanwordSettingsTests: XCTestCase {
    private func loaded(_ on: Bool) throws -> Suggester {
        var settings = EngineSettings()
        settings.loanwordSuggestions = on
        return try Suggester(dataDirectory: TestData.dataDir, settings: settings, selections: SelectionStore(), loading: .immediate)
    }

    func testTurningOffReleasesAndTurningOnRebuilds() throws {
        let s = try loaded(true)
        XCTAssertNotNil(s.loanwordRetriever)
        s.settings.loanwordSuggestions = false
        XCTAssertNil(s.loanwordRetriever, "turning the setting off frees the retriever")
        XCTAssertNil(s.loanwordError)
        XCTAssertFalse(s.suggest("term").candidates.contains("টার্ম"))
        s.settings.loanwordSuggestions = true
        XCTAssertNotNil(s.loanwordRetriever, "turning it on again rebuilds it")
        XCTAssertTrue(s.suggest("term").candidates.contains("টার্ম"))
    }

    func testOtherSettingChangesKeepTheRetriever() throws {
        let s = try loaded(true)
        let r = try XCTUnwrap(s.loanwordRetriever)
        s.settings.maxCandidates = 5
        XCTAssertTrue(s.loanwordRetriever === r)
    }

    func testBuildFinishingAfterOffIsDiscarded() throws {
        let s = try loaded(true)
        let built = try XCTUnwrap(s.loanwordRetriever)
        let generation = s.currentLoanwordGeneration
        s.settings.loanwordSuggestions = false
        s.finishLoanwords(built, failure: nil, generation: generation)
        XCTAssertNil(s.loanwordRetriever, "a build started before the setting was turned off is discarded")
        // Off and on again: the old build is still out of date.
        s.settings.loanwordSuggestions = true
        let fresh = try XCTUnwrap(s.loanwordRetriever)
        s.finishLoanwords(nil, failure: nil, generation: generation)
        XCTAssertTrue(s.loanwordRetriever === fresh)
    }

    func testOnOffOnInBackgroundEndsUsable() throws {
        let s = try Suggester(dataDirectory: TestData.dataDir, settings: EngineSettings(), selections: SelectionStore(), loading: .background)
        // Each wait has its own deadline, generous for slow runs (a sanitizer build loads several times slower).
        let loaded = Date().addingTimeInterval(300)
        while !s.isDictionaryReady && Date() < loaded { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(s.isDictionaryReady)
        for _ in 0..<5 {
            s.settings.loanwordSuggestions = true
            s.settings.loanwordSuggestions = false
            _ = s.suggest("term")
        }
        s.settings.loanwordSuggestions = true
        let built = Date().addingTimeInterval(300)
        while s.loanwordRetriever == nil && s.loanwordError == nil && Date() < built {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        // Let any discarded builds finish too, then check the retriever is still there and works.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertNotNil(s.loanwordRetriever, "\(s.loanwordError.map { "\($0)" } ?? "")")
        XCTAssertTrue(s.suggest("term").candidates.contains("টার্ম"))
        s.settings.loanwordSuggestions = false
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertNil(s.loanwordRetriever)
    }

    func testOldSettingsWithoutTheKeyDecodeAsOff() throws {
        let old = #"{"suggestions":true,"autocorrect":true,"maxCandidates":7,"undoAutocorrect":true,"rememberModePerApp":false}"#
        XCTAssertFalse(try JSONDecoder().decode(EngineSettings.self, from: Data(old.utf8)).loanwordSuggestions)
        XCTAssertFalse(EngineSettings().loanwordSuggestions, "the default stays off")
    }

    func testSettingRoundTripsThroughBackup() throws {
        var settings = EngineSettings()
        settings.loanwordSuggestions = true
        let data = try JSONEncoder().encode(UserBackup(settings: settings, words: [], learned: [:]))
        XCTAssertTrue(try JSONDecoder().decode(UserBackup.self, from: data).settings.loanwordSuggestions)
        // Reset to defaults (Engine.resetAll restores a backup with EngineSettings()) turns it off.
        let reset = try JSONEncoder().encode(UserBackup(settings: EngineSettings(), words: [], learned: [:]))
        XCTAssertFalse(try JSONDecoder().decode(UserBackup.self, from: reset).settings.loanwordSuggestions)
    }
}
