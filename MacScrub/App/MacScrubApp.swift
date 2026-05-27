import SwiftUI

@main
struct MacScrubApp: App {
    @State private var settings = SettingsStore()
    @State private var eventBlocker = EventBlocker()
    @State private var lidMonitor = LidMonitor()
    @State private var manager: CleaningModeManager

    init() {
        let settings = SettingsStore()
        let eventBlocker = EventBlocker()
        let lidMonitor = LidMonitor()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: eventBlocker,
            lidMonitor: lidMonitor
        )
        self._settings = State(initialValue: settings)
        self._eventBlocker = State(initialValue: eventBlocker)
        self._lidMonitor = State(initialValue: lidMonitor)
        self._manager = State(initialValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? .blue : .secondary)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
