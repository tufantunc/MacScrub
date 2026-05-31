import SwiftUI
import AppKit
import ApplicationServices

struct MainWindowView: View {
    @Bindable var manager: CleaningModeManager
    @Bindable var settings: SettingsStore
    @Bindable var nav: HubNavigation
    @Bindable var updateChecker: UpdateChecker

    @State private var showRestartAlert = false

    var body: some View {
        Group {
            switch nav.view {
            case .main: idleView
            case .preferences: preferencesView
            }
        }
        .frame(width: 392)
        // Genuinely translucent, light frosted panel (matches the mockup). A plain
        // SwiftUI material would only blur the opaque window background and read as
        // flat gray; this backs the window with a behind-window NSVisualEffectView
        // and makes the host window non-opaque so the desktop shows through.
        .background(WindowTranslucencyBackground())
        .environment(\.colorScheme, .light)
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

    // MARK: Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            appIcon.padding(.top, 30)

            Text("MacScrub")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MSColor.label)
                .padding(.top, 16)
            Text(String(localized: "idle.subtitle", defaultValue: "Clean your Mac safely."))
                .font(.system(size: 14.5))
                .foregroundStyle(MSColor.secondary)
                .padding(.top, 6)

            Button(action: startCleaning) {
                Text(String(localized: "menu.start_cleaning", defaultValue: "Start Cleaning Mode"))
            }
            .buttonStyle(PrimaryGradientButtonStyle())
            .padding(.horizontal, 34)
            .padding(.top, 22)

            Button {
                nav.view = .preferences
            } label: {
                Text(String(localized: "menu.settings", defaultValue: "Preferences…"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(MSColor.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 34)
            .padding(.top, 10)

            Text(String(localized: "idle.support",
                        defaultValue: "Keyboard and trackpad input will be temporarily blocked."))
                .font(.system(size: 12))
                .foregroundStyle(MSColor.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 16)

            if let update = updateChecker.availableUpdate {
                updateBanner(update)
                    .padding(.horizontal, 34)
                    .padding(.top, 16)
            }

            Spacer(minLength: 0)
                .frame(height: 30)
        }
    }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        Button {
            NSWorkspace.shared.open(update.pageURL)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text(String(format: String(localized: "update.available",
                                            defaultValue: "New version available (%@)"), update.version))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MSColor.tealDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(MSColor.tealTint, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color.white, Color(white: 0.93)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 66, height: 66)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(MSColor.tealStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: MSColor.tealGlow.opacity(0.5), radius: 8, y: 4)
    }

    // MARK: Preferences

    private var preferencesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    nav.view = .main
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MSColor.secondary)
                }
                .buttonStyle(.plain)
                Text(String(localized: "preferences.title", defaultValue: "Preferences"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MSColor.label)
            }
            .padding(.bottom, 16)

            prefsGroup
            exitKeysSection.padding(.top, 18)
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .onChange(of: settings.appLanguage) { oldValue, newValue in
            guard oldValue != newValue else { return }
            showRestartAlert = true
        }
    }

    private var prefsGroup: some View {
        VStack(spacing: 0) {
            // Auto-terminate (slider 30–300)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "preferences.autoterm", defaultValue: "Auto-terminate"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(MSColor.label)
                        Text(String(localized: "preferences.autoterm_sub", defaultValue: "End cleaning mode on its own"))
                            .font(.system(size: 11))
                            .foregroundStyle(MSColor.tertiary)
                    }
                    Spacer()
                    Text(String(localized: "\(settings.timeoutDuration) seconds"))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(MSColor.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.timeoutDuration) },
                    set: { settings.timeoutDuration = Int($0) }
                ), in: 30...300, step: 15)
                .tint(MSColor.teal)
            }
            .padding(13)
            Divider().padding(.leading, 13)

            // Lid
            Toggle(isOn: $settings.exitOnLidOpen) {
                Text(String(localized: "settings.exit_on_lid_open", defaultValue: "Exit on Lid Open"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(MSColor.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(MSColor.teal)
            .padding(13)
            Divider().padding(.leading, 13)

            // Language
            HStack {
                Text(String(localized: "settings.language", defaultValue: "Language"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(MSColor.label)
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
            .padding(13)
        }
        .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
    }

    private var exitKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "preferences.exit_keys", defaultValue: "Keys required to exit"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(MSColor.label)

            HStack(spacing: 8) {
                keyChip("⌘", "Command", .command)
                keyChip("⌥", "Option", .option)
                keyChip("⌃", "Control", .control)
                keyChip("⇧", "Shift", .shift)
            }

            Text(exitKeysHint)
                .font(.system(size: 11))
                .foregroundStyle(MSColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyChip(_ symbol: String, _ label: String, _ key: ModifierKeyFlags) -> some View {
        let on = settings.exitKeyModifiers.contains(key)
        return Button {
            let allowed = settings.exitKeyModifiers.count > 1 || !on
            guard allowed else { return }
            settings.exitKeyModifiers = on
                ? settings.exitKeyModifiers.subtracting(key)
                : settings.exitKeyModifiers.union(key)
        } label: {
            VStack(spacing: 5) {
                Text(symbol)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(on ? MSColor.tealDeep : MSColor.label)
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(on ? MSColor.tealDeep : MSColor.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background((on ? MSColor.tealTint : Color.white.opacity(0.7)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? MSColor.teal : Color.black.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var exitKeysHint: String {
        let secs = Int(manager.modifierDetector.holdDuration)
        return String(format: String(localized: "preferences.exit_keys_hint",
            defaultValue: "Hold the selected keys together for %lld seconds to unlock. At least one key is required."), secs)
    }

    private func startCleaning() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            manager.activate()
        } else {
            PermissionGuideView.showIfNeeded()
        }
    }
}

/// Primary action button matching the mockup's `.btn-primary`: a vertical
/// teal→tealStrong gradient with a glossy top edge and a soft teal glow.
private struct PrimaryGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [MSColor.teal, MSColor.tealStrong],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: MSColor.tealGlow, radius: 8, y: 4)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A light, behind-window frosted backdrop that also makes its host window
/// non-opaque so the desktop is visible through it (true translucency rather
/// than a flat gray material over an opaque window).
private struct WindowTranslucencyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover          // light, frosted
        view.blendingMode = .behindWindow // sample the desktop behind the window
        view.state = .active
        view.appearance = NSAppearance(named: .aqua) // stay light even in Dark mode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // The host window is opaque by default; clear it so behind-window
        // blending actually shows through.
        if let window = nsView.window {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
