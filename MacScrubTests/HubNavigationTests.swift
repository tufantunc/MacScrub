import Testing
@testable import MacScrub

@MainActor
@Suite("HubNavigation")
struct HubNavigationTests {

    @Test("Defaults to the main view")
    func testDefault() {
        #expect(HubNavigation().view == .main)
    }

    @Test("Switches to preferences and back to main")
    func testSwitch() {
        let nav = HubNavigation()
        nav.view = .preferences
        #expect(nav.view == .preferences)
        nav.view = .main
        #expect(nav.view == .main)
    }
}
