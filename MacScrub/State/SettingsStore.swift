import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let exitKeyModifiers = "exitKeyModifiers"
        static let timeoutDuration = "timeoutDuration"
        static let exitOnLidOpen = "exitOnLidOpen"
        static let appLanguage = "appLanguage"
        static let appleLanguages = "AppleLanguages"
    }

    var exitKeyModifiers: ModifierKeyFlags {
        didSet {
            if let data = try? JSONEncoder().encode(exitKeyModifiers) {
                defaults.set(data, forKey: Keys.exitKeyModifiers)
            }
        }
    }

    var timeoutDuration: Int {
        didSet { defaults.set(timeoutDuration, forKey: Keys.timeoutDuration) }
    }

    var exitOnLidOpen: Bool {
        didSet { defaults.set(exitOnLidOpen, forKey: Keys.exitOnLidOpen) }
    }

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            applyAppLanguage()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.exitKeyModifiers),
           let flags = try? JSONDecoder().decode(ModifierKeyFlags.self, from: data) {
            self.exitKeyModifiers = flags
        } else {
            self.exitKeyModifiers = .defaultFlags
        }

        self.timeoutDuration = defaults.object(forKey: Keys.timeoutDuration) as? Int ?? 120
        self.exitOnLidOpen = defaults.object(forKey: Keys.exitOnLidOpen) as? Bool ?? false
        self.appLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .system
    }

    /// Applies the selected language by overriding `AppleLanguages`, or clears the
    /// override to follow the system. Takes effect on next launch.
    private func applyAppLanguage() {
        if let code = appLanguage.localeCode {
            defaults.set([code], forKey: Keys.appleLanguages)
        } else {
            defaults.removeObject(forKey: Keys.appleLanguages)
        }
    }
}
