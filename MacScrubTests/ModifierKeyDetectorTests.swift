import Testing
import CoreGraphics
@testable import MacScrub

@MainActor
@Suite("ModifierKeyDetector")
struct ModifierKeyDetectorTests {

    @Test("All required keys pressed triggers callback after duration")
    func testAllKeysPressedTriggersCallback() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        detector.updateFlags(flags)

        try? await Task.sleep(for: .seconds(0.2))
        #expect(callbackFired == true)
    }

    @Test("Releasing a key resets the timer")
    func testReleasingKeyResetsTimer() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let allFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        detector.updateFlags(allFlags)

        try? await Task.sleep(for: .seconds(0.05))

        let partialFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        detector.updateFlags(partialFlags)

        try? await Task.sleep(for: .seconds(0.15))
        #expect(callbackFired == false)
    }

    @Test("Fewer than required keys does not trigger callback")
    func testPartialKeysNoCallback() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let partialFlags: CGEventFlags = [.maskCommand, .maskAlternate]
        detector.updateFlags(partialFlags)

        try? await Task.sleep(for: .seconds(0.2))
        #expect(callbackFired == false)
    }

    @Test("Pressed keys are tracked correctly")
    func testPressedKeysTracking() {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 3.0
        )

        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        detector.updateFlags(flags)

        #expect(detector.pressedKeys.contains(.command))
        #expect(detector.pressedKeys.contains(.option))
        #expect(detector.pressedKeys.contains(.control))
        #expect(!detector.pressedKeys.contains(.shift))
    }

    @Test("Hold start date is nil before all required keys are held")
    func testHoldStartDateNilInitially() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags(.maskCommand)
        #expect(detector.holdStartDate == nil)
    }

    @Test("Hold start date is set when all required keys are held")
    func testHoldStartDateSetWhenAllHeld() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        let start = detector.holdStartDate
        #expect(start != nil)
        if let start { #expect(abs(start.timeIntervalSinceNow) < 0.5) }
    }

    @Test("Releasing a required key clears hold start date")
    func testHoldStartDateClearedOnRelease() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        #expect(detector.holdStartDate != nil)
        detector.updateFlags(.maskCommand)
        #expect(detector.holdStartDate == nil)
    }

    @Test("Reset clears hold start date")
    func testHoldStartDateClearedByReset() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        detector.reset()
        #expect(detector.holdStartDate == nil)
    }

    @Test("Hold start date is stable across repeated full-press events")
    func testHoldStartDateStableOnRepeatedFullPress() async {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        let first = detector.holdStartDate
        #expect(first != nil)
        try? await Task.sleep(for: .milliseconds(50))
        detector.updateFlags([.maskCommand, .maskShift])
        #expect(detector.holdStartDate == first)
    }
}
