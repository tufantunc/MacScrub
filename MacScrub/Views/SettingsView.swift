import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Exit Keys") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold these modifier keys to exit cleaning mode:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Toggle("⌘ Command", isOn: modifierBinding(.command))
                            .toggleStyle(.checkbox)
                        Toggle("⌥ Option", isOn: modifierBinding(.option))
                            .toggleStyle(.checkbox)
                        Toggle("⌃ Control", isOn: modifierBinding(.control))
                            .toggleStyle(.checkbox)
                        Toggle("⇧ Shift", isOn: modifierBinding(.shift))
                            .toggleStyle(.checkbox)
                    }
                }
            }

            Section("Timeout") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Auto-exit after:")
                        Spacer()
                        Text("\(settings.timeoutDuration) seconds")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.timeoutDuration) },
                        set: { settings.timeoutDuration = Int($0) }
                    ), in: 30...300, step: 15)
                }
            }

            Section("Lid") {
                Toggle("Exit cleaning mode when lid is opened", isOn: $settings.exitOnLidOpen)
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
