import Testing
import AppKit
@testable import MacScrub

@MainActor
@Suite("OverlayWindowController")
struct OverlayWindowControllerTests {

    /// The controller owns the overlay window via ARC (`overlayWindow`). If the
    /// window also released itself on close (`isReleasedWhenClosed == true`, the
    /// default for programmatically created NSWindows), closing it would
    /// over-release and crash with EXC_BAD_ACCESS. It must be false.
    @Test("Overlay window is not released on close")
    func testOverlayWindowNotReleasedOnClose() {
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: EventBlocker(),
            lidMonitor: LidMonitor()
        )
        let controller = OverlayWindowController()
        let window = controller.makeOverlayWindow(manager: manager)
        #expect(window != nil)
        #expect(window?.isReleasedWhenClosed == false)
    }
}
