# Cleaning Overlay UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the full-screen cleaning overlay show only the configured exit keys with a stronger active look, a 3-second hold-progress bar driven by an observable hold-start date, and a visible idle-reset countdown driven by an observable deadline that any keyboard activity resets.

**Architecture:** Push two timestamps into the model layer — `ModifierKeyDetector.holdStartDate` and `CleaningModeManager.idleExitDeadline` — and let SwiftUI `TimelineView` derive both the hold-progress bar and the countdown from those dates against "now." `EventBlocker` gains an `onKeyActivity` callback fired for keyboard events; the manager wires that to a `noteActivity()` that bumps the deadline. The auto-exit task sleeps until the current deadline, re-checking on wake — when the deadline moves forward (activity), the task just goes back to sleep, no cancel/restart churn.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+) `@Observable` + `TimelineView`, Swift Testing, XcodeGen.

---

## File Structure

- `MacScrub/Core/ModifierKeyDetector.swift` — **modify**: add `@Observable`, add `holdStartDate: Date?`, set/clear it across the existing state transitions.
- `MacScrub/Core/EventBlockerProtocol.swift` — **modify**: add `var onKeyActivity: (() -> Void)? { get set }`.
- `MacScrub/Core/EventBlocker.swift` — **modify**: add the stored property and fire it from the tap callback for `keyDown`/`keyUp`/`flagsChanged`.
- `MacScrub/State/CleaningModeManager.swift` — **modify**: replace `startTimeout()` with idle-reset (`idleExitDeadline`, `noteActivity`, loop that re-reads the deadline after sleep); wire `eventBlocker.onKeyActivity`.
- `MacScrub/Views/ModifierKeySquare.swift` — **modify**: stronger active style (higher fill/border alpha + soft glow).
- `MacScrub/Views/CleaningOverlayView.swift` — **modify**: show only configured exit-key squares, add a `TimelineView`-driven countdown under the title, replace the count-based progress bar with a hold-progress bar driven from `holdStartDate`.
- `MacScrub/Localization/Localizable.xcstrings` — **modify**: update the value of the existing `overlay.hold_to_exit` key to "Hold exit keys to exit" (en/tr/zh-Hans).
- `MacScrubTests/ModifierKeyDetectorTests.swift` — **modify**: 4 new tests for `holdStartDate`.
- `MacScrubTests/CleaningModeManagerTests.swift` — **modify**: extend `MockEventBlocker` with `onKeyActivity`; 3 new tests for `idleExitDeadline` / `noteActivity` / activity wiring.

**Test command (use everywhere below — the Swift Testing summary line is the real result; ignore the legacy `Executed 0 tests` line):**
```bash
xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet
```

**Build-artifact note:** running the build sometimes causes Xcode's String Catalog tool to reformat `MacScrub/Localization/Localizable.xcstrings` in the working tree. Unless the task explicitly modifies that file, revert it before staging:
```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
```

---

## Task 1: ModifierKeyDetector — observable hold-start date

