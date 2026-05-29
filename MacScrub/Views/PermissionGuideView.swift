import SwiftUI
import ApplicationServices

struct PermissionGuideView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(String(localized: "permission.title", defaultValue: "Accessibility Permission Required"))
                .font(.headline)

            Text(String(localized: "permission.description", defaultValue: "MacScrub needs Accessibility access to block keyboard and trackpad input during cleaning."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "permission.how_to_enable", defaultValue: "How to enable:"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(String(localized: "permission.step1", defaultValue: "1. Open System Settings → Privacy & Security → Accessibility"))
                Text(String(localized: "permission.step2", defaultValue: "2. Click the + button and add MacScrub"))
                Text(String(localized: "permission.step3", defaultValue: "3. Restart MacScrub"))
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button(String(localized: "permission.open_settings", defaultValue: "Open System Settings")) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }

                Button(String(localized: "permission.done", defaultValue: "Done")) {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    static func makePanel() -> NSPanel {
        let controller = NSHostingController(rootView: PermissionGuideView())
        let panel = NSPanel(contentViewController: controller)
        panel.styleMask = [.titled, .closable]
        panel.title = "MacScrub"
        panel.isReleasedWhenClosed = false
        panel.layoutIfNeeded()
        panel.setContentSize(controller.view.fittingSize)
        return panel
    }

    static func showIfNeeded() {
        guard AXIsProcessTrusted() == false else { return }
        let panel = makePanel()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
