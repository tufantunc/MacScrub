import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var showContent = false
    @State private var breathing = false

    /// Modifier squares to display, ordered consistently and filtered to the
    /// user's configured exit keys.
    private var orderedExitKeys: [(symbol: String, flag: ModifierKeyFlags)] {
        let all: [(String, ModifierKeyFlags)] = [
            ("⌘", .command), ("⌥", .option), ("⌃", .control), ("⇧", .shift),
        ]
        return all.filter { manager.settings.exitKeyModifiers.contains($0.1) }
    }

    var body: some View {
        ZStack {
            if manager.isActive {
                VStack(spacing: 12) {
                    Text("🧼")
                        .font(.system(size: 42))
                        .scaleEffect(breathing ? 1.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: breathing
                        )

                    Text(String(localized: "overlay.title", defaultValue: "Cleaning Mode Active"))
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(.white)

                    // Idle-reset countdown — recomputed once per second.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formattedCountdown(deadline: manager.idleExitDeadline, now: context.date))
                            .font(.system(size: 34, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    Text(String(localized: "overlay.locked", defaultValue: "Keyboard and trackpad are locked."))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)

                    Text(String(localized: "overlay.hold_to_exit", defaultValue: "Hold exit keys to exit"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 14) {
                        ForEach(orderedExitKeys, id: \.symbol) { entry in
                            ModifierKeySquare(
                                symbol: entry.symbol,
                                isPressed: manager.modifierDetector.pressedKeys.contains(entry.flag)
                            )
                        }
                    }
                    .padding(.vertical, 4)

                    // Hold-progress bar — fills 0→1 over the 3 sec while all
                    // required keys are held; 0 otherwise.
                    TimelineView(.animation) { context in
                        ProgressView(value: holdProgress(at: context.date))
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                            .frame(width: 160)
                            .scaleEffect(y: 0.6)
                    }
                }
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1.0 : 0.98)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: manager.isActive)
                .onAppear {
                    withAnimation {
                        showContent = true
                        breathing = true
                    }
                }
                .onChange(of: manager.isActive) { _, newValue in
                    if !newValue {
                        showContent = false
                        breathing = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func holdProgress(at date: Date) -> Double {
        guard let start = manager.modifierDetector.holdStartDate else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / manager.modifierDetector.holdDuration))
    }

    private func formattedCountdown(deadline: Date, now: Date) -> String {
        let remaining = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
