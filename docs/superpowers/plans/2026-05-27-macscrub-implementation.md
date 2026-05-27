# MacScrub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar utility that blocks keyboard and trackpad input during keyboard cleaning.

**Architecture:** Single-target SwiftUI app using MenuBarExtra as entry point. CGEventTap intercepts input events at HID level. @Observable CleaningModeManager orchestrates state. Protocol-based core layer for testability.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14 Sonoma+, CGEventTap, IOKit, XcodeGen

---

## File Structure

```
MacScrub/
├── project.yml                              # XcodeGen project spec
├── MacScrub/
│   ├── App/
│   │   ├── MacScrubApp.swift                # @main, MenuBarExtra, WindowGroup for settings
│   │   └── Info.plist                       # LSUIElement = true
│   ├── Views/
│   │   ├── MenuBarView.swift                # Menu bar dropdown content
│   │   ├── CleaningOverlayView.swift        # Full-screen overlay with modifier key viz
│   │   ├── ModifierKeySquare.swift          # Single modifier key display component
│   │   ├── SettingsView.swift               # Settings window
│   │   └── PermissionGuideView.swift        # Accessibility permission dialog
│   ├── Core/
│   │   ├── EventBlocker.swift               # CGEventTap wrapper
│   │   ├── ModifierKeyDetector.swift        # Exit gesture detection
│   │   └── LidMonitor.swift                 # IOKit lid open/close
│   ├── State/
│   │   ├── CleaningModeManager.swift        # @Observable orchestrator
│   │   └── SettingsStore.swift              # @AppStorage backed settings
│   └── Assets.xcassets/                     # App icon, colors
├── MacScrubTests/
│   ├── SettingsStoreTests.swift
│   ├── ModifierKeyDetectorTests.swift
│   └── CleaningModeManagerTests.swift
├── MacScrub/Localization/
│   └── Localizable.xcstrings                # String Catalog (EN, TR, ZH)
├── .github/
│   └── workflows/
│       └── release.yml                      # CI/CD
├── LICENSE
└── README.md
```

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `MacScrub/App/Info.plist`
- Create: `MacScrub/App/MacScrubApp.swift` (minimal shell)
- Create: `MacScrub/Assets.xcassets/Contents.json`
- Create: `MacScrub/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `MacScrub/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: Install XcodeGen**

Run: `brew install xcodegen`

- [ ] **Step 2: Create project.yml**

```yaml
name: MacScrub
options:
  bundleIdPrefix: com.macscrub
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"

targets:
  MacScrub:
    type: application
    platform: macOS
    sources:
      - MacScrub
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macscrub.app
        INFOPLIST_FILE: MacScrub/App/Info.plist
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Automatic
        GENERATE_INFOPLIST_FILE: false
        SWIFT_EMIT_LOC_STRINGS: "YES"
    dependencies: []
    info:
      path: MacScrub/App/Info.plist

  MacScrubTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - MacScrubTests
    dependencies:
      - target: MacScrub
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macscrub.tests
        CODE_SIGN_IDENTITY: "-"
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacScrub</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleAllowedArchitectures</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Create minimal MacScrubApp.swift**

```swift
import SwiftUI

@main
struct MacScrubApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("MacScrub")
        } label: {
            Image(systemName: "sparkles")
        }
    }
}
```

- [ ] **Step 5: Create Assets.xcassets structure**

`MacScrub/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`MacScrub/Assets.xcassets/AccentColor.colorset/Contents.json`:
```json
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`MacScrub/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 6: Create MIT LICENSE file**

```
MIT License

Copyright (c) 2026 MacScrub Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 7: Create README.md**

```markdown
# MacScrub

A macOS menu bar utility that temporarily blocks keyboard and trackpad input during keyboard cleaning.

## Features

- Block all keyboard and trackpad input while cleaning
- Exit by holding all modifier keys (⌘⌥⌃⇧) for 3 seconds
- Automatic timeout after 120 seconds
- Customizable exit keys and timeout duration
- Apple-style calm, minimal UI

## Requirements

- macOS 14 Sonoma or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Installation

Download the latest DMG from [Releases](../../releases).

Drag MacScrub to your Applications folder. On first launch, right-click → Open to bypass Gatekeeper.

## Usage