**Files:**
- Modify: `MacScrub/Core/ModifierKeyDetector.swift`
- Test: `MacScrubTests/ModifierKeyDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these tests inside the existing `ModifierKeyDetectorTests` struct (just before its closing brace) in `MacScrubTests/ModifierKeyDetectorTests.swift`:

```swift
    @Test("Hold start date is nil before all required keys are held")
    func testHoldStartDateNilInitially() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags(.maskCommand)
        #expect(detector.holdStartDate == nil)
    }

    @Test("Hold start date is set when all required keys are held")
    func testHoldStartDateSetWhenAllHeld() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        let start = detector.holdStartDate
        #expect(start != nil)
        if let start { #expect(abs(start.timeIntervalSinceNow) < 0.5) }
    }

    @Test("Releasing a required key clears hold start date")
    func testHoldStartDateClearedOnRelease() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        #expect(detector.holdStartDate != nil)
        detector.updateFlags(.maskCommand)
        #expect(detector.holdStartDate == nil)
    }

    @Test("Reset clears hold start date")
    func testHoldStartDateClearedByReset() {
        let detector = ModifierKeyDetector(requiredKeys: [.command, .shift], holdDuration: 3.0)
        detector.updateFlags([.maskCommand, .maskShift])
        detector.reset()
        #expect(detector.holdStartDate == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: FAIL — compile error, `value of type 'ModifierKeyDetector' has no member 'holdStartDate'`.

- [ ] **Step 3: Replace the entire contents of `MacScrub/Core/ModifierKeyDetector.swift`**

```swift
import Foundation
import CoreGraphics

@MainActor
@Observable
final class ModifierKeyDetector {
    let requiredKeys: ModifierKeyFlags
    let holdDuration: TimeInterval
    var onAllKeysHeld: (() -> Void)?

    private(set) var pressedKeys: ModifierKeyFlags = []
    private(set) var holdStartDate: Date?
    private var holdTimer: Task<Void, Never>?

    init(requiredKeys: ModifierKeyFlags, holdDuration: TimeInterval = 3.0) {
        self.requiredKeys = requiredKeys
        self.holdDuration = holdDuration
    }

    func updateFlags(_ flags: CGEventFlags) {
        var newPressed: ModifierKeyFlags = []
        if flags.contains(.maskCommand) { newPressed.insert(.command) }
        if flags.contains(.maskAlternate) { newPressed.insert(.option) }
        if flags.contains(.maskControl) { newPressed.insert(.control) }
        if flags.contains(.maskShift) { newPressed.insert(.shift) }

        pressedKeys = newPressed

        let allHeld = requiredKeys.isSubset(of: newPressed)

        if allHeld {
            if holdStartDate == nil { holdStartDate = Date() }
            startHoldTimer()
        } else {
            cancelHoldTimer()
            holdStartDate = nil
        }
    }

    func reset() {
        pressedKeys = []
        cancelHoldTimer()
        holdStartDate = nil
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.holdDuration ?? 3.0))
            guard !Task.isCancelled else { return }
            self?.onAllKeysHeld?()
            self?.holdTimer = nil
            self?.holdStartDate = nil
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
}
```

Notes:
- Added `import Foundation` for `Date`.
- Added `@Observable` so SwiftUI tracks `pressedKeys` and `holdStartDate` (also retroactively fixes the live-update observation hole flagged in a prior review).
- `holdStartDate` is set on the rising edge (transition from "not all held" → "all held"), cleared on falling edge, cleared on `reset()`, and cleared right after `onAllKeysHeld` fires (inside the hold-timer task).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: PASS — Swift Testing summary `Test run with 27 tests in 6 suites passed` (23 existing + 4 new).

- [ ] **Step 5: Revert the xcstrings build artifact and commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Core/ModifierKeyDetector.swift MacScrubTests/ModifierKeyDetectorTests.swift
git commit -m "feat: observable holdStartDate on ModifierKeyDetector"
```

---

## Task 2: EventBlocker — onKeyActivity callback

The protocol gains a settable callback; the real blocker fires it from the tap callback for keyboard events; the mock conforms with a plain stored property. No direct unit test here — Task 3 exercises the wiring through the mock.

**Files:**
- Modify: `MacScrub/Core/EventBlockerProtocol.swift`
- Modify: `MacScrub/Core/EventBlocker.swift`
- Modify: `MacScrubTests/CleaningModeManagerTests.swift` (only the `MockEventBlocker` declaration at the bottom)

- [ ] **Step 1: Extend the protocol**

Replace the entire contents of `MacScrub/Core/EventBlockerProtocol.swift` with:

```swift
import CoreGraphics

@MainActor
protocol EventBlockerProtocol {
    var isBlocking: Bool { get }
    var onFlagsChanged: ((CGEventFlags) -> Void)? { get set }
    var onKeyActivity: (() -> Void)? { get set }
    func start() -> Bool
    func stop()
}
```

- [ ] **Step 2: Implement it on the real blocker**

In `MacScrub/Core/EventBlocker.swift`:

(a) Add this stored property just below `var onFlagsChanged: ((CGEventFlags) -> Void)?`:

```swift
    var onKeyActivity: (() -> Void)?
```

(b) Locate the `private func eventTapCallback(...)` and replace the body's `if type == .flagsChanged { ... }` block plus the following section so it reads:

```swift
    if type == .flagsChanged {
        let flags = event.flags
        Task { @MainActor in
            blocker.onFlagsChanged?(flags)
            blocker.onKeyActivity?()
        }
        return Unmanaged.passRetained(event)
    }

    if type == .keyDown || type == .keyUp {
        Task { @MainActor in
            blocker.onKeyActivity?()
        }
        return nil
    }

    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    let statusBarHeight: CGFloat = 25
    let adjustedY = screenHeight - mouseLocation.y
    if adjustedY <= statusBarHeight && (type == .leftMouseDown || type == .rightMouseDown || type == .leftMouseUp || type == .rightMouseUp) {
        return Unmanaged.passRetained(event)
    }

    return nil
```

(The only behavioural changes: `flagsChanged` now also fires `onKeyActivity`; new `.keyDown`/`.keyUp` branch fires `onKeyActivity` and still blocks the event by returning `nil`. The mouse / status-bar passthrough below is unchanged.)

- [ ] **Step 3: Conform the mock**

In `MacScrubTests/CleaningModeManagerTests.swift`, inside `final class MockEventBlocker: EventBlockerProtocol`, add this property below the existing `var onFlagsChanged: ((CGEventFlags) -> Void)?`:

```swift
    var onKeyActivity: (() -> Void)?
```

- [ ] **Step 4: Build and run the suite to confirm nothing else broke**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: PASS — `Test run with 27 tests in 6 suites passed`.

- [ ] **Step 5: Revert the xcstrings build artifact and commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Core/EventBlockerProtocol.swift MacScrub/Core/EventBlocker.swift MacScrubTests/CleaningModeManagerTests.swift
git commit -m "feat: EventBlocker.onKeyActivity callback for keyboard events"
```

---

## Task 3: CleaningModeManager — idle-reset countdown

**Files:**
- Modify: `MacScrub/State/CleaningModeManager.swift`
- Test: `MacScrubTests/CleaningModeManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these tests inside the existing `CleaningModeManagerTests` struct (just before its closing brace) in `MacScrubTests/CleaningModeManagerTests.swift`:

```swift
    @Test("Activate schedules idle exit deadline approximately at timeoutDuration ahead")
    func testActivateSchedulesIdleDeadline() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let remaining = manager.idleExitDeadline.timeIntervalSinceNow
        #expect(abs(remaining - 120) < 1.0)
    }

    @Test("noteActivity pushes idle deadline forward")
    func testNoteActivityPushesDeadline() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: MockEventBlocker(),
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let firstDeadline = manager.idleExitDeadline
        try? await Task.sleep(for: .milliseconds(50))
        manager.noteActivity()
        #expect(manager.idleExitDeadline > firstDeadline)
    }

    @Test("Key activity from event blocker pushes idle deadline forward")
    func testEventBlockerActivityPushesDeadline() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.timeoutDuration = 120
        let blocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: settings,
            eventBlocker: blocker,
            lidMonitor: MockLidMonitor()
        )
        manager.activate()
        let firstDeadline = manager.idleExitDeadline
        try? await Task.sleep(for: .milliseconds(50))
        blocker.onKeyActivity?()
        #expect(manager.idleExitDeadline > firstDeadline)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: FAIL — compile error, `value of type 'CleaningModeManager' has no member 'idleExitDeadline'` and `noteActivity`.

