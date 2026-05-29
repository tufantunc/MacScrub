import Testing
import AppKit
@testable import MacScrub

@MainActor
@Suite("PermissionGuideView")
struct PermissionGuideViewTests {
    @Test("Permission panel sizes to fit its content (no fixed-height mismatch)")
    func testPanelFitsContent() {
        let panel = PermissionGuideView.makePanel()
        let contentHeight = panel.contentView!.frame.height
        let fittingHeight = panel.contentView!.fittingSize.height
        #expect(fittingHeight > 0)
        #expect(abs(contentHeight - fittingHeight) < 1.0)
    }
}
