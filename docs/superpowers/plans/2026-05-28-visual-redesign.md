# Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin and re-flow MacScrub's four screens (idle window, preferences, menu, active overlay) to match `MacScrub Presentation.html`: teal accent, a separate in-window Preferences view, a ring hold-progress indicator with centered remaining-seconds, and labelled keycaps.

**Architecture:** A new `MSColor` palette + a pure `holdRemainingText` helper (Theme.swift), a shared `@Observable HubNavigation` for in-window main⇄preferences switching, and rewrites of the four view files. The model layer (SettingsStore, CleaningModeManager, detectors) is unchanged — this is presentation only.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+) `@Observable` + `TimelineView`, Swift Testing, XcodeGen (sources are directory-globbed, so new files are picked up by `xcodegen generate`).

---

## File Structure

- `MacScrub/Views/Theme.swift` — **create**: `enum MSColor` (teal palette + label/secondary/tertiary) and a free `holdRemainingText(holdStartDate:now:duration:)` helper.
- `MacScrub/State/HubNavigation.swift` — **create**: `enum HubView` + `@Observable HubNavigation`.
- `MacScrub/Views/ModifierKeySquare.swift` — **modify**: light labelled keycap (glyph + label, teal pressed state).
- `MacScrub/Views/CleaningOverlayView.swift` — **modify**: glass card with ring hold-progress + centered remaining-seconds, labelled keycaps, status pill; remove `M:SS` countdown and linear bar.
- `MacScrub/Views/MainWindowView.swift` — **modify**: simplified idle view + separate preferences view switched by `HubNavigation`.
- `MacScrub/Views/MenuBarView.swift` — **modify**: ⌃⌘C on Start, "Preferences…" via nav, inline "Exit on Lid Open" toggle, takes `settings` + `nav`.
- `MacScrub/App/MacScrubApp.swift` — **modify**: create the shared `HubNavigation`, inject into both views.
- `MacScrub/Localization/Localizable.xcstrings` — **modify**: new keys + two reworded values.

**Test command** (Swift Testing — the `Test run with N tests in M suites passed` line is the real result; ignore the legacy `Executed 0 tests` line):
```bash
xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet
```

**New-file note:** `project.yml` globs `sources: - MacScrub` and `- MacScrubTests`, so a new file is registered by running `xcodegen generate` (no manual pbxproj editing). Commit the regenerated `MacScrub.xcodeproj/project.pbxproj` together with new files.

**Build-artifact note:** building may make Xcode's String Catalog tool reformat `MacScrub/Localization/Localizable.xcstrings`. Unless a task edits that file, revert it before staging:
```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
```

---

## Task 1: Theme.swift — MSColor palette + holdRemainingText helper

**Files:**
- Create: `MacScrub/Views/Theme.swift`
- Test: `MacScrubTests/ThemeTests.swift`

- [ ] **Step 1: Create the failing test file `MacScrubTests/ThemeTests.swift`**

```swift
import Testing
import Foundation
@testable import MacScrub

@Suite("holdRemainingText")
struct HoldRemainingTextTests {

    @Test("Returns empty string when not holding")
    func testNilHoldStart() {
        #expect(holdRemainingText(holdStartDate: nil, now: Date(), duration: 3) == "")
    }

    @Test("Returns full duration at the moment hold starts")
    func testFullAtStart() {
        let now = Date()
        #expect(holdRemainingText(holdStartDate: now, now: now, duration: 3) == "3.0")
    }

    @Test("Returns remaining seconds partway through the hold")
    func testPartway() {
        let start = Date()
        let now = start.addingTimeInterval(1.4)
        #expect(holdRemainingText(holdStartDate: start, now: now, duration: 3) == "1.6")
    }

    @Test("Clamps to 0.0 past the hold duration")
    func testClampsAtZero() {
        let start = Date()
        let now = start.addingTimeInterval(5)
        #expect(holdRemainingText(holdStartDate: start, now: now, duration: 3) == "0.0")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command.
Expected: FAIL — compile error, `cannot find 'holdRemainingText' in scope`.

- [ ] **Step 3: Create `MacScrub/Views/Theme.swift`**

```swift
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
```

- [ ] **Step 4: Register the new files and run tests to verify they pass**

```bash
xcodegen generate
```
Then run the test command.
Expected: PASS — `Test run with 35 tests in 7 suites passed` (31 existing + 4 new).

- [ ] **Step 5: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/Theme.swift MacScrubTests/ThemeTests.swift MacScrub.xcodeproj/project.pbxproj
git commit -m "feat: MSColor palette + holdRemainingText helper"
```

