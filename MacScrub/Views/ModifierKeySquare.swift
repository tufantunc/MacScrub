import SwiftUI

struct ModifierKeySquare: View {
    let symbol: String
    let label: String
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isPressed ? MSColor.tealDeep : MSColor.label)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isPressed ? MSColor.tealDeep : MSColor.tertiary)
        }
        .frame(width: 110, height: 102)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isPressed ? MSColor.tealTint : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isPressed ? MSColor.teal : Color.black.opacity(0.07),
                              lineWidth: isPressed ? 1 : 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MSColor.tealGlow, lineWidth: 4)
                .opacity(isPressed ? 1 : 0)
        )
        .offset(y: isPressed ? 2 : 0)
        .shadow(color: Color.black.opacity(0.10), radius: 7, y: 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
    }
}
