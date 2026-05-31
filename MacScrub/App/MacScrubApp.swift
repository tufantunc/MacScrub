import SwiftUI

@MainActor
class OverlayWindowController {
    var overlayWindow: NSWindow?

    func makeOverlayWindow(manager: CleaningModeManager) -> NSWindow? {
        guard let screen = NSScreen.main else { return nil }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // This controller owns the window via `overlayWindow` (ARC). Without
        // this, NSWindow defaults to releasing itself on close, which would
        // double-free when ARC also releases it → EXC_BAD_ACCESS on deactivate.
        window.isReleasedWhenClosed = false
        window.level = .statusBar + 1
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSHostingView(rootView: CleaningOverlayView(manager: manager))
        view.frame = screen.frame
        window.contentView = view
        return window
    }

    func show(manager: CleaningModeManager) {
        guard overlayWindow == nil else { return }
        guard let window = makeOverlayWindow(manager: manager) else { return }
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
    @State private var settings: SettingsStore
    @State private var eventBlocker: EventBlocker
    @State private var lidMonitor: LidMonitor
    @State private var manager: CleaningModeManager
    @State private var nav: HubNavigation
    @State private var updateChecker: UpdateChecker
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
        let nav = HubNavigation()
        let updateChecker = UpdateChecker()
        self._settings = State(initialValue: settings)
        self._eventBlocker = State(initialValue: eventBlocker)
        self._lidMonitor = State(initialValue: lidMonitor)
        self._manager = State(initialValue: manager)
        self._nav = State(initialValue: nav)
        self._updateChecker = State(initialValue: updateChecker)
    }

    var body: some Scene {
        Window("MacScrub", id: "main") {
            MainWindowView(manager: manager, settings: settings, nav: nav, updateChecker: updateChecker)
                .onAppear {
                    manager.overlayController = overlayController
                    NSApp.activate(ignoringOtherApps: true)
                }
                .task {
                    await updateChecker.checkForUpdate()
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(manager: manager, settings: settings, nav: nav, updateChecker: updateChecker)
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? AnyShapeStyle(MSColor.teal) : AnyShapeStyle(.secondary))
        }
        .menuBarExtraStyle(.menu)
    }
}
