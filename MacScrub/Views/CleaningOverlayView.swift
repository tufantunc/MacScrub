import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var pulsing = false
    @State private var showContent = false

    /// Configured exit keys, in fixed display order, as (symbol, label, flag).
    private var orderedExitKeys: [(symbol: String, label: String, flag: ModifierKeyFlags)] {
        let all: [(String, String, ModifierKeyFlags)] = [
            ("⌘", "Command", .command),
            ("⌥", "Option", .option),
            ("⌃", "Control", .control),
            ("⇧", "Shift", .shift),
        ]
        return all.filter { manager.settings.exitKeyModifiers.contains($0.2) }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            if manager.isActive {
                Color.black.opacity(0.28)
                glassCard
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1.0 : 0.98)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: manager.isActive)
        .onAppear {
            withAnimation { showContent = true }
            pulsing = true
        }
        .onChange(of: manager.isActive) { _, newValue in
            if !newValue { showContent = false }
        }
    }

    private var glassCard: some View {
        VStack(spacing: 0) {
            ring.padding(.bottom, 20)

            Text(String(localized: "overlay.title", defaultValue: "Cleaning Mode Active"))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MSColor.label)

            Text(String(localized: "overlay.locked", defaultValue: "Keyboard and trackpad are locked."))
                .font(.system(size: 16))
                .foregroundStyle(MSColor.secondary)
                .padding(.top, 6)

            Text(instruction)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MSColor.tertiary)
                .padding(.top, 14)

            HStack(spacing: 16) {
                ForEach(orderedExitKeys, id: \.symbol) { entry in
                    ModifierKeySquare(
                        symbol: entry.symbol,
                        label: entry.label,
                        isPressed: manager.modifierDetector.pressedKeys.contains(entry.flag)
                    )
                }
            }
            .padding(.top, 26)

            statusPill.padding(.top, 24)
        }
        .padding(.horizontal, 52)
        .padding(.top, 44)
        .padding(.bottom, 40)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 45, y: 40)
    }

    private var ring: some View {
        Group {
            if manager.modifierDetector.holdStartDate != nil {
                // Holding the exit keys → hold-to-exit progress.
                TimelineView(.animation) { context in
                    ringContent(
                        progress: holdProgress(at: context.date),
                        number: holdRemainingText(
                            holdStartDate: manager.modifierDetector.holdStartDate,
                            now: context.date,
                            duration: manager.modifierDetector.holdDuration
                        ),
                        unit: "SEC"
                    )
                }
            } else {
                // Idle → auto-terminate countdown (fills as the deadline nears).
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ringContent(
                        progress: autoExitProgress(
                            deadline: manager.idleExitDeadline,
                            now: context.date,
                            total: TimeInterval(manager.settings.timeoutDuration)
                        ),
                        number: autoExitRemainingText(
                            deadline: manager.idleExitDeadline,
                            now: context.date
                        ),
                        unit: String(localized: "overlay.auto_exit", defaultValue: "Auto-exit")
                    )
                }
            }
        }
        .frame(width: 132, height: 132)
    }

    private func ringContent(progress: Double, number: String, unit: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(MSColor.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(number)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(MSColor.tealDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(MSColor.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(MSColor.teal)
                .frame(width: 8, height: 8)
                .opacity(pulsing ? 1 : 0.4)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsing)
            Text(String(localized: "overlay.input_disabled", defaultValue: "Input is disabled"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(MSColor.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.04)))
    }

    private var instruction: String {
        let secs = Int(manager.modifierDetector.holdDuration)
        return String(format: String(localized: "overlay.instruction",
                                      defaultValue: "Hold all modifier keys for %lld seconds to exit."), secs)
    }

    private func holdProgress(at date: Date) -> Double {
        guard let start = manager.modifierDetector.holdStartDate else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / manager.modifierDetector.holdDuration))
    }
}