- [ ] **Step 3: Apply the manager changes**

In `MacScrub/State/CleaningModeManager.swift`:

(a) Add this stored property declaration immediately below `private(set) var isActive = false`:

```swift
    private(set) var idleExitDeadline: Date = .distantPast
```

(b) Replace the existing `private func startTimeout() { ... }` method body and the `activate()` line that calls it. First, change the `activate()` body's call from `startTimeout()` to `startIdleTimeout()` and add the activity wiring. Locate this block in `activate()`:

```swift
        eventBlocker.onFlagsChanged = { [weak self] flags in
            self?.modifierDetector.updateFlags(flags)
        }

        let success = eventBlocker.start()
        guard success else {
            eventBlocker.stop()
            return
        }

        isActive = true
        lidMonitor.start()
        overlayController?.show(manager: self)
        startTimeout()
```

and replace it with:

```swift
        eventBlocker.onFlagsChanged = { [weak self] flags in
            self?.modifierDetector.updateFlags(flags)
        }
        eventBlocker.onKeyActivity = { [weak self] in
            self?.noteActivity()
        }

        let success = eventBlocker.start()
        guard success else {
            eventBlocker.stop()
            return
        }

        isActive = true
        lidMonitor.start()
        overlayController?.show(manager: self)
        startIdleTimeout()
```

(c) Replace the entire `private func startTimeout() { ... }` method at the bottom of the class with:

```swift
    func noteActivity() {
        guard isActive else { return }
        idleExitDeadline = .now + TimeInterval(settings.timeoutDuration)
    }

    private func startIdleTimeout() {
        timeoutTask?.cancel()
        idleExitDeadline = .now + TimeInterval(settings.timeoutDuration)
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = self.idleExitDeadline.timeIntervalSinceNow
                if remaining <= 0 {
                    self.deactivate()
                    return
                }
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
    }
```

