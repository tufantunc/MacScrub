import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🧼 MacScrub")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if manager.isActive {
                Button {
                    manager.deactivate()
                } label: {
                    Label(String(localized: "menu.stop_cleaning", defaultValue: "Stop Cleaning Mode"), systemImage: "stop.circle")
                }
            } else {
                Button {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    if AXIsProcessTrustedWithOptions(options) {
                        manager.activate()
                    } else {
                        PermissionGuideView.showIfNeeded()
                    }
                } label: {
                    Label(String(localized: "menu.start_cleaning", defaultValue: "Start Cleaning Mode"), systemImage: "play.circle")
                }
            }

            Divider()

            SettingsLink {
                Label(String(localized: "menu.settings", defaultValue: "Settings..."), systemImage: "gearshape")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(String(localized: "menu.quit", defaultValue: "Quit MacScrub"), systemImage: "xmark.circle")
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
