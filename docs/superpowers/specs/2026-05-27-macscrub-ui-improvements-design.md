# MacScrub UI & Architecture Improvements — Design

**Date:** 2026-05-27
**Status:** Approved

## Background

MacScrub is a macOS menu-bar utility that temporarily blocks keyboard and trackpad
input during cleaning. Today it has no main window (only `MenuBarExtra` + a `Settings`
scene), the menu uses a plain `VStack` of buttons, settings appear not to persist
across launches, and the app language is fixed to the system/default locale.

This design addresses five user requests:

1. A menu-bar menu that follows macOS conventions.
2. A main window shown when the app launches.
3. Fixing settings that revert to defaults after relaunch.
4. A language picker in settings.
5. A focused, best-practices code cleanup.

## Goals

- Single all-in-one **main window** shown on launch (no separate Settings window).
- **Native macOS menu** for the menu-bar item.
- **Reliable settings persistence** with correct SwiftUI observation.
- **Language selection** (System / English / Türkçe / 中文) with a restart prompt.
- Targeted cleanup of risky/duplicated code touched by the above.

## Non-Goals

- No live (no-restart) language switching.
- No Dock presence — the app stays a menu-bar accessory (`LSUIElement = true`).
- No unrelated refactors beyond code touched by these changes.
- No change to the core event-blocking / full-screen overlay behavior.

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Dock presence | Menu-bar only (`LSUIElement = true`); window still shown on launch |
| Window close | App keeps running in the menu bar; reopened from the menu / ⌘, |
| Settings surface | All-in-one main window; the separate `Settings` scene is removed |
| Language switching | System + manual selection, applied after restart (macOS-standard) |
| Menu style | Native `.menuBarExtraStyle(.menu)` |
| Main window concept | "All-in-one" (option C): start button + inline settings |

## Architecture

### Scenes (`MacScrubApp`)

- **Main window** — a `Window` scene (single instance, identified). Fixed content
  size via `.windowResizability(.contentSize)`. Shown on launch; the app is
  activated/brought to front even though `LSUIElement` hides the Dock icon.
- **MenuBarExtra** — `.menuBarExtraStyle(.menu)`, native menu (see below).
- The existing `Settings` scene is **removed**. `⌘,` and the menu "Settings" item
  open/focus the main window instead (via `openWindow` / `NSApp.activate`).

Window-close keeps the process alive (default for a menu-bar app without a
terminating handler); reopening goes through `openWindow(id:)`.

### Main window (`MainWindowView`)

Implements option C, polished to Apple HIG / current macOS aesthetics
(squircle app icon, soft shadow, SF Pro typography, grouped rows, prominent
primary action).

- **Idle state:** app icon, title, subtitle, prominent "Start Cleaning Mode"
  button, hint text, and a grouped settings card:
  - Auto-exit timeout (stepper or menu, range 30–300s, step 15)
  - Exit when lid opens (toggle)
  - Language (menu: System / English / Türkçe / 中文)
  - Secondary: "Exit keys" (reveals/sheets the four modifier toggles) and "About"
- **Active state:** in-window dark status panel showing remaining time and the
  exit-modifier indicator. The full-screen blocking overlay (`CleaningOverlayView`
  via `OverlayWindowController`) continues to work unchanged.

The window observes `CleaningModeManager.isActive` to switch between states and
gates "Start" behind the existing Accessibility-permission check
(`AXIsProcessTrustedWithOptions`, falling back to `PermissionGuideView`).

### Menu bar (`MenuBarView`)

Native menu via `.menuBarExtraStyle(.menu)`:

- Status header (disabled): "MacScrub · Ready" / "Cleaning…"
- Start Cleaning Mode / Stop Cleaning Mode (state-dependent)
- Open MacScrub (opens/focuses main window)
- Settings… (⌘,) → opens main window
- Quit MacScrub (⌘Q)

Buttons keep the existing permission gating before calling `manager.activate()`.

### SettingsStore (root cause of the persistence bug)

`SettingsStoreTests` pass in isolation, so raw `UserDefaults` writes work — the
runtime symptom comes from the observation/wiring layer: `@Observable` does **not**
track computed properties backed by `UserDefaults`, so SwiftUI neither re-renders
nor reliably reflects edits.

Refactor to **stored properties with `didSet` persistence**:

- Each setting is a real stored property, initialized from `UserDefaults` in `init`,
  with `didSet` writing back. This restores correct `@Observable` observation and
  guarantees a single source of truth that persists across launches.
- Add `appLanguage` (an enum: `.system`, `.en`, `.tr`, `.zh`).
- One shared `SettingsStore` instance is injected into all scenes
  (menu, main window) — no second instance.
- The existing `defaults: UserDefaults = .standard` injection point is preserved
  for tests.

### Localization & language switching (`LocalizationManager`)

- A small `@MainActor` type (or methods on the store) that reads/writes the selected
  language and applies it by setting `UserDefaults.standard.set([code], forKey:
  "AppleLanguages")` (and removing the key for "System").
- Changing the language shows a **restart-required** alert/notice; the UI fully
  switches after relaunch (documented macOS behavior).
- Add the new UI strings (window title/subtitle, language labels, restart notice,
  menu "Open MacScrub") to `Localizable.xcstrings` for `en`, `tr`, `zh-Hans`.

## Focused code cleanup

Limited to code in the blast radius of this work:

- `OverlayWindowController`: replace the `NSScreen.main!` force-unwrap with a safe
  guard (avoid a crash when no main screen is available).
- `CleaningModeManager`: de-duplicate the modifier-detector setup that is currently
  repeated in both `init` and `activate` (extract a single private builder).
- Wire the menu and main window to the same `manager` / `settings` instances cleanly;
  remove the now-unused `Settings` scene plumbing.

No unrelated refactors.

## Testing

- **SettingsStore regression:** values set on one store instance are read back by a
  fresh store sharing the same `UserDefaults` suite (proves cross-launch persistence).
- **LocalizationManager:** selecting a language writes the expected `AppleLanguages`
  value; selecting "System" clears it.
- Existing tests (`ModifierKeyDetectorTests`, `CleaningModeManagerTests`,
  `SettingsStoreTests`) stay green.

## Risks / Notes

- `LSUIElement = true` while showing a window on launch requires explicitly
  activating the app (`NSApp.activate`) so the window comes to the foreground.
- Language change requiring restart is intentional and surfaced to the user; live
  switching is explicitly out of scope.
- `Localizable.xcstrings` currently has 29 keys across `en`, `tr`, `zh-Hans`; new keys
  must be added for all three to avoid falling back to the key string.
