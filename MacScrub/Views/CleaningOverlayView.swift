import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var showContent = false
    @State private var breathing = false

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

                    Text("Cleaning Mode Active")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(.white)

                    Text("Keyboard and trackpad are locked.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)

                    Text("Hold all modifiers to exit")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 14) {
                        ModifierKeySquare(
                            symbol: "⌘",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.command)
                        )
                        ModifierKeySquare(
                            symbol: "⌥",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.option)
                        )
                        ModifierKeySquare(
                            symbol: "⌃",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.control)
                        )
                        ModifierKeySquare(
                            symbol: "⇧",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.shift)
                        )
                    }
                    .padding(.vertical, 4)

                    let requiredKeys = manager.settings.exitKeyModifiers
                    let pressed = manager.modifierDetector.pressedKeys.intersection(requiredKeys).count
                    let total = requiredKeys.count

                    Text("\(pressed) of \(total) keys held")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 4)

                    ProgressView(value: Double(pressed), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.4))
                        .frame(width: 120)
                        .scaleEffect(y: 0.6)
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
}
