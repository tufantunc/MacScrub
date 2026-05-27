import Foundation
import Testing
@testable import MacScrub

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {

    private func makeCleanDefaults() -> UserDefaults {
        let name = "MacScrubTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return defaults
    }

    @Test("Default values are correct")
    func testDefaultValues() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        #expect(store.exitKeyModifiers == [.command, .option, .control, .shift])
        #expect(store.timeoutDuration == 120)
        #expect(store.exitOnLidOpen == false)
    }

    @Test("Exit key modifiers can be updated")
    func testExitKeyModifiersUpdate() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        store.exitKeyModifiers = [.command, .shift]
        #expect(store.exitKeyModifiers == [.command, .shift])
    }

    @Test("Timeout duration can be updated")
    func testTimeoutDurationUpdate() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        store.timeoutDuration = 60
        #expect(store.timeoutDuration == 60)
    }

    @Test("Exit on lid open can be toggled")
    func testExitOnLidOpenToggle() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        store.exitOnLidOpen = true
        #expect(store.exitOnLidOpen == true)
    }
}
