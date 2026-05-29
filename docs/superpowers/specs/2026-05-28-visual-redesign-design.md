# Visual Redesign to Match Presentation Mockup — Design

**Date:** 2026-05-28
**Status:** Approved

## Background

`MacScrub Presentation.html` (at the repo root) is a high-fidelity mockup of four
screens: the **Idle Window**, **Preferences**, the **menu-bar menu**, and the
**Cleaning Mode active overlay**. The current app implements all four but with a
blue accent, an all-in-one idle window (settings inline), a small modifier-square
row, and a linear hold-progress bar plus an `M:SS` auto-terminate countdown.

This design re-skins and re-flows the app's screens to match the mockup: a calm
teal accent, a simplified idle window with a separate Preferences view, a ring
hold-progress indicator with a centered remaining-seconds readout, larger labelled
keycaps, and a refreshed glass overlay.

## Goals

- Apply the mockup's **teal accent palette** across the app.
- **Idle window**: icon, title, subtitle, primary "Start Cleaning Mode", secondary
  "Preferences…", support text. No inline settings.
- **Preferences**: a separate in-window view (back button + title) with
  Auto-terminate (slider 30–300s), Disable on Lid Close (toggle), Language (popup),
  and a "Keys required to exit" chip group.
- **Menu**: native macOS menu (kept), with Start/Stop, Open MacScrub, Preferences…,
  an inline "Exit on Lid Open" toggle, and Quit.
- **Active overlay**: glass card with a ring hold-progress indicator (center shows
  the breathing sparkle when idle, or remaining seconds while holding), labelled
  keycaps, and an "Input is disabled" status pill. No `M:SS` countdown.

## Non-Goals

- No change to `SettingsStore`'s data model (timeout stays `Int` 30–300; exit keys,
  lid flag, language unchanged).
- No change to the idle-reset auto-terminate mechanism, the accessibility-permission
  flow, the full-screen blocking event tap, or code signing.
- No `M:SS` countdown in the overlay (the auto-terminate timer keeps running
  invisibly).
- The mockup's "Tweaks" panel and its React/Babel scaffolding are presentation-only
  and are NOT ported.

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Menu style | Keep native `.menuBarExtraStyle(.menu)`; lid setting shown as an inline `Toggle` (renders a checkmark item) |
| Auto-terminate control | Keep the existing slider (30–300s); no "Never" option |
| Overlay countdown | Ring hold-progress only, with centered remaining-seconds while holding; remove the `M:SS` auto-terminate readout |
| Auto-terminate behavior | Keep idle-reset (any keyboard activity resets); internal only |
| Preferences surface | Separate in-window view (not modal/sheet), navigated via shared state |

## Architecture

### Accent palette — `MacScrub/Views/Theme.swift` (new)

A `Color` extension exposing the mockup's five teal tones, approximated from its
oklch values to sRGB:

- `Color.teal` (primary), `.tealStrong`, `.tealDeep`, `.tealTint` (~16% alpha),
  `.tealGlow` (~45% alpha).

These names are app-scoped via a small namespace to avoid colliding with SwiftUI's
built-in `Color.teal`. Concretely: an `enum MSColor { static let teal = Color(...) ... }`
(referenced as `MSColor.teal`). All app views switch their accent from `.blue` /
ad-hoc colors to `MSColor` tones.

### Shared in-window navigation — `MacScrub/State/HubNavigation.swift` (new)

```swift
enum HubView { case main, preferences }

@MainActor
@Observable
final class HubNavigation {
    var view: HubView = .main
}
```

One instance is created in `MacScrubApp.init` (alongside settings/manager) and
injected into both `MainWindowView` and `MenuBarView`. The menu's "Preferences…"
sets `nav.view = .preferences` then opens/focuses the main window; "Open MacScrub"
sets `nav.view = .main`; the in-window back button sets `nav.view = .main`.

### `MainWindowView` — idle + preferences, switched by `nav.view`

When cleaning is active the window still shows the idle hub (the full-screen overlay
owns the active state, per the prior redesign). `MainWindowView` renders:

- `nav.view == .main` → **idle view**: 66×66 squircle icon (white gradient, teal
  sparkles), "MacScrub", "Clean your Mac safely.", full-width teal "Start Cleaning
  Mode" button (gated by the existing AX-permission check), "Preferences…" secondary
  button (`nav.view = .preferences`), support text.
- `nav.view == .preferences` → **preferences view**: back button (`nav.view = .main`)
  + "Preferences" title; a grouped card with Auto-terminate (slider 30–300 step 15,
  value label), Disable on Lid Close (toggle bound to `settings.exitOnLidOpen`),
  Language (menu `Picker` bound to `settings.appLanguage`, restart-alert preserved);
  below the card, "Keys required to exit" with four labelled chips bound to
  `settings.exitKeyModifiers` (min one), and the hold-to-exit hint.

