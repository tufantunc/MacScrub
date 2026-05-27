import SwiftUI
import CoreGraphics
import AVFoundation
import ApplicationServices

@MainActor
@Observable
final class CleaningModeManager {
    private(set) var isActive = false
    private(set) var modifierDetector: ModifierKeyDetector
    let settings: SettingsStore
    private var eventBlocker: EventBlockerProtocol
    private let lidMonitor: LidMonitorProtocol
    private var timeoutTask: Task<Void, Never>?
    private let exitSoundID: SystemSoundID = 1057

    var needsPermission: Bool {
        AXIsProcessTrusted() == false
    }
    weak var overlayController: OverlayWindowController?

    init(settings: SettingsStore, eventBlocker: EventBlockerProtocol, lidMonitor: LidMonitorProtocol) {
        self.settings = settings
        self.eventBlocker = eventBlocker
        self.lidMonitor = lidMonitor
        // Minimal placeholder so the non-optional property is set before
        // makeDetector() (an instance method) can be called.
        self.modifierDetector = ModifierKeyDetector(requiredKeys: [])
        self.modifierDetector = makeDetector()

        self.lidMonitor.onLidOpen = { [weak self] in
            guard let self else { return }
            if self.settings.exitOnLidOpen {
                self.deactivate()
            }
        }
    }

    private func makeDetector() -> ModifierKeyDetector {
        let detector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        detector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }
        return detector
    }

    func activate() {
        guard !isActive else { return }

        modifierDetector = makeDetector()

        eventBlocker.onFlagsChanged = { [weak self] flags in
            self?.modifierDetector.updateFlags(flags)
        }

        let success = eventBlocker.start()
        guard success else {
            eventBlocker.stop()
            return
        }

        isActive = true
        lidMonitor.start()
        overlayController?.show(manager: self)
        startTimeout()
    }

    func deactivate() {
        guard isActive else { return }
        eventBlocker.stop()
        lidMonitor.stop()
        modifierDetector.reset()
        timeoutTask?.cancel()
        timeoutTask = nil
        isActive = false
        overlayController?.hide()
        AudioServicesPlaySystemSound(exitSoundID)
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Double(self.settings.timeoutDuration)))
            guard !Task.isCancelled else { return }
            self.deactivate()
        }
    }
}
