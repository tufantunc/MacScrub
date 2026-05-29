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
