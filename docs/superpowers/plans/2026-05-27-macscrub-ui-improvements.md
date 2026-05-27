# MacScrub UI & Architecture Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an all-in-one main window shown on launch, a native menu-bar menu, reliable settings persistence, and a language picker — while keeping the app a menu-bar accessory.

**Architecture:** SwiftUI `App` with three concerns: a `Window` scene (main hub, option C), a native `MenuBarExtra(.menu)`, and a shared `@Observable SettingsStore` refactored to stored-properties-with-`didSet` so SwiftUI observation and `UserDefaults` persistence both work. Language selection writes `AppleLanguages` and prompts a restart. The existing full-screen blocking overlay is unchanged.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), Swift Testing (`import Testing`), XcodeGen project, `xcodebuild` for build/test.

---

## File Structure

- `MacScrub/State/SettingsStore.swift` — **modify**: stored properties + `didSet` persistence; add `appLanguage`.
- `MacScrub/State/AppLanguage.swift` — **create**: language enum (system/en/tr/zh-Hans) + apply/display helpers.
- `MacScrub/State/CleaningModeManager.swift` — **modify**: de-duplicate detector setup.
- `MacScrub/App/MacScrubApp.swift` — **modify**: `Window` scene, remove `Settings` scene, `.menu` menu-bar style, ⌘, command, safe `NSScreen` guard in `OverlayWindowController`.
- `MacScrub/App/Info.plist` — **modify**: add `LSUIElement = true`.
- `MacScrub/Views/MenuBarView.swift` — **modify**: native menu items + open-window.
- `MacScrub/Views/MainWindowView.swift` — **create**: idle/active hub (option C).
- `MacScrub/Localization/Localizable.xcstrings` — **modify**: add UI strings (en/tr/zh-Hans).
- `MacScrubTests/SettingsStoreTests.swift` — **modify**: cross-instance persistence + language tests.

**Test command (use everywhere below):**
```bash
xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet
```

---

## Task 1: SettingsStore — stored properties + persistence + appLanguage

Root cause of the "settings revert" bug: `@Observable` does not track computed properties backed by `UserDefaults`, so edits neither re-render nor reliably persist through the wiring. Fix by using real stored properties loaded in `init`, persisted in `didSet`.

**Files:**
- Create: `MacScrub/State/AppLanguage.swift`
- Modify: `MacScrub/State/SettingsStore.swift`
- Test: `MacScrubTests/SettingsStoreTests.swift`

- [ ] **Step 1: Create the AppLanguage enum**

Create `MacScrub/State/AppLanguage.swift`:

```swift
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english = "en"
    case turkish = "tr"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// `nil` means "follow the system" (no `AppleLanguages` override).
    var localeCode: String? {
        self == .system ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "language.system", defaultValue: "System")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .chinese: return "中文"
        }
    }
}
```

- [ ] **Step 2: Write failing tests for persistence and language**

Append these tests inside the `SettingsStoreTests` struct in `MacScrubTests/SettingsStoreTests.swift` (before the closing brace):

```swift
    @Test("Settings persist across store instances")
    func testPersistenceAcrossInstances() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.timeoutDuration = 60
        store.exitOnLidOpen = true
        store.exitKeyModifiers = [.command, .shift]

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.timeoutDuration == 60)
        #expect(reloaded.exitOnLidOpen == true)
        #expect(reloaded.exitKeyModifiers == [.command, .shift])
    }

    @Test("Default language is system")
    func testDefaultLanguage() {
        let store = SettingsStore(defaults: makeCleanDefaults())
        #expect(store.appLanguage == .system)
    }

    @Test("Selecting a language persists across instances")
    func testLanguagePersists() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .chinese

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.appLanguage == .chinese)
    }

    @Test("Selecting a language writes AppleLanguages")
    func testLanguageWritesAppleLanguages() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .turkish
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["tr"])
    }

    @Test("Selecting System clears AppleLanguages override")
    func testSystemLanguageClearsOverride() {
        let defaults = makeCleanDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .turkish
        store.appLanguage = .system
        #expect(defaults.stringArray(forKey: "AppleLanguages") == nil)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: FAIL — compile error, `appLanguage` is not a member of `SettingsStore`.

- [ ] **Step 4: Rewrite SettingsStore with stored properties**

Replace the entire contents of `MacScrub/State/SettingsStore.swift` with:

```swift
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
```

Note: `didSet` does not fire during `init`, so loading values does not re-persist or apply the language — correct.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: PASS — all `SettingsStore` tests green, including the four pre-existing ones.

- [ ] **Step 6: Commit**

```bash
git add MacScrub/State/AppLanguage.swift MacScrub/State/SettingsStore.swift MacScrubTests/SettingsStoreTests.swift
git commit -m "fix: persist settings via stored properties; add appLanguage"
```

---

## Task 2: De-duplicate detector setup in CleaningModeManager

The modifier-detector creation + `onAllKeysHeld` wiring is duplicated in `init` and `activate`. Extract one builder. Behavior is unchanged; `CleaningModeManagerTests` must stay green.

**Files:**
- Modify: `MacScrub/State/CleaningModeManager.swift`
- Test: `MacScrubTests/CleaningModeManagerTests.swift` (existing, no change)

- [ ] **Step 1: Add a private builder and use it in init and activate**

In `MacScrub/State/CleaningModeManager.swift`, replace the `init` and the first part of `activate` so the detector setup goes through one method.

Replace the `init(...)` body's detector lines:

```swift
        self.modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )

        self.modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }
