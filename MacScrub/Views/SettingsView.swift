import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section(String(localized: "settings.exit_keys", defaultValue: "Exit Keys")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.hold_modifiers_description", defaultValue: "Hold these modifier keys to exit cleaning mode:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Toggle(String(localized: "settings.command", defaultValue: "⌘ Command"), isOn: modifierBinding(.command))
                            .toggleStyle(.checkbox)
                        Toggle(String(localized: "settings.option", defaultValue: "⌥ Option"), isOn: modifierBinding(.option))
                            .toggleStyle(.checkbox)
                        Toggle(String(localized: "settings.control", defaultValue: "⌃ Control"), isOn: modifierBinding(.control))
                            .toggleStyle(.checkbox)
                        Toggle(String(localized: "settings.shift", defaultValue: "⇧ Shift"), isOn: modifierBinding(.shift))
                            .toggleStyle(.checkbox)
                    }
                }
            }

            Section(String(localized: "settings.timeout", defaultValue: "Timeout")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "settings.auto_exit_after", defaultValue: "Auto-exit after:"))
                        Spacer()
                        Text(String(localized: "\(settings.timeoutDuration) seconds"))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.timeoutDuration) },
                        set: { settings.timeoutDuration = Int($0) }
                    ), in: 30...300, step: 15)
                }
            }

            Section(String(localized: "settings.lid", defaultValue: "Lid")) {
                Toggle(String(localized: "settings.exit_on_lid_open", defaultValue: "Exit cleaning mode when lid is opened"), isOn: $settings.exitOnLidOpen)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }

    private func modifierBinding(_ key: ModifierKeyFlags) -> Binding<Bool> {
        Binding(
            get: { settings.exitKeyModifiers.contains(key) },
            set: { isOn in
                let current = settings.exitKeyModifiers
                let minimum = settings.exitKeyModifiers.count > 1 || isOn
                guard minimum else { return }
                if isOn {
                    settings.exitKeyModifiers = current.union(key)
                } else {
                    settings.exitKeyModifiers = current.subtracting(key)
                }
            }
        )
    }
}