The auto-exit task sleeps until the current deadline, re-reads `idleExitDeadline` when it wakes, and goes back to sleep if the deadline has moved forward. `noteActivity()` simply bumps the deadline; no cancel/restart per keystroke.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: PASS — `Test run with 30 tests in 6 suites passed` (27 + 3 new).

- [ ] **Step 5: Revert the xcstrings build artifact and commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/State/CleaningModeManager.swift MacScrubTests/CleaningModeManagerTests.swift
git commit -m "feat: idle-reset auto-exit countdown on CleaningModeManager"
```

---

## Task 4: ModifierKeySquare — stronger active state

Visual change; no unit test. Build-only verification.

**Files:**
- Modify: `MacScrub/Views/ModifierKeySquare.swift`

- [ ] **Step 1: Replace the entire contents of the file**

```swift
import SwiftUI

struct ModifierKeySquare: View {
    let symbol: String
    let isPressed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isPressed ? Color.white.opacity(0.32) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isPressed ? Color.white.opacity(0.7) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .frame(width: 46, height: 46)
            .overlay {
                Text(symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(isPressed ? Color.white : Color.white.opacity(0.3))
            }
            .shadow(color: isPressed ? Color.white.opacity(0.35) : Color.clear, radius: 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}
```

Diff vs. previous: pressed fill `0.20` → `0.32`, pressed border `0.40` → `0.70`, added `.shadow(color: isPressed ? Color.white.opacity(0.35) : Color.clear, radius: 6)` for a soft glow.

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Revert the xcstrings build artifact and commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/ModifierKeySquare.swift
git commit -m "style: stronger active state for ModifierKeySquare (brighter fill, border, glow)"
```

---

## Task 5: Update the hold-hint localization string

The existing `overlay.hold_to_exit` key's value is updated in place (en/tr/zh-Hans). Updating in place — rather than introducing a new key — also flows the new wording to the main window, which reads the same key.

**Files:**
- Modify: `MacScrub/Localization/Localizable.xcstrings`

- [ ] **Step 1: Run the update script**

Run this from the repo root:

```bash
python3 - <<'PY'
import json
path = "MacScrub/Localization/Localizable.xcstrings"
d = json.load(open(path, encoding="utf-8"))
d["strings"]["overlay.hold_to_exit"] = {"localizations": {
    "en":       {"stringUnit": {"state": "translated", "value": "Hold exit keys to exit"}},
    "tr":       {"stringUnit": {"state": "translated", "value": "Çıkış tuşlarını basılı tut"}},
    "zh-Hans":  {"stringUnit": {"state": "translated", "value": "按住退出键以退出"}},
}}
json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("updated overlay.hold_to_exit")
PY
```

Expected output: `updated overlay.hold_to_exit`.

- [ ] **Step 2: Confirm the new value parses**

Run:
```bash
python3 -c "import json;d=json.load(open('MacScrub/Localization/Localizable.xcstrings'));print(d['strings']['overlay.hold_to_exit']['localizations']['tr']['stringUnit']['value'])"
```
Expected: `Çıkış tuşlarını basılı tut`.

- [ ] **Step 3: Build to confirm the catalog is valid**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit only the xcstrings (it IS the deliberate change this time)**

```bash
git add MacScrub/Localization/Localizable.xcstrings
git commit -m "i18n: reword overlay.hold_to_exit to 'Hold exit keys to exit'"
```

---

## Task 6: CleaningOverlayView — configured-only keys + countdown + hold-progress bar

**Files:**
- Modify: `MacScrub/Views/CleaningOverlayView.swift`

- [ ] **Step 1: Replace the entire contents of `MacScrub/Views/CleaningOverlayView.swift`**

```swift
import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var showContent = false
    @State private var breathing = false

    /// Modifier squares to display, ordered consistently and filtered to the
    /// user's configured exit keys.
    private var orderedExitKeys: [(symbol: String, flag: ModifierKeyFlags)] {
        let all: [(String, ModifierKeyFlags)] = [
            ("⌘", .command), ("⌥", .option), ("⌃", .control), ("⇧", .shift),
        ]
        return all.filter { manager.settings.exitKeyModifiers.contains($0.1) }
    }

    var body: some View {
        ZStack {
            if manager.isActive {
                VStack(spacing: 12) {
                    Text("🧼")
                        .font(.system(size: 42))
                        .scaleEffect(breathing ? 1.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: breathing
                        )

                    Text(String(localized: "overlay.title", defaultValue: "Cleaning Mode Active"))
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(.white)

                    // Idle-reset countdown — recomputed once per second.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formattedCountdown(deadline: manager.idleExitDeadline, now: context.date))
                            .font(.system(size: 34, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    Text(String(localized: "overlay.locked", defaultValue: "Keyboard and trackpad are locked."))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)

                    Text(String(localized: "overlay.hold_to_exit", defaultValue: "Hold exit keys to exit"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 14) {
                        ForEach(orderedExitKeys, id: \.symbol) { entry in
                            ModifierKeySquare(
                                symbol: entry.symbol,
                                isPressed: manager.modifierDetector.pressedKeys.contains(entry.flag)
                            )
                        }
                    }
                    .padding(.vertical, 4)

                    // Hold-progress bar — fills 0→1 over the 3 sec while all
                    // required keys are held; 0 otherwise.
                    TimelineView(.animation) { context in
                        ProgressView(value: holdProgress(at: context.date))
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                            .frame(width: 160)
                            .scaleEffect(y: 0.6)
                    }
                }
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1.0 : 0.98)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: manager.isActive)
                .onAppear {
                    withAnimation {
                        showContent = true
                        breathing = true
                    }
                }
                .onChange(of: manager.isActive) { _, newValue in
                    if !newValue {
                        showContent = false
                        breathing = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func holdProgress(at date: Date) -> Double {
        guard let start = manager.modifierDetector.holdStartDate else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / manager.modifierDetector.holdDuration))
    }

    private func formattedCountdown(deadline: Date, now: Date) -> String {
        let remaining = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
```

Diff vs. previous overlay: configured-only modifier squares via `orderedExitKeys` + `ForEach`; the old "N of M keys held" text is removed; the old count-based `ProgressView` is replaced with the new hold-progress bar driven by `holdProgress(at:)`; a new countdown `TimelineView` is added directly below the title; the hold hint now uses the reworded `overlay.hold_to_exit` value as-is.

- [ ] **Step 2: Build and run the suite to confirm nothing regressed**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` and `Test run with 30 tests in 6 suites passed`.

- [ ] **Step 3: Revert the xcstrings build artifact and commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/CleaningOverlayView.swift
git commit -m "feat: overlay shows configured keys, idle countdown, hold-progress bar"
```

---

## Task 7: Manual verification

Hands-on verification of the four user-facing requirements.

**Files:** none.

- [ ] **Step 1: Build a runnable app and launch it**

```bash
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build -quiet
open build/Build/Products/Debug/MacScrub.app
```
Expected: `** BUILD SUCCEEDED **`; app launches.

- [ ] **Step 2: Check each user-facing behavior**

In the main window's Exit Keys section, deselect a couple of modifiers so only e.g. ⌘ and ⇧ remain. Start cleaning mode and confirm:

- The overlay shows **only the configured modifier squares** (here ⌘ and ⇧), not all four.
- Pressing one of the configured modifiers makes that square noticeably brighter (stronger fill, brighter border, soft glow).
- Holding *all* configured modifiers together makes the bottom bar fill smoothly; releasing one resets it to empty; holding for ~3 s exits.
- Under the title, a large monospaced `M:SS` countdown is visible. It ticks down once per second; pressing any key (any keyboard key, not the mouse) snaps it back to the full configured timeout.
- Reopen the main window, restore all four exit modifiers, restart cleaning, and confirm four squares again.

- [ ] **Step 3: Commit only if verification revealed fixes**

If Step 2 surfaced issues you fixed, commit them; otherwise nothing to commit here.

---

## Self-Review Notes

- **Spec coverage:**
  - configured-only squares → Task 6 (`orderedExitKeys` + `ForEach`).
  - brighter active look → Task 4.
  - 3-second hold-progress bar driven from `holdStartDate` → Tasks 1 + 6.
  - idle-reset countdown driven from `idleExitDeadline` → Tasks 2 + 3 + 6.
  - reworded hold hint → Task 5.
  - `@Observable` on detector (incidental correctness improvement) → Task 1.
- **Type consistency:** `holdStartDate: Date?` (Task 1) is read identically in the overlay (Task 6) via `manager.modifierDetector.holdStartDate`. `idleExitDeadline: Date` and `noteActivity()` (Task 3) match the names used in Task 6's countdown and Task 2's activity callback wiring. `onKeyActivity: (() -> Void)?` matches between the protocol (Task 2), the real blocker (Task 2), the mock (Task 2), and the manager wiring (Task 3).
- **No placeholders:** every code step has full code; the i18n change is an explicit script with expected output.
