# MacScrub — Design Specification

**Date:** 2026-05-27
**Status:** Approved
**License:** MIT

## Overview

MacScrub is a macOS menu bar utility that temporarily blocks keyboard and trackpad input during keyboard cleaning. Open source, single-purpose, calm Apple-style experience.

**Platform:** macOS 14 Sonoma+
**Distribution:** GitHub Releases (DMG)
**Languages:** English (base), Turkish, Chinese (Simplified) — extensible via String Catalog

## Architecture

Single-target SwiftUI app. No dock icon (`LSUIElement = true`). Entry point: `MenuBarExtra`.

```
┌─────────────────────────────┐
│  UI Layer (SwiftUI)         │
│  - MenuBarExtra dropdown    │
│  - Cleaning overlay window  │
│  - Settings window          │
├─────────────────────────────┤
│  State Layer                │
│  - CleaningModeManager      │
│    (@Observable, singleton) │
│  - SettingsStore            │
│    (@AppStorage backed)     │
├─────────────────────────────┤
│  Core Layer                 │
│  - EventBlocker             │
│    (CGEventTap wrapper)     │
│  - ModifierKeyDetector      │
│    (exit gesture detection) │
│  - LidMonitor               │
│    (IOKit sleep/wake)       │
└─────────────────────────────┘
```

**Data flow:**
1. User clicks "Start Cleaning Mode" → `CleaningModeManager.activate()`
2. Manager → `EventBlocker.start()` (CGEventTap active)
3. Manager → overlay window shown
4. `ModifierKeyDetector` monitors modifier keys; when all 4 held for 3s → `CleaningModeManager.deactivate()`
5. Timeout timer (120s) → auto deactivate
6. Deactivate → `EventBlocker.stop()` + overlay dismissed + system sound

**Concurrency:** All state on `@MainActor`. CGEventTap callbacks dispatched to main queue.

## Event Blocking System

**EventBlocker** uses `CGEventTapCreate` at `kCGHIDEventTap` level with `kCGHeadInsertEventTap` placement.

**Blocked events:**

| Event | CGEvent Type | Action |
|---|---|---|
| Key down | `.keyDown` | Block |
| Key up | `.keyUp` | Block |
| Mouse click | `.leftMouseDown`, `.rightMouseDown` | Block |
| Mouse drag | `.leftMouseDragged`, `.rightMouseDragged` | Block |
| Scroll | `.scrollWheel` | Block |
| Gesture | `.gesture` | Block |
| Other mouse | `.otherMouseDown` | Block |

**Not blocked:**
- `.flagsChanged` — passed to `ModifierKeyDetector` for exit gesture recognition
- Menu bar mouse events — EventBlocker skips events in the menu bar screen region

**ModifierKeyDetector:**
- Monitors 4 modifier flags: `.command`, `.option`, `.control`, `.shift`
- All pressed simultaneously → 3s timer starts
- Any released → timer resets
- 3s elapsed → calls `CleaningModeManager.deactivate()`

**Accessibility Permission:**
- CGEventTap requires Accessibility permission (System Settings → Privacy & Security → Accessibility)
- On first launch, if permission missing → dialog guides user to System Settings
- `CGEventTapCreate` returns `nil` when permission absent
- Permission checked on every activate attempt

**Timeout:**
- 120s default timer starts on cleaning mode activation
- Timer does not reset on any event
- On expiry → deactivate + system sound

## Menu Bar Integration

**MenuBarExtra** with SF Symbol `sparkles`:
- Cleaning mode off → gray icon
- Cleaning mode active → blue icon + "Cleaning Mode Active" label

**Dropdown menu (normal mode):**
```
🧼 MacScrub
─────────────────
▶ Start Cleaning Mode
─────────────────
⚙ Settings...
Quit
```

**Dropdown menu (cleaning mode active):** Menu bar click events are not blocked, so dropdown remains accessible.

## Cleaning Mode Overlay

**Visual approach:** Dimmed blur overlay with `.ultraThinMaterial` background. Centered status card. Desktop barely visible behind.

**Layout:**
- Emoji icon (🧼)
- Title: "Cleaning Mode Active"
- Subtitle: "Keyboard and trackpad are locked."
- Instruction text: "Hold all modifiers to exit"
- 4 modifier key squares (⌘ ⌥ ⌃ ⇧)
- Pressed keys: brighter fill + border
- Unpressed keys: dim, low opacity
- Thin linear progress bar below keys showing hold duration
- Text indicator: "3 of 4 keys held"

**Animations:**
- Spring animation for overlay appear/disappear
- Scale 0.98 → 1.0 on key press
- Smooth progress bar fill
- Breathing animation on idle state

**Exit animation:** Blur fade out + light system sound ("Cleaning Mode Ended" notification)

**Color palette:** No red/green. Calm neutrals. White text on dark translucent background.

## Settings

Separate window opened from menu bar dropdown. Three settings:

1. **Exit Keys** — modifier key selection (checkboxes: ⌘ ⌥ ⌃ ⇧). Default: all four. Minimum 1 key must be selected.
2. **Timeout Duration** — slider, range 30s–300s. Default: 120s.
3. **Exit on Lid Open** — toggle. Default: off. When enabled, cleaning mode deactivates when laptop lid is opened (detected via IOKit sleep/wake notifications).

**Storage:** `@AppStorage` (UserDefaults). Settings take effect immediately.

## Localization

**Format:** String Catalog (`Localizable.xcstrings`) — Xcode native JSON format.

**Languages:** English (base), Turkish (`tr`), Chinese Simplified (`zh-Hans`).

**Detection:** `Bundle.main.preferredLocalizations` for automatic system language matching. Fallback: English.

**Extensibility:** `Localizable.xcstrings` is a JSON file in the repo. Community can add languages via PR. Adding a new language requires only: add language in Xcode → translate strings in catalog. No scripts or custom tooling needed.

## Distribution

**GitHub Releases** with automated CI:

**GitHub Actions workflow:**
- Triggered by version tag push (e.g., `v1.0.0`)
- macOS runner
- `xcodebuild archive` → `xcodebuild -exportArchive`
- `.dmg` created via `hdiutil`
- Published as GitHub Release asset

**DMG:**
- Drag-to-Applications style
- Simple background with app icon + Applications shortcut
- Ad-hoc code signature (no paid Apple Developer account required)
- No notarization — users must right-click → Open on first launch

**Project structure:**
```
MacScrub/
├── MacScrub.xcodeproj
├── MacScrub/
│   ├── MacScrubApp.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── CleaningOverlay.swift
│   │   └── SettingsView.swift
│   ├── Core/
│   │   ├── EventBlocker.swift
│   │   ├── ModifierKeyDetector.swift
│   │   └── LidMonitor.swift
│   ├── State/
│   │   ├── CleaningModeManager.swift
│   │   └── SettingsStore.swift
│   ├── Localization/
│   │   └── Localizable.xcstrings
│   └── Assets.xcassets
├── .github/
│   └── workflows/
│       └── release.yml
├── LICENSE
└── README.md
```

## Key Design Principles

- **Single purpose:** Block input during cleaning. Nothing else.
- **Calm and safe:** No alarms, no red/green, no "LOCKED!" energy. Translucent, breathing, temporary.
- **Always escapable:** Exit instructions always visible. Auto-timeout always active. Menu bar always accessible.
- **Apple HIG compliance:** Native typography, SF Symbols, `.ultraThinMaterial`, rounded corners (16–24px), generous padding, spring animations, minimal controls.
- **YAGNI:** Three settings only. No analytics, no crash reporting, no accounts, no premium tier.
