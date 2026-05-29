import Testing
import Foundation
import CoreGraphics
@testable import MacScrub

@MainActor
@Suite("CleaningModeManager")
struct CleaningModeManagerTests {

    @Test("Activate sets isActive to true")
    func testActivate() {
        let eventBlocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        #expect(manager.isActive == true)
        #expect(eventBlocker.startCalled == true)
    }

    @Test("Deactivate sets isActive to false")
    func testDeactivate() {
        let eventBlocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        manager.deactivate()
        #expect(manager.isActive == false)
        #expect(eventBlocker.stopCalled == true)
    }

    @Test("Activate fails gracefully when event blocker fails")
    func testActivateFailsWhenEventBlockerFails() {
        let eventBlocker = MockEventBlocker()
        eventBlocker.shouldSucceed = false
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        #expect(manager.isActive == false)
    }

    @Test("Activate starts the lid monitor")
    func testActivateStartsLidMonitor() {
        let lid = MockLidMonitor()
        let manager = CleaningModeManager(
            settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            eventBlocker: MockEventBlocker(),
            lidMonitor: lid
        )
        manager.activate()
        #expect(lid.startCalled == true)
    }

    @Test("Deactivate stops the lid monitor")
    func testDeactivateStopsLidMonitor() {
        let lid = MockLidMonitor()
        let manager = CleaningModeManager(
            settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            eventBlocker: MockEventBlocker(),
            lidMonitor: lid
        )
        manager.activate()
        manager.deactivate()
        #expect(lid.stopCalled == true)
    }

    @Test("Lid open exits cleaning when exitOnLidOpen is true")
    func testLidOpenExitsWhenEnabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.exitOnLidOpen = true
        let lid = MockLidMonitor()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: lid
        )
        manager.activate()
        lid.simulateLidOpen()
        #expect(manager.isActive == false)
    }

    @Test("Lid open does nothing when exitOnLidOpen is false")
    func testLidOpenIgnoredWhenDisabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.exitOnLidOpen = false
        let lid = MockLidMonitor()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: lid
        )
        manager.activate()
        lid.simulateLidOpen()
        #expect(manager.isActive == true)
    }

    @Test("Activate schedules idle exit deadline approximately at timeoutDuration ahead")
    func testActivateSchedulesIdleDeadline() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let remaining = manager.idleExitDeadline.timeIntervalSinceNow
        #expect(abs(remaining - 120) < 1.0)
    }

    @Test("noteActivity pushes idle deadline forward")
    func testNoteActivityPushesDeadline() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let firstDeadline = manager.idleExitDeadline
        try? await Task.sleep(for: .milliseconds(50))
        manager.noteActivity()
        #expect(manager.idleExitDeadline > firstDeadline)
    }

    @Test("Key activity from event blocker pushes idle deadline forward")
    func testEventBlockerActivityPushesDeadline() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let blocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: blocker,
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let firstDeadline = manager.idleExitDeadline
        try? await Task.sleep(for: .milliseconds(50))
        blocker.onKeyActivity?()
        #expect(manager.idleExitDeadline > firstDeadline)
    }
}

@MainActor
final class MockEventBlocker: EventBlockerProtocol {
    var isBlocking = false
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onKeyActivity: (() -> Void)?
    var startCalled = false
    var stopCalled = false
    var shouldSucceed = true

    func start() -> Bool {
        startCalled = true
        if shouldSucceed {
            isBlocking = true
        }
        return shouldSucceed
    }

    func stop() {
        stopCalled = true
        isBlocking = false
    }
}

@MainActor
final class MockLidMonitor: LidMonitorProtocol {
    var onLidOpen: (() -> Void)?
    var startCalled = false
    var stopCalled = false
    func start() { startCalled = true }
    func stop() { stopCalled = true }
    func simulateLidOpen() { onLidOpen?() }
}
