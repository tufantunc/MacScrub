import SwiftUI

struct ModifierKeySquare: View {
    let symbol: String
    let isPressed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isPressed ? Color.white.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .frame(width: 46, height: 46)
            .overlay {
                Text(symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(isPressed ? .white : .white.opacity(0.3))
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}
