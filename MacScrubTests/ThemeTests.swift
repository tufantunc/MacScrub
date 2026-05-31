import Testing
import Foundation
@testable import MacScrub

@Suite("holdRemainingText")
struct HoldRemainingTextTests {

    @Test("Returns empty string when not holding")
    func testNilHoldStart() {
        #expect(holdRemainingText(holdStartDate: nil, now: Date(), duration: 3) == "")
    }

    @Test("Returns full duration at the moment hold starts")
    func testFullAtStart() {
        let now = Date()
        #expect(holdRemainingText(holdStartDate: now, now: now, duration: 3) == "3.0")
    }

    @Test("Returns remaining seconds partway through the hold")
    func testPartway() {
        let start = Date()
        let now = start.addingTimeInterval(1.4)
        #expect(holdRemainingText(holdStartDate: start, now: now, duration: 3) == "1.6")
    }

    @Test("Clamps to 0.0 past the hold duration")
    func testClampsAtZero() {
        let start = Date()
        let now = start.addingTimeInterval(5)
        #expect(holdRemainingText(holdStartDate: start, now: now, duration: 3) == "0.0")
    }
}

@Suite("autoExit countdown")
struct AutoExitCountdownTests {

    @Test("Remaining time formats as M:SS")
    func testRemainingFormat() {
        let now = Date()
        #expect(autoExitRemainingText(deadline: now.addingTimeInterval(125), now: now) == "2:05")
        #expect(autoExitRemainingText(deadline: now.addingTimeInterval(45), now: now) == "0:45")
    }

    @Test("Remaining time clamps to 0:00 past the deadline")
    func testRemainingClamps() {
        let now = Date()
        #expect(autoExitRemainingText(deadline: now, now: now) == "0:00")
        #expect(autoExitRemainingText(deadline: now.addingTimeInterval(-10), now: now) == "0:00")
    }

    @Test("Progress is 0 at a fresh reset and 1 at the deadline")
    func testProgressEndpoints() {
        let now = Date()
        #expect(autoExitProgress(deadline: now.addingTimeInterval(120), now: now, total: 120) == 0)
        #expect(autoExitProgress(deadline: now, now: now, total: 120) == 1)
    }

    @Test("Progress is 0.5 halfway to the deadline")
    func testProgressMidpoint() {
        let now = Date()
        #expect(autoExitProgress(deadline: now.addingTimeInterval(60), now: now, total: 120) == 0.5)
    }
}
