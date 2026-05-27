import SwiftUI
import CoreGraphics
import AVFoundation

@MainActor
@Observable
final class CleaningModeManager {
    private(set) var isActive = false
    private(set) var modifierDetector: ModifierKeyDetector
    let settings: SettingsStore
    private var eventBlocker: EventBlockerProtocol
    private let lidMonitor: LidMonitor
    private var timeoutTask: Task<Void, Never>?
    private let exitSoundID: SystemSoundID = 1057
    weak var overlayController: OverlayWindowController?

    init(settings: SettingsStore, eventBlocker: EventBlockerProtocol, lidMonitor: LidMonitor) {
        self.settings = settings
        self.eventBlocker = eventBlocker
        self.lidMonitor = lidMonitor
        self.modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )

        self.modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }

        self.lidMonitor.onLidOpen = { [weak self] in
            guard let self else { return }
            if self.settings.exitOnLidOpen {
                self.deactivate()
            }
        }
    }

    func activate() {
        guard !isActive else { return }

        modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }

        eventBlocker.onFlagsChanged = { [weak self] flags in
            self?.modifierDetector.updateFlags(flags)
        }

        let success = eventBlocker.start()
        guard success else {
            eventBlocker.stop()
            return
        }

        isActive = true
        overlayController?.show(manager: self)
        startTimeout()
    }

    func deactivate() {
        guard isActive else { return }
        eventBlocker.stop()
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
