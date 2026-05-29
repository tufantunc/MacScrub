import SwiftUI
import ApplicationServices

struct MainWindowView: View {
    @Bindable var manager: CleaningModeManager
    @Bindable var settings: SettingsStore

    @State private var showExitKeys = false
    @State private var showRestartAlert = false

    var body: some View {
        idleView
        .frame(width: 360)
        .alert(
            String(localized: "language.restart_title", defaultValue: "Restart Required"),
            isPresented: $showRestartAlert
        ) {
            Button(String(localized: "language.restart_quit", defaultValue: "Quit Now")) {
                NSApplication.shared.terminate(nil)
            }
            Button(String(localized: "language.restart_later", defaultValue: "Later"), role: .cancel) {}
        } message: {
            Text(String(localized: "language.restart_message",
                        defaultValue: "Quit and reopen MacScrub to apply the new language."))
        }
    }

    private var idleView: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.37, green: 0.63, blue: 1.0),
                                                  Color(red: 0.04, green: 0.42, blue: 1.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 62, height: 62)
                    .overlay(Text("✨").font(.system(size: 30)))
                    .shadow(color: .blue.opacity(0.35), radius: 8, y: 4)

                Text("MacScrub")
                    .font(.system(size: 20, weight: .bold))
                Text(String(localized: "window.subtitle",
                            defaultValue: "Clean your keyboard and trackpad safely"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)

            // Primary action
            Button(action: startCleaning) {
                Text(String(localized: "menu.start_cleaning", defaultValue: "Start Cleaning Mode"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 26)
            .padding(.top, 22)

            Text(holdHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            // Settings card
            settingsCard
                .padding(.horizontal, 26)
                .padding(.top, 22)

            Button(String(localized: "settings.about", defaultValue: "About")) {
                showAbout()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .padding(.vertical, 16)
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Timeout
            HStack {
                Label(String(localized: "settings.auto_exit_after", defaultValue: "Auto-exit after:"),
                      systemImage: "timer")
                Spacer()
                Text(String(localized: "\(settings.timeoutDuration) seconds"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Stepper(value: $settings.timeoutDuration, in: 30...300, step: 15) {
                    EmptyView()
                }
                .labelsHidden()
            }
            .padding(12)
            Divider().padding(.leading, 12)

            // Lid
            Toggle(isOn: $settings.exitOnLidOpen) {
                Label(String(localized: "settings.exit_on_lid_open",
                             defaultValue: "Exit cleaning mode when lid is opened"),
                      systemImage: "laptopcomputer")
            }
            .padding(12)
            Divider().padding(.leading, 12)

            // Language
            HStack {
                Label(String(localized: "settings.language", defaultValue: "Language"),
                      systemImage: "globe")
                Spacer()
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(12)
            Divider().padding(.leading, 12)

            // Exit keys (expandable)
            DisclosureGroup(isExpanded: $showExitKeys) {
                exitKeysToggles.padding(.top, 6)
            } label: {
                Label(String(localized: "settings.exit_keys", defaultValue: "Exit Keys"),
                      systemImage: "keyboard")
            }
            .padding(12)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 1))
        .onChange(of: settings.appLanguage) { oldValue, newValue in
            guard oldValue != newValue else { return }
            showRestartAlert = true
        }
    }

    private var exitKeysToggles: some View {
        HStack(spacing: 12) {
            modifierToggle("⌘", .command)
            modifierToggle("⌥", .option)
            modifierToggle("⌃", .control)
            modifierToggle("⇧", .shift)
        }
    }

    private func modifierToggle(_ symbol: String, _ key: ModifierKeyFlags) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { settings.exitKeyModifiers.contains(key) },
            set: { isOn in
                let allowed = settings.exitKeyModifiers.count > 1 || isOn
                guard allowed else { return }
                settings.exitKeyModifiers = isOn
                    ? settings.exitKeyModifiers.union(key)
                    : settings.exitKeyModifiers.subtracting(key)
            }
        ))
        .toggleStyle(.checkbox)
    }

    private var holdHint: String {
        String(localized: "overlay.hold_to_exit", defaultValue: "Hold exit keys to exit")
    }

    private func startCleaning() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            manager.activate()
        } else {
            PermissionGuideView.showIfNeeded()
        }
    }

    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