```

with:

```swift
        self.modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        self.modifierDetector = makeDetector()
```

Then in `activate()` replace:

```swift
        modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }
```

with:

```swift
        modifierDetector = makeDetector()
```

Add this private method to the class (e.g. just above `activate()`):

```swift
    private func makeDetector() -> ModifierKeyDetector {
        let detector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        detector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }
        return detector
    }
```

(The initial inline assignment in `init` is a required placeholder so the non-optional `modifierDetector` is set before calling `makeDetector()`; the second line replaces it with the configured detector.)

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: PASS — `CleaningModeManager` tests (activate / deactivate / fail-gracefully) green.

- [ ] **Step 3: Commit**

```bash
git add MacScrub/State/CleaningModeManager.swift
git commit -m "refactor: single detector builder in CleaningModeManager"
```

---

## Task 3: Add localization strings

Add all new UI strings for `en`, `tr`, `zh-Hans` before any view references them. Editing the `.xcstrings` JSON via a script avoids hand-merge errors.

**Files:**
- Modify: `MacScrub/Localization/Localizable.xcstrings`

- [ ] **Step 1: Run the insertion script**

Run this exact command from the repo root:

```bash
python3 - <<'PY'
import json
path = "MacScrub/Localization/Localizable.xcstrings"
d = json.load(open(path, encoding="utf-8"))
new = {
  "window.subtitle": ("Clean your keyboard and trackpad safely",
                      "Klavye ve trackpad'i güvenle temizle",
                      "安全地清洁键盘和触控板"),
  "settings.language": ("Language", "Dil", "语言"),
  "language.system": ("System", "Sistem", "系统"),
  "settings.about": ("About", "Hakkında", "关于"),
  "menu.open": ("Open MacScrub", "MacScrub'ı Aç", "打开 MacScrub"),
  "menu.status_ready": ("MacScrub · Ready", "MacScrub · Hazır", "MacScrub · 就绪"),
  "menu.status_cleaning": ("Cleaning…", "Temizleniyor…", "清洁中…"),
  "language.restart_title": ("Restart Required", "Yeniden Başlatma Gerekli", "需要重启"),
  "language.restart_message": ("Quit and reopen MacScrub to apply the new language.",
                               "Yeni dili uygulamak için MacScrub'ı kapatıp yeniden açın.",
                               "退出并重新打开 MacScrub 以应用新语言。"),
  "language.restart_quit": ("Quit Now", "Şimdi Çık", "立即退出"),
  "language.restart_later": ("Later", "Sonra", "稍后"),
}
for key, (en, tr, zh) in new.items():
    d["strings"][key] = {"localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "tr": {"stringUnit": {"state": "translated", "value": tr}},
        "zh-Hans": {"stringUnit": {"state": "translated", "value": zh}},
    }}
json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("added", len(new), "keys; total now", len(d["strings"]))
PY
```

Expected output: `added 11 keys; total now 40`.

- [ ] **Step 2: Verify the file is valid JSON and keys exist**

Run:
```bash
python3 -c "import json;d=json.load(open('MacScrub/Localization/Localizable.xcstrings'));print('settings.language' in d['strings'], 'menu.open' in d['strings'])"
```
Expected: `True True`

- [ ] **Step 3: Commit**

```bash
git add MacScrub/Localization/Localizable.xcstrings
git commit -m "feat: add localization strings for window, menu, language picker"
```

---

## Task 4: MainWindowView — the all-in-one hub (option C)

A single window with idle and active states. Idle: app icon, title, subtitle, prominent Start button, a grouped settings card (timeout / lid / language), an expandable exit-keys section, and an About link. Active: a dark in-window status panel with remaining-time hint and the modifier indicator (the full-screen overlay continues to handle real blocking). Views are verified by build + manual run (Task 8); no unit test.

**Files:**
- Create: `MacScrub/Views/MainWindowView.swift`

- [ ] **Step 1: Create MainWindowView**

Create `MacScrub/Views/MainWindowView.swift`:

```swift
import SwiftUI
import ApplicationServices