---

## Task 2: HubNavigation.swift — shared in-window navigation

**Files:**
- Create: `MacScrub/State/HubNavigation.swift`
- Test: `MacScrubTests/HubNavigationTests.swift`

- [ ] **Step 1: Create the failing test file `MacScrubTests/HubNavigationTests.swift`**

```swift
import Testing
@testable import MacScrub

@MainActor
@Suite("HubNavigation")
struct HubNavigationTests {

    @Test("Defaults to the main view")
    func testDefault() {
        #expect(HubNavigation().view == .main)
    }

    @Test("Switches to preferences and back to main")
    func testSwitch() {
        let nav = HubNavigation()
        nav.view = .preferences
        #expect(nav.view == .preferences)
        nav.view = .main
        #expect(nav.view == .main)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command.
Expected: FAIL — compile error, `cannot find 'HubNavigation' in scope`.

- [ ] **Step 3: Create `MacScrub/State/HubNavigation.swift`**

```swift
import SwiftUI

enum HubView: Equatable {
    case main
    case preferences
}

/// Drives which view the main window shows (idle hub vs. preferences). One shared
/// instance is created by the app and injected into the window and the menu.
@MainActor
@Observable
final class HubNavigation {
    var view: HubView = .main
}
```

- [ ] **Step 4: Register the new files and run tests to verify they pass**

```bash
xcodegen generate
```
Then run the test command.
Expected: PASS — `Test run with 37 tests in 8 suites passed` (35 + 2 new).

- [ ] **Step 5: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/State/HubNavigation.swift MacScrubTests/HubNavigationTests.swift MacScrub.xcodeproj/project.pbxproj
git commit -m "feat: shared HubNavigation for in-window main/preferences switching"
```

---

## Task 3: Localization strings

Add new UI strings and reword two values, for `en`/`tr`/`zh-Hans`, before the views reference them.

**Files:**
- Modify: `MacScrub/Localization/Localizable.xcstrings`

- [ ] **Step 1: Run the update script from the repo root**

```bash
python3 - <<'PY'
import json
path = "MacScrub/Localization/Localizable.xcstrings"
d = json.load(open(path, encoding="utf-8"))

def put(key, en, tr, zh):
    d["strings"][key] = {"localizations": {
        "en":      {"stringUnit": {"state": "translated", "value": en}},
        "tr":      {"stringUnit": {"state": "translated", "value": tr}},
        "zh-Hans": {"stringUnit": {"state": "translated", "value": zh}},
    }}

# new keys
put("idle.subtitle", "Clean your Mac safely.", "Mac'inizi güvenle temizleyin.", "安全地清洁你的 Mac。")
put("idle.support",
    "Keyboard and trackpad input will be temporarily blocked.",
    "Klavye ve trackpad girişi geçici olarak engellenecek.",
    "键盘和触控板输入将被暂时阻止。")
put("preferences.title", "Preferences", "Tercihler", "偏好设置")
put("preferences.autoterm", "Auto-terminate", "Otomatik sonlandır", "自动结束")
put("preferences.autoterm_sub",
    "End cleaning mode on its own",
    "Temizlik modunu kendiliğinden bitir",
    "自动结束清洁模式")
put("preferences.exit_keys", "Keys required to exit", "Çıkış için gereken tuşlar", "退出所需的按键")
put("preferences.exit_keys_hint",
    "Hold the selected keys together for %lld seconds to unlock. At least one key is required.",
    "Kilidi açmak için seçili tuşları birlikte %lld saniye basılı tutun. En az bir tuş gereklidir.",
    "同时按住所选按键 %lld 秒以解锁。至少需要一个按键。")
put("overlay.input_disabled", "Input is disabled", "Giriş devre dışı", "输入已禁用")
put("overlay.instruction",
    "Hold all modifier keys for %lld seconds to exit.",
    "Çıkmak için tüm değiştirici tuşları %lld saniye basılı tutun.",
    "按住所有修饰键 %lld 秒以退出。")

# reworded values (keys kept)
put("menu.settings", "Preferences…", "Tercihler…", "偏好设置…")
put("settings.exit_on_lid_open", "Exit on Lid Open", "Kapak Açılınca Çık", "开盖时退出")

json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("total keys now", len(d["strings"]))
PY
```

Expected output: `total keys now 50` (40 existing + 10 new keys; the two reworded keys already existed).

