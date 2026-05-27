import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var exitKeyModifiers: ModifierKeyFlags {
        get {
            if let data = defaults.data(forKey: "exitKeyModifiers"),
               let flags = try? JSONDecoder().decode(ModifierKeyFlags.self, from: data) {
                return flags
            }
            return .defaultFlags
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "exitKeyModifiers")
            }
        }
    }

    var timeoutDuration: Int {
        get { defaults.object(forKey: "timeoutDuration") as? Int ?? 120 }
        set { defaults.set(newValue, forKey: "timeoutDuration") }
    }

    var exitOnLidOpen: Bool {
        get { defaults.object(forKey: "exitOnLidOpen") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "exitOnLidOpen") }
    }
}