struct MainWindowView: View {
    @Bindable var manager: CleaningModeManager
    @Bindable var settings: SettingsStore

    @State private var showExitKeys = false
    @State private var showRestartAlert = false

    var body: some View {
        Group {
            if manager.isActive {
                ActiveStatusView(manager: manager)
            } else {
                idleView
            }
        }
        .frame(width: 360)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: manager.isActive)
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
        .onChange(of: settings.appLanguage) { _, _ in
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
        String(localized: "overlay.hold_to_exit", defaultValue: "Hold all modifiers to exit")
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

private struct ActiveStatusView: View {
    var manager: CleaningModeManager

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .padding(20)
                .background(Circle().strokeBorder(.tint.opacity(0.35), lineWidth: 3))

            Text(String(localized: "overlay.title", defaultValue: "Cleaning Mode Active"))
                .font(.system(size: 18, weight: .bold))
            Text(String(localized: "overlay.locked", defaultValue: "Keyboard and trackpad are locked."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                indicator("⌘", .command)
                indicator("⌥", .option)
                indicator("⌃", .control)
                indicator("⇧", .shift)
            }
            .padding(.top, 6)

            Text(String(localized: "overlay.hold_to_exit", defaultValue: "Hold all modifiers to exit"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button(String(localized: "menu.stop_cleaning", defaultValue: "Stop Cleaning Mode")) {
                manager.deactivate()
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
    }

    private func indicator(_ symbol: String, _ key: ModifierKeyFlags) -> some View {
        let pressed = manager.modifierDetector.pressedKeys.contains(key)
        return Text(symbol)
            .font(.system(size: 14))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(.tint.opacity(pressed ? 0.28 : 0.12)))
            .foregroundStyle(pressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
}
```

- [ ] **Step 2: Verify it compiles (build only)**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED. (The view is not yet shown by any scene — that comes in Task 6.)

- [ ] **Step 3: Commit**

```bash
git add MacScrub/Views/MainWindowView.swift
git commit -m "feat: main window hub view (idle + active states)"
```

---

## Task 5: Native menu-bar menu

Replace the window-style button stack with a native macOS menu. Items: section header with status, Start/Stop, Open MacScrub, Settings (⌘,), Quit (⌘Q). Opening the window uses the SwiftUI environment.

**Files:**
- Modify: `MacScrub/Views/MenuBarView.swift`

- [ ] **Step 1: Rewrite MenuBarView**

Replace the entire contents of `MacScrub/Views/MenuBarView.swift` with:

```swift
import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section(manager.isActive
                ? String(localized: "menu.status_cleaning", defaultValue: "Cleaning…")
                : String(localized: "menu.status_ready", defaultValue: "MacScrub · Ready")) {
            if manager.isActive {
                Button(String(localized: "menu.stop_cleaning", defaultValue: "Stop Cleaning Mode")) {
                    manager.deactivate()
                }
            } else {
                Button(String(localized: "menu.start_cleaning", defaultValue: "Start Cleaning Mode")) {
                    startCleaning()
                }
            }
        }

        Divider()

        Button(String(localized: "menu.open", defaultValue: "Open MacScrub")) {
            openMainWindow()
        }
        Button(String(localized: "menu.settings", defaultValue: "Settings...")) {
            openMainWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(String(localized: "menu.quit", defaultValue: "Quit MacScrub")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func startCleaning() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            manager.activate()
        } else {
            PermissionGuideView.showIfNeeded()
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED. (`openWindow(id: "main")` resolves once Task 6 adds the `Window` scene; build still succeeds because the id is a runtime string.)

- [ ] **Step 3: Commit**

```bash
git add MacScrub/Views/MenuBarView.swift
git commit -m "feat: native menu-bar menu with open-window and settings"
```

---

## Task 6: App scenes — Window + .menu style + remove Settings + safe overlay

Wire the `Window` scene (id `"main"`), switch the menu-bar to `.menu` style, remove the `Settings` scene, add the ⌘, command, activate the app on launch, and make `OverlayWindowController` safe against a missing main screen.

**Files:**
- Modify: `MacScrub/App/MacScrubApp.swift`

- [ ] **Step 1: Rewrite MacScrubApp.swift**

Replace the entire contents of `MacScrub/App/MacScrubApp.swift` with:

```swift
import SwiftUI

@MainActor
class OverlayWindowController {
    var overlayWindow: NSWindow?

    func show(manager: CleaningModeManager) {
        guard overlayWindow == nil else { return }
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .statusBar + 1
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSHostingView(rootView: CleaningOverlayView(manager: manager))
        view.frame = screen.frame
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    func hide() {
        overlayWindow?.close()
        overlayWindow = nil
    }
}

@main
struct MacScrubApp: App {
    @State private var settings: SettingsStore
    @State private var eventBlocker: EventBlocker
    @State private var lidMonitor: LidMonitor
    @State private var manager: CleaningModeManager
    private let overlayController = OverlayWindowController()

    init() {
        let settings = SettingsStore()
        let eventBlocker = EventBlocker()
        let lidMonitor = LidMonitor()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: eventBlocker,
            lidMonitor: lidMonitor
        )
        self._settings = State(initialValue: settings)
        self._eventBlocker = State(initialValue: eventBlocker)
        self._lidMonitor = State(initialValue: lidMonitor)
        self._manager = State(initialValue: manager)
    }

    var body: some Scene {
        Window("MacScrub", id: "main") {
            MainWindowView(manager: manager, settings: settings)
                .onAppear {
                    manager.overlayController = overlayController
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? .blue : .secondary)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

Key changes vs. the original: `Settings` scene removed; `Window(id: "main")` added; `NSScreen.main` force-unwrap replaced with `guard let`; `.menuBarExtraStyle(.menu)`; app activated on launch.

- [ ] **Step 2: Build and run the test suite**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED and all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add MacScrub/App/MacScrubApp.swift
git commit -m "feat: main window scene, native menu style, safe overlay screen guard"
```

---

## Task 7: Hide the Dock icon (LSUIElement)

The app should be a menu-bar accessory: no Dock icon, but the window still opens on launch (the app is activated explicitly in Task 6).

**Files:**
- Modify: `MacScrub/App/Info.plist`

- [ ] **Step 1: Add LSUIElement**

In `MacScrub/App/Info.plist`, add this key/value pair inside the top-level `<dict>` (e.g. right after the `CFBundleVersion` entry):

```xml
	<key>LSUIElement</key>
	<true/>
```

- [ ] **Step 2: Verify the plist is well-formed**

Run: `plutil -lint MacScrub/App/Info.plist`
Expected: `MacScrub/App/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add MacScrub/App/Info.plist
git commit -m "feat: hide Dock icon via LSUIElement (menu-bar accessory)"
```

---

## Task 8: Manual verification

Confirm the real app behaves per the spec. (No automated UI tests — this is hands-on verification.)

**Files:** none.

- [ ] **Step 1: Build a runnable app and launch it**

Run:
```bash
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build -quiet
open build/Build/Products/Debug/MacScrub.app
```
Expected: BUILD SUCCEEDED; app launches.

- [ ] **Step 2: Verify each behavior**

Check, and note any failures:
- No Dock icon appears; the ✨ menu-bar icon is present.
- The main window appears on launch and comes to the front.
- The menu-bar icon opens a **native menu** (not a panel) with: status header, Start Cleaning Mode, Open MacScrub, Settings… (⌘,), Quit (⌘Q).
- In the window: change timeout, toggle lid, expand Exit Keys and toggle a modifier. Quit the app (⌘Q) and relaunch → **the changes are still there** (persistence fixed).
- Change Language to Türkçe → restart alert appears. Choose Quit Now, relaunch → UI is in Turkish. Set back to System → relaunch → UI follows system again.
- Click Start Cleaning Mode (grant Accessibility if prompted) → full-screen overlay appears and input is blocked; the window switches to its active panel. Hold ⌘⌥⌃⇧ for 3s → exits.
- Close the window (red button) → app keeps running in the menu bar; "Open MacScrub" reopens it.

- [ ] **Step 3: Commit (only if verification revealed fixes)**

If Step 2 surfaced issues you fixed, commit them; otherwise nothing to commit here.

---

## Self-Review Notes

- **Spec coverage:** menu redesign → Task 5; main window on launch → Tasks 4 & 6; settings persistence fix → Task 1; language picker → Tasks 1, 3, 4; best-practice cleanup (`NSScreen.main!`, detector dedupe) → Tasks 6 & 2; Dock/accessory behavior → Task 7; tests → Task 1 (+existing suites kept green).
- **Type consistency:** `AppLanguage` (Task 1) is used identically in `SettingsStore`, `MainWindowView` (Task 4); window id `"main"` matches between `openWindow(id: "main")` (Tasks 4/5) and `Window(... id: "main")` (Task 6); string keys added in Task 3 match those referenced in Tasks 4/5.
- **No placeholders:** every code step contains full code; the localization edit is a concrete script with expected output.
