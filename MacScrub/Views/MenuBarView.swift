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
                    Label("Stop Cleaning Mode", systemImage: "stop.circle")
                }
            } else {
                Text("🧼 MacScrub")
                    .font(.headline)
                Divider()
                Button {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    if AXIsProcessTrustedWithOptions(options) {
                        manager.activate()
                    }
                } label: {
                    Label("Start Cleaning Mode", systemImage: "play.circle")
                }
            }

            Divider()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }

            Divider()
            Button("Quit MacScrub") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
