import CoreGraphics

struct ModifierKeyFlags: OptionSet, Codable, Equatable {
    let rawValue: UInt64

    static let command = ModifierKeyFlags(rawValue: CGEventFlags.maskCommand.rawValue)
    static let option = ModifierKeyFlags(rawValue: CGEventFlags.maskAlternate.rawValue)
    static let control = ModifierKeyFlags(rawValue: CGEventFlags.maskControl.rawValue)
    static let shift = ModifierKeyFlags(rawValue: CGEventFlags.maskShift.rawValue)

    static let defaultFlags: ModifierKeyFlags = [.command, .option, .control, .shift]

    var count: Int {
        rawValue.nonzeroBitCount
    }
}