- [ ] **Step 2: Confirm a couple of keys parse**

```bash
python3 -c "import json;d=json.load(open('MacScrub/Localization/Localizable.xcstrings'));print(d['strings']['preferences.title']['localizations']['tr']['stringUnit']['value'], '|', d['strings']['menu.settings']['localizations']['en']['stringUnit']['value'])"
```
Expected: `Tercihler | Preferences…`

- [ ] **Step 3: Build to confirm the catalog is valid**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit (the xcstrings IS the deliberate change here)**

```bash
git add MacScrub/Localization/Localizable.xcstrings
git commit -m "i18n: add redesign strings; reword menu.settings + lid label"
```

---

## Task 4: ModifierKeySquare keycap + CleaningOverlayView ring

Rewrite the keycap as a light labelled key, and rebuild the overlay with the ring hold-progress indicator (centered remaining-seconds while holding, breathing sparkle when idle), labelled keycaps, and an "Input is disabled" status pill. Build-only (no unit test; the pure helper it uses is already tested).

**Files:**
- Modify: `MacScrub/Views/ModifierKeySquare.swift`
- Modify: `MacScrub/Views/CleaningOverlayView.swift`

- [ ] **Step 1: Replace the entire contents of `MacScrub/Views/ModifierKeySquare.swift`**

```swift
import SwiftUI

struct ModifierKeySquare: View {
    let symbol: String
    let label: String
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isPressed ? MSColor.tealDeep : MSColor.label)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isPressed ? MSColor.tealDeep : MSColor.tertiary)
        }
        .frame(width: 110, height: 102)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isPressed ? MSColor.tealTint : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isPressed ? MSColor.teal : Color.black.opacity(0.07),
                              lineWidth: isPressed ? 1 : 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MSColor.tealGlow, lineWidth: 4)
                .opacity(isPressed ? 1 : 0)
        )
        .offset(y: isPressed ? 2 : 0)
        .shadow(color: Color.black.opacity(0.10), radius: 7, y: 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
    }
}
```

- [ ] **Step 2: Replace the entire contents of `MacScrub/Views/CleaningOverlayView.swift`**

```swift
import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var breathing = false
    @State private var pulsing = false
    @State private var showContent = false

    /// Configured exit keys, in fixed display order, as (symbol, label, flag).
    private var orderedExitKeys: [(symbol: String, label: String, flag: ModifierKeyFlags)] {
        let all: [(String, String, ModifierKeyFlags)] = [
            ("⌘", "Command", .command),
            ("⌥", "Option", .option),
            ("⌃", "Control", .control),
            ("⇧", "Shift", .shift),
        ]
        return all.filter { manager.settings.exitKeyModifiers.contains($0.2) }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            if manager.isActive {
                Color.black.opacity(0.28)
                glassCard
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1.0 : 0.98)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: manager.isActive)
        .onAppear {
            withAnimation { showContent = true }
            breathing = true
            pulsing = true
        }
        .onChange(of: manager.isActive) { _, newValue in
            if !newValue { showContent = false }
        }
    }

    private var glassCard: some View {
        VStack(spacing: 0) {
            ring.padding(.bottom, 20)

            Text(String(localized: "overlay.title", defaultValue: "Cleaning Mode Active"))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MSColor.label)

            Text(String(localized: "overlay.locked", defaultValue: "Keyboard and trackpad are locked."))
                .font(.system(size: 16))
                .foregroundStyle(MSColor.secondary)
                .padding(.top, 6)

            Text(instruction)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MSColor.tertiary)
                .padding(.top, 14)

            HStack(spacing: 16) {
                ForEach(orderedExitKeys, id: \.symbol) { entry in
                    ModifierKeySquare(
                        symbol: entry.symbol,
                        label: entry.label,
                        isPressed: manager.modifierDetector.pressedKeys.contains(entry.flag)
                    )
                }
            }
            .padding(.top, 26)

            statusPill.padding(.top, 24)
        }
        .padding(.horizontal, 52)
        .padding(.top, 44)
        .padding(.bottom, 40)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 45, y: 40)
    }

    private var ring: some View {
        Group {
            if manager.modifierDetector.holdStartDate != nil {
                TimelineView(.animation) { context in
                    ringContent(
                        progress: holdProgress(at: context.date),
                        remaining: holdRemainingText(
                            holdStartDate: manager.modifierDetector.holdStartDate,
                            now: context.date,
                            duration: manager.modifierDetector.holdDuration
                        )
                    )
                }
            } else {
                ringContent(progress: 0, remaining: nil)
            }
        }
        .frame(width: 132, height: 132)
    }

    private func ringContent(progress: Double, remaining: String?) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(MSColor.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let remaining {
                VStack(spacing: 1) {
                    Text(remaining)
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(MSColor.tealDeep)
                    Text("SEC")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(MSColor.tertiary)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 46))
                    .foregroundStyle(MSColor.tealStrong)
                    .scaleEffect(breathing ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: breathing)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(MSColor.teal)
                .frame(width: 8, height: 8)
                .opacity(pulsing ? 1 : 0.4)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsing)
            Text(String(localized: "overlay.input_disabled", defaultValue: "Input is disabled"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(MSColor.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.04)))
    }

    private var instruction: String {
        let secs = Int(manager.modifierDetector.holdDuration)
        return String(format: String(localized: "overlay.instruction",
                                      defaultValue: "Hold all modifier keys for %lld seconds to exit."), secs)
    }

    private func holdProgress(at date: Date) -> Double {
        guard let start = manager.modifierDetector.holdStartDate else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / manager.modifierDetector.holdDuration))
    }
}
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/ModifierKeySquare.swift MacScrub/Views/CleaningOverlayView.swift
git commit -m "feat: teal ring overlay + labelled keycaps to match mockup"
```

