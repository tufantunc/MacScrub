# Cleaning Overlay UX Improvements — Design

**Date:** 2026-05-28
**Status:** Approved

## Background

The full-screen cleaning overlay (`CleaningOverlayView`) is what the user sees while
keyboard and trackpad are blocked. Today it always shows all four modifier keys,
a "N of M keys held" string, and a progress bar that counts pressed keys. The
auto-exit timeout runs invisibly in the background, with no on-screen indication
of how long is left, and it does not react to user activity.

This design refines the overlay's feedback so the user sees exactly which keys
they need, gets clear visual confirmation when those keys are pressed, watches a
hold-to-exit bar fill over the 3-second window, and always knows how much time
is left before the cleaning mode auto-exits.

## Goals

- Show only the **configured** exit-key modifiers (1–4 squares), not always four.
- Stronger **active visual state** when an exit key is pressed.
- A bottom **hold-progress bar** that fills from 0 to 1 over the 3-second
  hold-to-exit window, and is empty when not all required keys are held.
- A visible **idle-reset countdown** under the title: any keyboard activity
  resets it; reaching zero triggers auto-exit.

## Non-Goals

- No change to the underlying input-blocking mechanism.
- No change to the cleaning-mode start flow (menu / main window / permission UX).
- Mouse activity does not reset the idle countdown — "any key" means any key,
  not the pointer.
- No new persisted settings.

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Hold-progress bar semantics | Pure 3-second hold timer (0 when not all required keys held; resets on release) |
| Countdown behavior | Idle-reset — restarts on every keyboard activity |
| Countdown appearance | Large monospaced `M:SS` under the title, `tabular-nums` |

## Architecture

The change spans three layers, each with one clear responsibility.

### `ModifierKeyDetector` — exposes hold progress

- Annotate with `@Observable` so SwiftUI can track changes (the indicators were
  previously read across an unobservable boundary; this also retroactively
  fixes the live-update concern flagged in the prior code review).
- Add `private(set) var holdStartDate: Date?`.
  - Set to `Date.now` when the required keys first become fully held
    (inside `updateFlags`, transitioning from "not all held" → "all held").
  - Cleared (`nil`) when any required key is released, when `reset()` runs, and
    immediately after `onAllKeysHeld` fires.
- Existing `pressedKeys`/`onAllKeysHeld`/timer behavior is preserved.

### `CleaningModeManager` — exposes idle deadline and reacts to activity

- Replace the fixed-duration `timeoutTask` with an idle-reset cycle:
  - `private(set) var idleExitDeadline: Date` (observed).
  - On `activate()`: set `idleExitDeadline = .now + settings.timeoutDuration`
    and schedule a `Task` that sleeps until that deadline, then deactivates.
  - Add `func noteActivity()`: pushes the deadline forward to
    `.now + settings.timeoutDuration`, cancels the in-flight task, and
    schedules a fresh one to the new deadline.
  - On `deactivate()`: cancel the task (unchanged shape).
- Wire activity in `activate()`:
  `eventBlocker.onKeyActivity = { [weak self] in self?.noteActivity() }`.

### `EventBlocker` — reports keyboard activity

- Add `var onKeyActivity: (() -> Void)?` to `EventBlockerProtocol` and
  `EventBlocker`.
- Fire `onKeyActivity` from the tap callback for `.keyDown`, `.keyUp`, and
  `.flagsChanged` events (modifier presses count as keyboard activity).
- Mouse / scroll events do not fire it — explicit non-goal.
- Dispatch onto the main actor (`Task { @MainActor in blocker.onKeyActivity?() }`)
  in the same pattern used for `onFlagsChanged`.
- `MockEventBlocker` (tests) gains the same property; existing tests untouched.

### `CleaningOverlayView` — new layout (top → bottom)

1. Existing 🧼 icon (kept as-is).
2. Title "Cleaning Mode Active".
3. **NEW** large monospaced countdown, e.g. `1:58`, driven by a
   `TimelineView(.periodic(from: .now, by: 1))` reading
   `manager.idleExitDeadline` and rendering
   `max(0, deadline − .now)` formatted as `M:SS` with `.monospacedDigit()`.
4. Subtitle "Keyboard and trackpad are locked."
5. Small hold-hint ("Hold exit keys to exit" — string updated since "all
   modifiers" is no longer literally accurate when a subset is configured).
6. **Configured** modifier squares (1–4), built from `settings.exitKeyModifiers`
   in the fixed display order [⌘, ⌥, ⌃, ⇧].
7. **NEW** thin hold-progress bar (replaces the old "N of M keys held" text and
   the count-based `ProgressView`):
   - Uses `TimelineView(.animation)` for smooth fill.
   - Progress: `min(1, max(0, (.now − holdStartDate) / 3))` when
     `holdStartDate != nil`, else `0`.

### `ModifierKeySquare` — stronger active state

Increase the contrast of the pressed style:

- Fill: `Color.white.opacity(0.32)` (was `0.20`).
- Border: `Color.white.opacity(0.7)` (was `0.40`).
- Text: pure white (unchanged).
- Add a soft glow `shadow(color: .white.opacity(0.35), radius: 6)` when pressed.

Unpressed style is unchanged (subtle, low-contrast).

## Data flow

```
EventBlocker tap callback ──► onKeyActivity ──► Manager.noteActivity()
                          └─► onFlagsChanged ─► Detector.updateFlags()
                                                  │
                                                  ├─► pressedKeys (observed)
                                                  └─► holdStartDate (observed)

Manager.idleExitDeadline (observed) ──► TimelineView (countdown)
Detector.holdStartDate     (observed) ──► TimelineView (hold bar)
```

The model side updates `Date` properties; the view side animates by reading
"now" via `TimelineView`. No model-side ticker.

## Testing

- `ModifierKeyDetectorTests`:
  - When all required keys are pressed, `holdStartDate` becomes non-nil and is
    within a small tolerance of `Date.now`.
  - Releasing a required key clears `holdStartDate` back to nil.
  - After `onAllKeysHeld` fires, `holdStartDate` is nil.
  - `reset()` clears `holdStartDate`.
- `CleaningModeManagerTests`:
  - After `activate()`, `idleExitDeadline` is approximately
    `Date.now + settings.timeoutDuration`.
  - `noteActivity()` pushes the deadline forward.
  - Activity wiring: simulating an `onKeyActivity` invocation from the (mock)
    event blocker calls `noteActivity()` (verified via the deadline advancing).
- All existing tests must stay green.

## Risks / Notes

- `@Observable` on `ModifierKeyDetector` is a real correctness improvement: the
  prior overlay relied on SwiftUI re-rendering through a non-observed boundary,
  which has been a latent fragility flagged in earlier reviews.
- Idle-reset countdown means a user actively cleaning who occasionally bumps a
  key will never auto-exit until they truly stop — which is the intent
  ("auto-exit if forgotten"), not a regression.
- The hold-progress bar uses `TimelineView(.animation)`, which redraws roughly
  every frame while active — acceptable for a brief 3-second window.
- The string "Hold all modifiers to exit" is reworded to "Hold exit keys to
  exit" to stay accurate when a subset is configured. This is done by updating
  the *value* of the existing `overlay.hold_to_exit` key (in en/tr/zh) rather
  than introducing a new key, so the wording also flows to the main window's
  hold hint, which reads the same key.