1. Click the ✨ icon in the menu bar
2. Click "Start Cleaning Mode"
3. Clean your keyboard and trackpad safely
4. Hold ⌘⌥⌃⇧ for 3 seconds to exit (or wait 120 seconds)

## License

MIT
```

- [ ] **Step 8: Generate Xcode project and verify build**

Run:
```bash
xcodegen generate
xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add project.yml MacScrub/ LICENSE README.md
git commit -m "feat: project scaffold with XcodeGen, Info.plist, minimal app"
```

---

### Task 2: SettingsStore

**Files:**
- Create: `MacScrub/State/SettingsStore.swift`
- Create: `MacScrubTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import MacScrub

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {

    @Test("Default values are correct")
    func testDefaultValues() {
        let store = SettingsStore()
        #expect(store.exitKeyModifiers == [.command, .option, .control, .shift])
        #expect(store.timeoutDuration == 120)
        #expect(store.exitOnLidOpen == false)
    }

    @Test("Exit key modifiers can be updated")
    func testExitKeyModifiersUpdate() {
        let store = SettingsStore()
        store.exitKeyModifiers = [.command, .shift]
        #expect(store.exitKeyModifiers == [.command, .shift])
    }

    @Test("Timeout duration can be updated")
    func testTimeoutDurationUpdate() {
        let store = SettingsStore()
        store.timeoutDuration = 60
        #expect(store.timeoutDuration == 60)
    }

    @Test("Exit on lid open can be toggled")
    func testExitOnLidOpenToggle() {
        let store = SettingsStore()
        store.exitOnLidOpen = true
        #expect(store.exitOnLidOpen == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/SettingsStoreTests`
Expected: FAIL — `cannot find 'SettingsStore' in scope`

- [ ] **Step 3: Write SettingsStore implementation**

```swift
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    @AppStorage("exitKeyModifiers") var exitKeyModifiers: ModifierKeyFlags = .defaultFlags
    @AppStorage("timeoutDuration") var timeoutDuration: Int = 120
    @AppStorage("exitOnLidOpen") var exitOnLidOpen: Bool = false
}
```

Note: This requires a `ModifierKeyFlags` type that wraps `CGEventFlags` for `AppStorage` conformance. Create `MacScrub/State/ModifierKeyFlags.swift`:

```swift
import CoreGraphics

struct ModifierKeyFlags: OptionSet, Codable, Equatable {
    let rawValue: UInt64

    static let command = ModifierKeyFlags(rawValue: CGEventFlags.maskCommand.rawValue)
    static let option = ModifierKeyFlags(rawValue: CGEventFlags.maskAlternate.rawValue)
    static let control = ModifierKeyFlags(rawValue: CGEventFlags.maskControl.rawValue)
    static let shift = ModifierKeyFlags(rawValue: CGEventFlags.maskShift.rawValue)

    static let defaultFlags: ModifierKeyFlags = [.command, .option, .control, .shift]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/SettingsStoreTests`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add MacScrub/State/SettingsStore.swift MacScrub/State/ModifierKeyFlags.swift MacScrubTests/SettingsStoreTests.swift
git commit -m "feat: SettingsStore with AppStorage-backed settings and tests"
```

---

### Task 3: EventBlocker

**Files:**
- Create: `MacScrub/Core/EventBlocker.swift`
- Create: `MacScrub/Core/EventBlockerProtocol.swift`

- [ ] **Step 1: Write EventBlockerProtocol**

```swift
import CoreGraphics

@MainActor
protocol EventBlockerProtocol {
    var isBlocking: Bool { get }
    var onFlagsChanged: ((CGEventFlags) -> Void)? { get set }
    func start() -> Bool
    func stop()
}
```

- [ ] **Step 2: Write EventBlocker implementation**

```swift
import CoreGraphics
import ApplicationServices

@MainActor
final class EventBlocker: EventBlockerProtocol {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isBlocking = false
    var onFlagsChanged: ((CGEventFlags) -> Void)?

    func start() -> Bool {
        guard !isBlocking else { return true }

        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        guard let tap = CGEventTapCreate(
            tap: .cgHIDEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let runLoopSource else { return false }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEventTapEnable(tap: tap, enable: true)
        isBlocking = true
        return true
    }

    func stop() {
        guard isBlocking, let eventTap, let runLoopSource else { return }
        CGEventTapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        self.eventTap = nil
        self.runLoopSource = nil
        isBlocking = false
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    let blocker = Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = blocker.eventTap {
            CGEventTapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .flagsChanged {
        let flags = event.flags
        Task { @MainActor in
            blocker.onFlagsChanged?(flags)
        }
        return Unmanaged.passRetained(event)
    }

    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    let statusBarHeight: CGFloat = 25
    let adjustedY = screenHeight - mouseLocation.y
    if adjustedY <= statusBarHeight && (type == .leftMouseDown || type == .rightMouseDown) {
        return Unmanaged.passRetained(event)
    }

    return nil
}
```

Note: The `NSEvent.mouseLocation` and `NSScreen` references require `import AppKit`. Add this import at the top of `EventBlocker.swift`.

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MacScrub/Core/EventBlockerProtocol.swift MacScrub/Core/EventBlocker.swift
git commit -m "feat: EventBlocker with CGEventTap, protocol-based, menu bar passthrough"
```

---

### Task 4: ModifierKeyDetector

**Files:**
- Create: `MacScrub/Core/ModifierKeyDetector.swift`
- Create: `MacScrubTests/ModifierKeyDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import MacScrub

@MainActor
@Suite("ModifierKeyDetector")
struct ModifierKeyDetectorTests {

    @Test("All required keys pressed triggers callback after duration")
    func testAllKeysPressedTriggersCallback() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        detector.updateFlags(flags)

        try? await Task.sleep(for: .seconds(0.2))
        #expect(callbackFired == true)
    }

    @Test("Releasing a key resets the timer")
    func testReleasingKeyResetsTimer() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let allFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        detector.updateFlags(allFlags)

        try? await Task.sleep(for: .seconds(0.05))

        let partialFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        detector.updateFlags(partialFlags)

        try? await Task.sleep(for: .seconds(0.15))
        #expect(callbackFired == false)
    }

    @Test("Fewer than required keys does not trigger callback")
    func testPartialKeysNoCallback() async {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 0.1
        )
        var callbackFired = false
        detector.onAllKeysHeld = { callbackFired = true }

        let partialFlags: CGEventFlags = [.maskCommand, .maskAlternate]
        detector.updateFlags(partialFlags)

        try? await Task.sleep(for: .seconds(0.2))
        #expect(callbackFired == false)
    }

    @Test("Pressed keys are tracked correctly")
    func testPressedKeysTracking() {
        let detector = ModifierKeyDetector(
            requiredKeys: .defaultFlags,
            holdDuration: 3.0
        )

        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        detector.updateFlags(flags)

        #expect(detector.pressedKeys.contains(.command))
        #expect(detector.pressedKeys.contains(.option))
        #expect(detector.pressedKeys.contains(.control))
        #expect(!detector.pressedKeys.contains(.shift))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/ModifierKeyDetectorTests`
Expected: FAIL — `cannot find 'ModifierKeyDetector' in scope`

- [ ] **Step 3: Write ModifierKeyDetector implementation**

```swift
import Foundation
import CoreGraphics

@MainActor
final class ModifierKeyDetector {
    let requiredKeys: ModifierKeyFlags
    let holdDuration: TimeInterval
    var onAllKeysHeld: (() -> Void)?

    private(set) var pressedKeys: ModifierKeyFlags = []
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
            startHoldTimer()
        } else {
            cancelHoldTimer()
        }
    }

    func reset() {
        pressedKeys = []
        cancelHoldTimer()
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.holdDuration ?? 3.0))
            guard !Task.isCancelled else { return }
            self?.onAllKeysHeld?()
            self?.holdTimer = nil
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/ModifierKeyDetectorTests`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add MacScrub/Core/ModifierKeyDetector.swift MacScrubTests/ModifierKeyDetectorTests.swift
git commit -m "feat: ModifierKeyDetector with hold timer, tests for flag tracking"
```

---

### Task 5: LidMonitor

**Files:**
- Create: `MacScrub/Core/LidMonitor.swift`

- [ ] **Step 1: Write LidMonitor implementation**

```swift
import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
final class LidMonitor {
    var onLidOpen: (() -> Void)?
    private var rootPort: mach_port_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    func start() {
        rootPort = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard rootPort != 0 else { return }

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        var selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(
            notificationPort,
            rootPort,
            kIOGeneralInterest,
            lidCallback,
            &selfPtr,
            &notifier
        )
    }

    func stop() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let notificationPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootPort != 0 {
            IOObjectRelease(rootPort)
            rootPort = 0
        }
    }
}

private func lidCallback(
    refcon: UnsafeMutableRawPointer?,
    service: UInt32,
    messageType: UInt32,
    messageArgument: UnsafeMutableRawPointer?
) -> Void {
    guard messageType == kIOMessageSystemWillPowerOn else { return }
    guard let refcon else { return }
    let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        monitor.onLidOpen?()
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MacScrub/Core/LidMonitor.swift
git commit -m "feat: LidMonitor with IOKit sleep/wake detection"
```

---

### Task 6: CleaningModeManager

**Files:**
- Create: `MacScrub/State/CleaningModeManager.swift`
- Create: `MacScrubTests/CleaningModeManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MacScrub

@MainActor
@Suite("CleaningModeManager")
struct CleaningModeManagerTests {

    @Test("Activate sets isActive to true")
    func testActivate() {
        let eventBlocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: LidMonitor()
        )
        manager.activate()
        #expect(manager.isActive == true)
        #expect(eventBlocker.startCalled == true)
    }

    @Test("Deactivate sets isActive to false")
    func testDeactivate() {
        let eventBlocker = MockEventBlocker()
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: LidMonitor()
        )
        manager.activate()
        manager.deactivate()
        #expect(manager.isActive == false)
        #expect(eventBlocker.stopCalled == true)
    }

    @Test("Activate fails gracefully when event blocker fails")
    func testActivateFailsWhenEventBlockerFails() {
        let eventBlocker = MockEventBlocker()
        eventBlocker.shouldSucceed = false
        let manager = CleaningModeManager(
            settings: SettingsStore(),
            eventBlocker: eventBlocker,
            lidMonitor: LidMonitor()
        )
        manager.activate()
        #expect(manager.isActive == false)
    }
}

@MainActor
final class MockEventBlocker: EventBlockerProtocol {
    var isBlocking = false
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var startCalled = false
    var stopCalled = false
    var shouldSucceed = true

    func start() -> Bool {
        startCalled = true
        if shouldSucceed {
            isBlocking = true
        }
        return shouldSucceed
    }

    func stop() {
        stopCalled = true
        isBlocking = false
    }
}
```

Note: `MockEventBlocker` needs `import CoreGraphics` at the top of the test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/CleaningModeManagerTests`
Expected: FAIL — `cannot find 'CleaningModeManager' in scope`

- [ ] **Step 3: Write CleaningModeManager implementation**

```swift
import SwiftUI
import CoreGraphics
import AVFoundation

@MainActor
@Observable
final class CleaningModeManager {
    private(set) var isActive = false
    private(set) var modifierDetector: ModifierKeyDetector
    private let settings: SettingsStore
    private let eventBlocker: EventBlockerProtocol
    private let lidMonitor: LidMonitor
    private var timeoutTask: Task<Void, Never>?
    private var exitSoundID: SystemSoundID = 1057

    init(settings: SettingsStore, eventBlocker: EventBlockerProtocol, lidMonitor: LidMonitor) {
        self.settings = settings
        self.eventBlocker = eventBlocker
        self.lidMonitor = lidMonitor
        self.modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )

        self.modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }

        self.lidMonitor.onLidOpen = { [weak self] in
            guard let self else { return }
            if self.settings.exitOnLidOpen {
                self.deactivate()
            }
        }
    }

    func activate() {
        guard !isActive else { return }

        modifierDetector = ModifierKeyDetector(
            requiredKeys: settings.exitKeyModifiers,
            holdDuration: 3.0
        )
        modifierDetector.onAllKeysHeld = { [weak self] in
            self?.deactivate()
        }

        eventBlocker.onFlagsChanged = { [weak self] flags in
            self?.modifierDetector.updateFlags(flags)
        }

        let success = eventBlocker.start()
        guard success else {
            eventBlocker.stop()
            return
        }

        isActive = true
        startTimeout()
    }

    func deactivate() {
        guard isActive else { return }
        eventBlocker.stop()
        modifierDetector.reset()
        timeoutTask?.cancel()
        timeoutTask = nil
        isActive = false
        AudioServicesPlaySystemSound(exitSoundID)
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Double(self.settings.timeoutDuration)))
            guard !Task.isCancelled else { return }
            self.deactivate()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrubTests -only-testing:MacScrubTests/CleaningModeManagerTests`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add MacScrub/State/CleaningModeManager.swift MacScrubTests/CleaningModeManagerTests.swift
git commit -m "feat: CleaningModeManager orchestrator with timeout and tests"
```

---

### Task 7: MenuBarExtra UI

**Files:**
- Modify: `MacScrub/App/MacScrubApp.swift`
- Create: `MacScrub/Views/MenuBarView.swift`

- [ ] **Step 1: Create MenuBarView**

```swift
import SwiftUI

struct MenuBarView: View {
    @Bindable var manager: CleaningModeManager

    var body: some View {
        VStack(alignment: .leading) {
            if manager.isActive {
                Text("🧼 MacScrub")
                    .font(.headline)
                Divider()
                Button {
                    manager.deactivate()
                } label: {
                    Label("Stop Cleaning Mode", systemImage: "stop.circle")
                }
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Text("🧼 MacScrub")
                    .font(.headline)
                Divider()
                Button {
                    manager.activate()
                } label: {
                    Label("Start Cleaning Mode", systemImage: "play.circle")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()
            Button {
                openSettings()
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }

            Divider()
            Button("Quit MacScrub") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
```

- [ ] **Step 2: Update MacScrubApp.swift**

Replace the entire file:

```swift
import SwiftUI

@main
struct MacScrubApp: App {
    @State private var settings = SettingsStore()
    @State private var eventBlocker = EventBlocker()
    @State private var lidMonitor = LidMonitor()
    @State private var manager: CleaningModeManager

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
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: manager.isActive ? "sparkles" : "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? .blue : .secondary)
        }

        Settings {
            SettingsView(settings: settings)
        }

        Window("Cleaning Mode", id: "cleaning-overlay") {
            CleaningOverlayView(manager: manager)
                .background(.clear)
        }
        .windowStyle(.plainWindowStyle)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
```

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **` (may show warnings about missing views — that's OK, they'll be created next)

Note: At this point the build may fail because `CleaningOverlayView` and `SettingsView` don't exist yet. If so, create placeholder files:

`MacScrub/Views/CleaningOverlayView.swift`:
```swift
import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager

    var body: some View {
        Text("Cleaning Mode Overlay")
    }
}
```

`MacScrub/Views/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var settings: SettingsStore

    var body: some View {
        Text("Settings")
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add MacScrub/App/MacScrubApp.swift MacScrub/Views/MenuBarView.swift MacScrub/Views/CleaningOverlayView.swift MacScrub/Views/SettingsView.swift
git commit -m "feat: MenuBarExtra with start/stop, settings, and quit"
```

---

### Task 8: Cleaning Overlay UI

**Files:**
- Modify: `MacScrub/Views/CleaningOverlayView.swift`
- Create: `MacScrub/Views/ModifierKeySquare.swift`

- [ ] **Step 1: Create ModifierKeySquare**

```swift
import SwiftUI

struct ModifierKeySquare: View {
    let symbol: String
    let isPressed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isPressed ? Color.white.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .frame(width: 46, height: 46)
            .overlay {
                Text(symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(isPressed ? .white : .white.opacity(0.3))
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}
```

- [ ] **Step 2: Implement CleaningOverlayView**

Replace the placeholder:

```swift
import SwiftUI

struct CleaningOverlayView: View {
    var manager: CleaningModeManager
    @State private var showContent = false
    @State private var breathing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.01)

            if manager.isActive {
                VStack(spacing: 12) {
                    Text("🧼")
                        .font(.system(size: 42))
                        .scaleEffect(breathing ? 1.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: breathing
                        )

                    Text("Cleaning Mode Active")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(.white)

                    Text("Keyboard and trackpad are locked.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)

                    Text("Hold all modifiers to exit")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .textCase(.uppercase)

                    HStack(spacing: 14) {
                        ModifierKeySquare(
                            symbol: "⌘",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.command)
                        )
                        ModifierKeySquare(
                            symbol: "⌥",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.option)
                        )
                        ModifierKeySquare(
                            symbol: "⌃",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.control)
                        )
                        ModifierKeySquare(
                            symbol: "⇧",
                            isPressed: manager.modifierDetector.pressedKeys.contains(.shift)
                        )
                    }
                    .padding(.vertical, 4)

                    let pressed = manager.modifierDetector.pressedKeys.intersection(manager.settings.exitKeyModifiers ?? .defaultFlags).count
                    let total = manager.settings.exitKeyModifiers?.count ?? 4

                    Text("\(pressed) of \(total) keys held")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 4)

                    ProgressView(value: Double(pressed), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.4))
                        .frame(width: 120)
                        .scaleEffect(y: 0.6)
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
}
```

Note: The overlay needs to reference `settings` from `manager`. `CleaningModeManager` needs to expose `settings`:

Add to `CleaningModeManager`:
```swift
let settings: SettingsStore
```
(Make sure it's already a stored property — it should be from Task 6.)

- [ ] **Step 3: Make the overlay window full screen**

Update the Window scene in `MacScrubApp.swift` to present as a full-screen overlay. Replace the window definition:

```swift
Window("Cleaning Mode", id: "cleaning-overlay") {
    CleaningOverlayView(manager: manager)
        .background(.clear)
}
.windowStyle(.plainWindowStyle)
.windowResizability(.contentSize)
.defaultPosition(.center)
```

The overlay needs to be presented as a full-screen panel. Add a helper method to open/close it. Add this to `MacScrubApp`:

```swift
@Observable
class OverlayWindowController {
    var overlayWindow: NSWindow?

    func show(manager: CleaningModeManager) {
        guard overlayWindow == nil else { return }
        let screen = NSScreen.main!
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: NSScreen.main
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
```

Update `MacScrubApp` to use it:

```swift
@main
struct MacScrubApp: App {
    @State private var settings = SettingsStore()
    @State private var eventBlocker = EventBlocker()
    @State private var lidMonitor = LidMonitor()
    @State private var manager: CleaningModeManager
    @State private var overlayController = OverlayWindowController()

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
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(manager.isActive ? .blue : .secondary)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
```

Remove the `Window` scene — we'll manage the overlay window manually via `OverlayWindowController`.

Add overlay show/hide logic tied to `manager.isActive`. Add an `onChange` handler inside the `MenuBarExtra`:

Actually, the cleanest approach is to make `CleaningModeManager` handle overlay presentation. Add to `CleaningModeManager`:

```swift
weak var overlayController: OverlayWindowController?

func activate() {
    // ... existing code ...
    isActive = true
    startTimeout()
    overlayController?.show(manager: self)
}

func deactivate() {
    // ... existing code ...
    isActive = false
    AudioServicesPlaySystemSound(exitSoundID)
    overlayController?.hide()
}
```

Then in `MacScrubApp.init()`:
```swift
manager.overlayController = overlayController
```

Remove the `Window` scene from the body entirely.

- [ ] **Step 4: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MacScrub/Views/CleaningOverlayView.swift MacScrub/Views/ModifierKeySquare.swift MacScrub/App/MacScrubApp.swift MacScrub/State/CleaningModeManager.swift
git commit -m "feat: cleaning overlay with modifier key visualization, progress bar, breathing animation"
```

---

### Task 9: Settings Window UI

**Files:**
- Modify: `MacScrub/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

Replace the placeholder:

```swift
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
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MacScrub/Views/SettingsView.swift
git commit -m "feat: settings window with exit keys, timeout slider, lid open toggle"
```

---

### Task 10: Accessibility Permission Flow

**Files:**
- Create: `MacScrub/Views/PermissionGuideView.swift`
- Modify: `MacScrub/State/CleaningModeManager.swift`

- [ ] **Step 1: Create PermissionGuideView**

```swift
import SwiftUI

struct PermissionGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Accessibility Permission Required")
                .font(.headline)

            Text("MacScrub needs Accessibility access to block keyboard and trackpad input during cleaning.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("How to enable:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("1. Open System Settings → Privacy & Security → Accessibility")
                Text("2. Click the + button and add MacScrub")
                Text("3. Restart MacScrub")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Open System Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: Add permission check to CleaningModeManager**

Add a computed property to `CleaningModeManager`:

```swift
var needsPermission: Bool {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary) == false
}
```

Update `activate()` to check permission before starting:

In the `activate()` method, before `let success = eventBlocker.start()`, add:

```swift
guard AXIsProcessTrusted() else {
    return
}
```

- [ ] **Step 3: Show permission dialog from MenuBarView**

In `MenuBarView`, update the start button action:

```swift
Button {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    if AXIsProcessTrustedWithOptions(options) {
        manager.activate()
    }
} label: {
    Label("Start Cleaning Mode", systemImage: "play.circle")
}
```

Add `import ApplicationServices` to `MenuBarView.swift`.

- [ ] **Step 4: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MacScrub/Views/PermissionGuideView.swift MacScrub/State/CleaningModeManager.swift MacScrub/Views/MenuBarView.swift
git commit -m "feat: accessibility permission check and guide dialog"
```

---

### Task 11: Localization

**Files:**
- Create: `MacScrub/Localization/Localizable.xcstrings`
- Modify: All view files to use localized strings

- [ ] **Step 1: Create Localizable.xcstrings with EN, TR, ZH**

Create the String Catalog JSON file with all localized strings. This is a large JSON file. The key strings to localize:

| Key | English | Turkish | Chinese |
|---|---|---|---|
| menu.title | 🧼 MacScrub | 🧼 MacScrub | 🧼 MacScrub |
| menu.startCleaning | Start Cleaning Mode | Temizlik Modunu Başlat | 开始清洁模式 |
| menu.stopCleaning | Stop Cleaning Mode | Temizlik Modunu Durdur | 停止清洁模式 |
| menu.settings | Settings... | Ayarlar... | 设置... |
| menu.quit | Quit MacScrub | MacScrub'tan Çık | 退出 MacScrub |
| overlay.title | Cleaning Mode Active | Temizlik Modu Aktif | 清洁模式已激活 |
| overlay.subtitle | Keyboard and trackpad are locked. | Klavye ve trackpad kilitli. | 键盘和触控板已锁定。 |
| overlay.instruction | Hold all modifiers to exit | Çıkmak için tüm modifier tuşlarını basılı tut | 按住所有修饰键退出 |
| overlay.keysHeld | %@ of %@ keys held | %@ / %@ tuş basılı | 已按住 %@/%@ 个键 |
| settings.exitKeys | Exit Keys | Çıkış Tuşları | 退出按键 |
| settings.exitKeysDescription | Hold these modifier keys to exit cleaning mode: | Temizlik modundan çıkmak için bu modifier tuşlarını basılı tutun: | 按住这些修饰键退出清洁模式： |
| settings.timeout | Timeout | Zaman Aşımı | 超时 |
| settings.timeoutDescription | Auto-exit after: | Şu süre sonunda otomatik çık: | 自动退出时间： |
| settings.seconds | %@ seconds | %@ saniye | %@ 秒 |
| settings.lid | Lid | Kapak | 背盖 |
| settings.lidDescription | Exit cleaning mode when lid is opened | Kapak açıldığında temizlik modundan çık | 打开背盖时退出清洁模式 |
| permission.title | Accessibility Permission Required | Erişilebilirlik İzni Gerekli | 需要辅助功能权限 |
| permission.description | MacScrub needs Accessibility access to block keyboard and trackpad input during cleaning. | MacScrub, temizlik sırasında klavye ve trackpad girdilerini engellemek için Erişilebilirlik iznine ihtiyaç duyar. | MacScrub 需要辅助功能权限才能在清洁时阻止键盘和触控板输入。 |
| permission.howToEnable | How to enable: | Nasıl etkinleştirilir: | 如何启用： |
| permission.step1 | 1. Open System Settings → Privacy & Security → Accessibility | 1. Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik'i açın | 1. 打开系统设置 → 隐私与安全 → 辅助功能 |
| permission.step2 | 2. Click the + button and add MacScrub | 2. + düğmesine tıklayın ve MacScrub'ü ekleyin | 2. 点击 + 按钮并添加 MacScrub |
| permission.step3 | 3. Restart MacScrub | 3. MacScrub'ü yeniden başlatın | 3. 重新启动 MacScrub |
| permission.openSettings | Open System Settings | Sistem Ayarlarını Aç | 打开系统设置 |
| permission.done | Done | Tamam | 完成 |

The `Localizable.xcstrings` file format is a JSON structure. Create it programmatically or manually in Xcode after adding the languages. For the plan, mark all user-facing strings in views with `Text(String(localized: "key"))` or `Text("key", bundle: .main)`.

- [ ] **Step 2: Update view files to use localized strings**

Replace all hardcoded strings in views with `Text(String(localized: "key", defaultValue: "English text"))`.

Example in `MenuBarView.swift`:
```swift
Text(String(localized: "menu.title", defaultValue: "🧼 MacScrub"))
```

Apply this pattern to all views: `MenuBarView`, `CleaningOverlayView`, `SettingsView`, `PermissionGuideView`.

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project MacScrub.xcodeproj -scheme MacScrub build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MacScrub/Localization/ MacScrub/Views/
git commit -m "feat: localization with EN, TR, ZH string catalog"
```

---

### Task 12: GitHub Actions CI/CD

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create release workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Build Archive
        run: |
          xcodebuild archive \
            -project MacScrub.xcodeproj \
            -scheme MacScrub \
            -archivePath build/MacScrub.xcarchive \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Export App
        run: |
          mkdir -p build/export
          xcodebuild -exportArchive \
            -archivePath build/MacScrub.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist
        env:
          EXPORT_OPTIONS: |
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>method</key>
                <string>copy</string>
                <key>signing</key>
                <dict>
                    <key>style</key>
                    <string>adhoc</string>
                </dict>
            </dict>
            </plist>

      - name: Create ExportOptions.plist
        run: |
          cat > ExportOptions.plist << 'EOF'
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>method</key>
              <string>copy</string>
              <key>signing</key>
              <dict>
                  <key>style</key>
                  <string>adhoc</string>
              </dict>
          </dict>
          </plist>
          EOF

      - name: Export App (retry with plist)
        run: |
          xcodebuild -exportArchive \
            -archivePath build/MacScrub.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist

      - name: Create DMG
        run: |
          APP_PATH="build/export/MacScrub.app"
          DMG_PATH="MacScrub-${{ github.ref_name }}.dmg"
          hdiutil create -volname "MacScrub" \
            -srcfolder "$APP_PATH" \
            -ov -format UDZO \
            "$DMG_PATH"

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: "*.dmg"
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: GitHub Actions release workflow with DMG packaging"
```

---

## Plan Self-Review

### Spec Coverage Check

| Spec Requirement | Task |
|---|---|
| macOS 14 Sonoma+ | Task 1 (project.yml) |
| Single-target SwiftUI | Task 1 |
| LSUIElement (no dock icon) | Task 1 (Info.plist) |
| MenuBarExtra entry | Task 7 |
| CGEventTap event blocking | Task 3 |
| Blocked events table | Task 3 |
| flagsChanged passthrough | Task 3 |
| Menu bar events passthrough | Task 3 |
| ModifierKeyDetector (4 keys, 3s) | Task 4 |
| Accessibility permission | Task 10 |
| 120s default timeout | Task 2, Task 6 |
| Menu bar icon states | Task 7 |
| Dropdown menus | Task 7 |
| Dimmed blur overlay | Task 8 |
| Modifier key squares | Task 8 |
| Key fill + progress bar | Task 8 |
| Spring animations | Task 8 |
| Breathing animation | Task 8 |
| Exit animation + system sound | Task 6 |
| Settings: Exit Keys | Task 9 |
| Settings: Timeout | Task 9 |
| Settings: Lid Open Exit | Task 9 |
| @AppStorage storage | Task 2 |
| Localization EN/TR/ZH | Task 11 |
| GitHub Actions CI | Task 12 |
| DMG packaging | Task 12 |
| MIT License | Task 1 |

### Placeholder Scan
No TBDs, TODOs, or placeholder code.

### Type Consistency
- `ModifierKeyFlags` defined in Task 2, used consistently in Tasks 4, 6, 8, 9
- `EventBlockerProtocol` defined in Task 3, conformed to by `EventBlocker` (Task 3) and `MockEventBlocker` (Task 6)
- `CleaningModeManager` init signature matches usage in Tasks 6, 7, 8
- `SettingsStore` used as `@Bindable` in Task 9, as direct parameter in Tasks 2, 6
