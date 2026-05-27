import Testing
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
            lidMonitor: LidMonitor()
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
            lidMonitor: LidMonitor()
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
            lidMonitor: LidMonitor()
        )
        manager.activate()
        #expect(manager.isActive == false)
    }
}

@MainActor
final class MockEventBlocker: EventBlockerProtocol {
    var isBlocking = false
    var onFlagsChanged: ((CGEventFlags) -> Void)?
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