Fixed width ~392. The existing language-change → restart alert is retained.

### `MenuBarView` — native menu (kept)

```
Section(status header)
  Start Cleaning Mode / Stop Cleaning Mode   (⌃⌘C on Start)
Divider
Open MacScrub                                 → nav.view = .main, openWindow
Preferences… (⌘,)                             → nav.view = .preferences, openWindow
Divider
Toggle("Exit on Lid Open", isOn: $settings.exitOnLidOpen)
Divider
Quit MacScrub (⌘Q)
```

`Toggle` inside a `.menu`-style `MenuBarExtra` renders as a checkmark item, giving
the inline on/off affordance without a custom popover.

### `CleaningOverlayView` — ring + labelled keycaps

- Glass card (`.ultraThinMaterial` is replaced by the mockup's light translucent
  gradient look approximated with material + overlay tint), centered over the blurred
  wallpaper + scrim (existing).
- **Ring** (132×132): a background track circle + a teal progress arc whose trim is
  `holdProgress` (0→1 over `holdDuration`), driven by `TimelineView(.animation)` from
  `manager.modifierDetector.holdStartDate`. Center:
  - holding (`holdStartDate != nil`): remaining-seconds text (one decimal, e.g.
    "1.1"), with a small "SEC" label, computed via a pure helper.
  - idle: the breathing teal sparkle (existing breathing animation).
- Title "Cleaning Mode Active"; subtitle "Keyboard and trackpad are locked.";
  instruction "Hold all modifier keys for N seconds to exit." (N = `holdDuration`).
- **Labelled keycaps** (configured keys only, 1–4): glyph + uppercase label
  (Command/Option/Control/Shift). Pressed state uses the teal tint/border/glow and a
  2px downward offset.
- Status pill: pulsing teal dot + "Input is disabled".
- The `M:SS` readout and the linear `ProgressView` are removed.

### `ModifierKeySquare` → labelled keycap

Same file/type name; its body becomes the mockup's larger keycap (glyph + label,
~110×102, teal pressed state). It is now constructed with both a symbol and a label
string. (`CleaningOverlayView` passes the label.)

### Pure helper for the ring readout

A free, testable function (placed in `Theme.swift` or a small `OverlayMath.swift`):

```swift
func holdRemainingText(holdStartDate: Date?, now: Date, duration: TimeInterval) -> String
```

Returns `""` when `holdStartDate == nil`; otherwise `max(0, duration - elapsed)`
formatted to one decimal (e.g. "1.1"). `holdProgress` likewise clamps 0...1.

## Data flow (unchanged spine)

```
EventBlocker tap ─► onFlagsChanged ─► Detector.updateFlags ─► pressedKeys / holdStartDate (@Observable)
               └─► onKeyActivity ──► Manager.noteActivity() ─► idleExitDeadline (@Observable, invisible)

Detector.holdStartDate ─► TimelineView(.animation) ─► ring trim + centered remaining seconds
SettingsStore.exitKeyModifiers ─► overlay keycaps + preferences chips
HubNavigation.view ─► MainWindowView (idle ⇄ preferences); set by menu + back button
```

## Testing

- **HubNavigation**: defaults to `.main`; setting `.preferences` and back to `.main`
  is observed.
- **holdRemainingText**: nil → ""; full duration remaining → "3.0"; partway →
  expected one-decimal string; clamps at "0.0" past the deadline.
- Existing suites (SettingsStore, CleaningModeManager, ModifierKeyDetector,
  OverlayWindowController, PermissionGuideView, Placeholder) stay green.
- View-only changes (idle/preferences/menu/overlay/keycap visuals) verified by build
  + manual check.

## Risks / Notes

- `MSColor` namespace avoids shadowing SwiftUI's `Color.teal`; using the system
  `.teal` directly would not match the mockup's specific oklch chroma.
- The ring uses `TimelineView(.animation)` (already used for the hold bar), redrawing
  ~per frame only during the brief hold window — acceptable.
- The mockup shows traffic-light title-bar buttons; the real `Window` scene provides
  the standard title bar automatically, so no custom title bar is built.
- Renaming the lid setting's localized value ("Exit on Lid Open") is cosmetic; the
  underlying `settings.exitOnLidOpen` key and behavior are unchanged.
- `menu.settings`'s value changes from "Settings..." to "Preferences…" to match the
  mockup; the key name stays `menu.settings`.
