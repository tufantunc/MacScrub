import Foundation
import CoreGraphics

@MainActor
final class ModifierKeyDetector {
    let requiredKeys: ModifierKeyFlags
    let holdDuration: TimeInterval
    var onAllKeysHeld: (() -> Void)?

    private(set) var pressedKeys: ModifierKeyFlags = []
    private var holdTimer: Task<Void, Never>?

    init(requiredKeys: ModifierKeyFlags, holdDuration: TimeInterval = 3.0) {
        self.requiredKeys = requiredKeys
        self.holdDuration = holdDuration
    }

    func updateFlags(_ flags: CGEventFlags) {
        var newPressed: ModifierKeyFlags = []
        if flags.contains(.maskCommand) { newPressed.insert(.command) }
        if flags.contains(.maskAlternate) { newPressed.insert(.option) }
        if flags.contains(.maskControl) { newPressed.insert(.control) }
        if flags.contains(.maskShift) { newPressed.insert(.shift) }

        pressedKeys = newPressed

        let allHeld = requiredKeys.isSubset(of: newPressed)

        if allHeld {
            startHoldTimer()
        } else {
            cancelHoldTimer()
        }
    }

    func reset() {
        pressedKeys = []
        cancelHoldTimer()
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.holdDuration ?? 3.0))
            guard !Task.isCancelled else { return }
            self?.onAllKeysHeld?()
            self?.holdTimer = nil
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
}
