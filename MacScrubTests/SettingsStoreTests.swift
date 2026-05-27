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

    @Test("Settings persist across store instances")
    func testPersistenceAcrossInstances() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.timeoutDuration = 60
        store.exitOnLidOpen = true
        store.exitKeyModifiers = [.command, .shift]

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.timeoutDuration == 60)
        #expect(reloaded.exitOnLidOpen == true)
        #expect(reloaded.exitKeyModifiers == [.command, .shift])
    }

    @Test("Default language is system")
    func testDefaultLanguage() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        #expect(store.appLanguage == .system)
    }

    @Test("Selecting a language persists across instances")
    func testLanguagePersists() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .chinese

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.appLanguage == .chinese)
    }

    @Test("Selecting a language writes AppleLanguages")
    func testLanguageWritesAppleLanguages() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .turkish
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["tr"])
    }

    @Test("Selecting System clears AppleLanguages override")
    func testSystemLanguageClearsOverride() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .turkish
        store.appLanguage = .system
        // Clearing the override removes our explicit selection; the resolved value
        // then falls back to the system (which may be non-nil on localized machines).
        #expect(defaults.stringArray(forKey: "AppleLanguages") != ["tr"])
    }
}
