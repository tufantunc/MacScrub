import SwiftUI

@MainActor
class OverlayWindowController {
    var overlayWindow: NSWindow?

    func show(manager: CleaningModeManager) {
        guard overlayWindow == nil else { return }
        let screen = NSScreen.main!
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: NSScreen.main
        )
        window.level = .statusBar + 1
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSHostingView(rootView: CleaningOverlayView(manager: manager))
        view.frame = screen.frame
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    func hide() {
        overlayWindow?.close()
        overlayWindow = nil
    }
}

@main
struct MacScrubApp: App {
    @State private var settings = SettingsStore()
    @State private var eventBlocker = EventBlocker()
    @State private var lidMonitor = LidMonitor()
    @State private var manager: CleaningModeManager
    private let overlayController = OverlayWindowController()

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
                .onAppear {
                    manager.overlayController = overlayController
                }
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? .blue : .secondary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