---

## Task 5: MainWindowView — idle + preferences via HubNavigation

Simplify the idle view (no inline settings card) and add a separate preferences view; switch between them with the shared `HubNavigation`. Wire the shared nav in `MacScrubApp` and pass it to `MainWindowView` (MenuBarView stays nav-less until Task 6, so the build stays green).

**Files:**
- Modify: `MacScrub/Views/MainWindowView.swift`
- Modify: `MacScrub/App/MacScrubApp.swift`

- [ ] **Step 1: Replace the entire contents of `MacScrub/Views/MainWindowView.swift`**

```swift
import SwiftUI
import ApplicationServices

struct MainWindowView: View {
    @Bindable var manager: CleaningModeManager
    @Bindable var settings: SettingsStore
    @Bindable var nav: HubNavigation

    @State private var showRestartAlert = false

    var body: some View {
        Group {
            switch nav.view {
            case .main: idleView
            case .preferences: preferencesView
            }
        }
        .frame(width: 392)
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(MSColor.teal)
            .padding(.horizontal, 34)
            .padding(.top, 22)

            Button(String(localized: "menu.settings", defaultValue: "Preferences…")) {
                nav.view = .preferences
            }
            .buttonStyle(.plain)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(MSColor.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 34)
            .padding(.top, 10)

            Text(String(localized: "idle.support",
                        defaultValue: "Keyboard and trackpad input will be temporarily blocked."))
                .font(.system(size: 12))
                .foregroundStyle(MSColor.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 16)
                .padding(.bottom, 30)
        }
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
        let secs = Int(3)
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
```

- [ ] **Step 2: Wire the shared `HubNavigation` into the app and pass it to `MainWindowView`**

In `MacScrub/App/MacScrubApp.swift`:

(a) Add a `@State` property below `@State private var manager: CleaningModeManager`:
```swift
    @State private var nav: HubNavigation
```

(b) In `init()`, after the `let manager = ...` block and before the `self._settings = ...` assignments, add:
```swift
        let nav = HubNavigation()
```
and add this assignment alongside the other `self._...` assignments:
```swift
        self._nav = State(initialValue: nav)
```

(c) Change the `MainWindowView(...)` call in the `Window` scene from:
```swift
            MainWindowView(manager: manager, settings: settings)
```
to:
```swift
            MainWindowView(manager: manager, settings: settings, nav: nav)
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/MainWindowView.swift MacScrub/App/MacScrubApp.swift
git commit -m "feat: idle + preferences views switched by HubNavigation"
```

---

## Task 6: MenuBarView — nav, ⌃⌘C, Preferences, inline lid toggle

**Files:**
- Modify: `MacScrub/Views/MenuBarView.swift`
- Modify: `MacScrub/App/MacScrubApp.swift`

- [ ] **Step 1: Replace the entire contents of `MacScrub/Views/MenuBarView.swift`**

