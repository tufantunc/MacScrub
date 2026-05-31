import SwiftUI

/// App-scoped accent palette approximating the presentation mockup's oklch
/// teal tones (kept under `MSColor` to avoid shadowing SwiftUI's `Color.teal`).
enum MSColor {
    static let teal       = Color(red: 0.34, green: 0.69, blue: 0.74)
    static let tealStrong = Color(red: 0.23, green: 0.59, blue: 0.65)
    static let tealDeep   = Color(red: 0.11, green: 0.45, blue: 0.51)
    static let tealTint   = Color(red: 0.34, green: 0.69, blue: 0.74).opacity(0.16)
    static let tealGlow   = Color(red: 0.36, green: 0.71, blue: 0.74).opacity(0.45)

    static let label      = Color.black.opacity(0.84)
    static let secondary  = Color.black.opacity(0.52)
    static let tertiary   = Color.black.opacity(0.40)
}

/// Remaining hold time, formatted to one decimal (e.g. "1.6"). Empty string when
/// not currently holding. Pure and unit-tested; drives the overlay ring readout.
func holdRemainingText(holdStartDate: Date?, now: Date, duration: TimeInterval) -> String {
    guard let start = holdStartDate else { return "" }
    let remaining = max(0, duration - now.timeIntervalSince(start))
    return String(format: "%.1f", remaining)
}

/// Time left before the idle auto-terminate fires, formatted as `M:SS`
/// (e.g. "2:00"). Clamped at "0:00". Pure and unit-tested.
func autoExitRemainingText(deadline: Date, now: Date) -> String {
    let remaining = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    return String(format: "%d:%02d", remaining / 60, remaining % 60)
}

/// Fill fraction (0…1) for the idle auto-terminate ring: 0 right after a reset,
/// approaching 1 as the deadline nears. Pure and unit-tested.
func autoExitProgress(deadline: Date, now: Date, total: TimeInterval) -> Double {
    guard total > 0 else { return 0 }
    let remaining = max(0, deadline.timeIntervalSince(now))
    return min(1, max(0, 1 - remaining / total))
}
