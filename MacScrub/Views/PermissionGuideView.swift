import SwiftUI
import ApplicationServices

struct PermissionGuideView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Accessibility Permission Required")
                .font(.headline)

            Text("MacScrub needs Accessibility access to block keyboard and trackpad input during cleaning.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("How to enable:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("1. Open System Settings → Privacy & Security → Accessibility")
                Text("2. Click the + button and add MacScrub")
                Text("3. Restart MacScrub")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Open System Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }

                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    static func showIfNeeded() {
        guard AXIsProcessTrusted() == false else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "MacScrub"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PermissionGuideView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
