import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager

    var body: some View {
        VStack(alignment: .leading) {
            if manager.isActive {
                Text("🧼 MacScrub")
                    .font(.headline)
                Divider()
                Button {
                    manager.deactivate()
                } label: {
                    Label(String(localized: "menu.stop_cleaning", defaultValue: "Stop Cleaning Mode"), systemImage: "stop.circle")
                }
            } else {
                Text("🧼 MacScrub")
                    .font(.headline)
                Divider()
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

            Divider()
            Button(String(localized: "menu.quit", defaultValue: "Quit MacScrub")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
