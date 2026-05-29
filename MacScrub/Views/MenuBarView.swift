import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section(manager.isActive
                ? String(localized: "menu.status_cleaning", defaultValue: "Cleaning…")
                : String(localized: "menu.status_ready", defaultValue: "MacScrub · Ready")) {
            if manager.isActive {
                Button(String(localized: "menu.stop_cleaning", defaultValue: "Stop Cleaning Mode")) {
                    manager.deactivate()
                }
            } else {
                Button(String(localized: "menu.start_cleaning", defaultValue: "Start Cleaning Mode")) {
                    startCleaning()
                }
            }
        }

        Divider()

        Button(String(localized: "menu.open", defaultValue: "Open MacScrub")) {
            openMainWindow()
        }
        Button(String(localized: "menu.settings", defaultValue: "Settings...")) {
            openMainWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(String(localized: "menu.quit", defaultValue: "Quit MacScrub")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func startCleaning() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            manager.activate()
        } else {
            PermissionGuideView.showIfNeeded()
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