```swift
import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager
    @Bindable var settings: SettingsStore
    @Bindable var nav: HubNavigation
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
                .keyboardShortcut("c", modifiers: [.control, .command])
            }
        }

        Divider()

        Button(String(localized: "menu.open", defaultValue: "Open MacScrub")) {
            nav.view = .main
            openMainWindow()
        }
        Button(String(localized: "menu.settings", defaultValue: "Preferences…")) {
            nav.view = .preferences
            openMainWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Toggle(String(localized: "settings.exit_on_lid_open", defaultValue: "Exit on Lid Open"),
               isOn: $settings.exitOnLidOpen)

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

- [ ] **Step 2: Pass `settings` and `nav` to `MenuBarView` in the app**

In `MacScrub/App/MacScrubApp.swift`, change the `MenuBarExtra` content call from:
```swift
            MenuBarView(manager: manager)
```
to:
```swift
            MenuBarView(manager: manager, settings: settings, nav: nav)
```

- [ ] **Step 3: Build and run the full suite**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` and `Test run with 37 tests in 8 suites passed`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/MenuBarView.swift MacScrub/App/MacScrubApp.swift
git commit -m "feat: menu uses nav for preferences + inline lid toggle + ⌃⌘C"
```

---

## Task 7: Manual verification

Confirm the redesigned screens match the mockup and behave correctly.

**Files:** none.

- [ ] **Step 1: Build a runnable app and launch it**

```bash
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build -quiet
open build/Build/Products/Debug/MacScrub.app
```
Expected: `** BUILD SUCCEEDED **`; app launches (menu-bar accessory, window on launch).

- [ ] **Step 2: Verify each screen against the mockup**

- **Idle window**: teal sparkles app icon, "MacScrub", "Clean your Mac safely.", a teal "Start Cleaning Mode" button, a "Preferences…" button, and the support line. No inline settings card.
- **Preferences**: clicking "Preferences…" switches the same window to a back-button + "Preferences" view with an Auto-terminate slider (value label updates), an "Exit on Lid Open" toggle, a Language popup, and a four-chip "Keys required to exit" group (teal when on; can't deselect the last one). Back button returns to idle.
- **Menu**: the ✨ menu-bar icon opens a native menu with status header, Start Cleaning Mode (⌃⌘C), Open MacScrub, Preferences… (⌘,), an "Exit on Lid Open" checkmark toggle, and Quit (⌘Q). "Preferences…" opens the window directly on the preferences view.
- **Active overlay**: Start cleaning (grant Accessibility if asked). The overlay shows a glass card with the teal ring (breathing sparkle center when idle); pressing the configured keys lights the labelled keycaps; holding all of them fills the ring and the center shows counting-down seconds (e.g. "1.6"); after the hold it exits. The "Input is disabled" pill shows a pulsing teal dot. No `M:SS` countdown is shown.
- Deselect some exit keys in Preferences and confirm the overlay shows only those keycaps.

- [ ] **Step 3: Commit (only if verification revealed fixes)**

If Step 2 surfaced issues you fixed, commit them; otherwise nothing to commit here.

---

## Self-Review Notes

- **Spec coverage:** teal palette → Task 1 (`MSColor`); idle window simplified → Task 5; separate preferences view → Task 5; native menu + inline lid toggle + Preferences rename + ⌃⌘C → Task 6; ring overlay + labelled keycaps + status pill, no `M:SS` → Tasks 1 (helper) + 4; shared navigation → Task 2 + Tasks 5/6 wiring; localization → Task 3; tests → Tasks 1 & 2.
- **Type consistency:** `holdRemainingText(holdStartDate:now:duration:)` (Task 1) is called identically in Task 4's overlay. `MSColor.*` (Task 1) is used in Tasks 4, 5. `HubNavigation` / `HubView` (.main/.preferences) (Task 2) is used in Tasks 5 & 6 and constructed once in `MacScrubApp` (Task 5), passed to `MainWindowView(manager:settings:nav:)` (Task 5) and `MenuBarView(manager:settings:nav:)` (Task 6). `ModifierKeySquare(symbol:label:isPressed:)` (Task 4) is constructed with all three args in the same task's overlay. The localized keys added in Task 3 (`idle.subtitle`, `idle.support`, `preferences.*`, `overlay.input_disabled`, `overlay.instruction`, reworded `menu.settings`/`settings.exit_on_lid_open`) match every `String(localized:)` reference in Tasks 4–6.
- **No placeholders:** every code step has full code; the i18n step is an explicit script with expected output; new files are registered via `xcodegen generate`.
- **Build-green ordering:** the `nav` parameter is added to a view and its single call site (in `MacScrubApp`) within the same task, so each task compiles independently.
