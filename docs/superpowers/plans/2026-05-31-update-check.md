# Automatic Update Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On launch, check the latest GitHub release and—if newer than the running version—show a "New version available" affordance in the idle window and the menu that opens the GitHub release page.

**Architecture:** A `@MainActor @Observable UpdateChecker` (constructed once in `MacScrubApp`, injected into the views) fetches the latest release behind a `ReleaseFetching` protocol (real `URLSession` fetcher + test mock), compares versions with a pure, unit-tested `isVersion` function, and publishes `availableUpdate`. The bundle version is kept equal to the release tag via `MARKETING_VERSION` injected at build time.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+) `@Observable`, async/await `URLSession`, Swift Testing, XcodeGen, GitHub Actions.

---

## File Structure

- `MacScrub/State/UpdateChecker.swift` — **create**: `ReleaseInfo`, `ReleaseFetching` protocol, `GitHubReleaseFetcher`, `UpdateInfo`, the pure `isVersion(_:newerThan:)` function, and the `UpdateChecker` `@Observable` service.
- `MacScrubTests/UpdateCheckerTests.swift` — **create**: tests for `isVersion` and `UpdateChecker` (with a mock fetcher).
- `MacScrub/Localization/Localizable.xcstrings` — **modify**: add `update.available`.
- `project.yml` — **modify**: add `MARKETING_VERSION: "1.0.0"` default.
- `MacScrub/App/Info.plist` — **modify**: `CFBundleShortVersionString` → `$(MARKETING_VERSION)`.
- `.github/workflows/release.yml` — **modify**: pass `MARKETING_VERSION` from the tag to the archive build.
- `MacScrub/App/MacScrubApp.swift` — **modify**: construct + inject `UpdateChecker`, trigger the launch check.
- `MacScrub/Views/MainWindowView.swift` — **modify**: idle-window update banner.
- `MacScrub/Views/MenuBarView.swift` — **modify**: menu update item.

**Test command** (Swift Testing — the real result is the `Test run with N tests in M suites passed` line; ignore the legacy `Executed 0 tests` line):
```bash
xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet
```

**New files** are registered by `xcodegen generate` (sources are directory-globbed); do not hand-edit `project.pbxproj`. Commit the regenerated pbxproj with new files.

**Build-artifact note:** unless a task edits it, revert `MacScrub/Localization/Localizable.xcstrings` before staging (`git checkout -- MacScrub/Localization/Localizable.xcstrings`), and never stage `…/UserInterfaceState.xcuserstate`.

---

## Task 1: UpdateChecker + version comparison (with tests)

**Files:**
- Create: `MacScrub/State/UpdateChecker.swift`
- Test: `MacScrubTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Create the failing test file `MacScrubTests/UpdateCheckerTests.swift`**

```swift
import Testing
import Foundation
@testable import MacScrub

@Suite("isVersion")
struct IsVersionTests {

    @Test("Newer major/minor/patch is detected")
    func testNewer() {
        #expect(isVersion("v1.1.0", newerThan: "1.0.0") == true)
        #expect(isVersion("2.0.0", newerThan: "1.9.9") == true)
        #expect(isVersion("v2", newerThan: "1.9.9") == true)
    }

    @Test("Equal versions are not newer (including differing component counts)")
    func testEqual() {
        #expect(isVersion("1.0.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "1.0") == false)
    }

    @Test("Older versions are not newer")
    func testOlder() {
        #expect(isVersion("0.9.0", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "1.1.0") == false)
    }

    @Test("Components compare numerically, not lexically")
    func testNumeric() {
        #expect(isVersion("1.10.0", newerThan: "1.2.0") == true)
        #expect(isVersion("1.2.0", newerThan: "1.10.0") == false)
    }

    @Test("Non-numeric components are treated as 0 and never crash")
    func testNonNumeric() {
        #expect(isVersion("abc", newerThan: "1.0.0") == false)
        #expect(isVersion("1.0.0", newerThan: "abc") == true)
    }
}

@MainActor
@Suite("UpdateChecker")
struct UpdateCheckerTests {

    private func info(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tag_name: tag, html_url: URL(string: "https://github.com/tufantunc/MacScrub/releases/tag/\(tag)")!)
    }

    @Test("Newer release publishes availableUpdate")
    func testNewerPublishes() async {
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .success(info("v1.1.0"))),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate?.version == "v1.1.0")
        #expect(checker.availableUpdate?.pageURL.absoluteString.contains("v1.1.0") == true)
    }

    @Test("Equal release leaves availableUpdate nil")
    func testEqualNil() async {
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .success(info("v1.0.0"))),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate == nil)
    }

    @Test("Fetch error leaves availableUpdate nil")
    func testErrorNil() async {
        struct Boom: Error {}
        let checker = UpdateChecker(
            fetcher: MockReleaseFetcher(result: .failure(Boom())),
            currentVersion: "1.0.0"
        )
        await checker.checkForUpdate()
        #expect(checker.availableUpdate == nil)
    }
}

struct MockReleaseFetcher: ReleaseFetching {
    var result: Result<ReleaseInfo, Error>
    func fetchLatestRelease() async throws -> ReleaseInfo { try result.get() }
}
```

- [ ] **Step 2: Register files and confirm RED**

Run `xcodegen generate`, then the test command.
Expected: FAIL — compile errors (`cannot find 'isVersion'`, `ReleaseInfo`, `UpdateChecker`, `ReleaseFetching`).

- [ ] **Step 3: Create `MacScrub/State/UpdateChecker.swift`**

```swift
import Foundation
import Observation

/// Subset of GitHub's `/releases/latest` payload we care about. Keys match the
/// JSON (snake_case), so no custom CodingKeys are needed; extra fields are ignored.
struct ReleaseInfo: Decodable, Equatable {
    let tag_name: String
    let html_url: URL
}

/// What the UI needs to surface an available update.
struct UpdateInfo: Equatable {
    let version: String   // the release tag as published, e.g. "v1.1.0"
    let pageURL: URL      // the GitHub release page
}

protocol ReleaseFetching {
    func fetchLatestRelease() async throws -> ReleaseInfo
}

/// Fetches the latest published (non-draft, non-prerelease) GitHub release.
struct GitHubReleaseFetcher: ReleaseFetching {
    private let url = URL(string: "https://api.github.com/repos/tufantunc/MacScrub/releases/latest")!

    func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
}

/// Returns true only when `latest` is strictly newer than `current`. Strips a
/// leading `v`/`V`, compares dot-separated components numerically (missing trailing
/// components count as 0, so "1.0" == "1.0.0"); non-numeric components count as 0.
func isVersion(_ latest: String, newerThan current: String) -> Bool {
    func components(_ s: String) -> [Int] {
        let trimmed = (s.first == "v" || s.first == "V") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
    let a = components(latest)
    let b = components(current)
    for i in 0..<max(a.count, b.count) {
        let l = i < a.count ? a[i] : 0
        let c = i < b.count ? b[i] : 0
        if l != c { return l > c }
    }
    return false
}

@MainActor
@Observable
final class UpdateChecker {
    private(set) var availableUpdate: UpdateInfo?

    private let fetcher: ReleaseFetching
    private let currentVersion: String
    private var didCheck = false

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
    }

    /// Checks once per process; failures are silent (availableUpdate stays nil).
    func checkForUpdate() async {
        guard !didCheck else { return }
        didCheck = true
        do {
            let release = try await fetcher.fetchLatestRelease()
            if isVersion(release.tag_name, newerThan: currentVersion) {
                availableUpdate = UpdateInfo(version: release.tag_name, pageURL: release.html_url)
            }
        } catch {
            // Silent: no banner on network/decode failure.
        }
    }
}
```

- [ ] **Step 4: Register and confirm GREEN**

Run `xcodegen generate`, then the test command.
Expected: PASS — `Test run with 49 tests in 10 suites passed` (40 existing + 9 new).

- [ ] **Step 5: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/State/UpdateChecker.swift MacScrubTests/UpdateCheckerTests.swift MacScrub.xcodeproj/project.pbxproj
git commit -m "feat: UpdateChecker + version comparison (GitHub latest release)"
```

---

## Task 2: Localization string

**Files:**
- Modify: `MacScrub/Localization/Localizable.xcstrings`

- [ ] **Step 1: Run the script**

```bash
python3 - <<'PY'
import json
path = "MacScrub/Localization/Localizable.xcstrings"
d = json.load(open(path, encoding="utf-8"))
d["strings"]["update.available"] = {"localizations": {
    "en":      {"stringUnit": {"state": "translated", "value": "New version available (%@)"}},
    "tr":      {"stringUnit": {"state": "translated", "value": "Yeni sürüm mevcut (%@)"}},
    "zh-Hans": {"stringUnit": {"state": "translated", "value": "有新版本可用 (%@)"}},
}}
json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("added update.available; total keys", len(d["strings"]))
PY
```
Expected output: `added update.available; total keys 52`.

- [ ] **Step 2: Confirm it parses**

```bash
python3 -c "import json;d=json.load(open('MacScrub/Localization/Localizable.xcstrings'));print(d['strings']['update.available']['localizations']['tr']['stringUnit']['value'])"
```
Expected: `Yeni sürüm mevcut (%@)`

- [ ] **Step 3: Build to confirm the catalog is valid**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit (the xcstrings IS the intended change)**

```bash
git add MacScrub/Localization/Localizable.xcstrings
git commit -m "i18n: add update.available string"
```

---

## Task 3: Inject version from the release tag

Keeps the bundle's short version equal to the published tag so the update check is reliable.

**Files:**
- Modify: `project.yml`
- Modify: `MacScrub/App/Info.plist`
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add a default `MARKETING_VERSION` in `project.yml`**

In `project.yml`, the `settings.base` block currently begins:
```yaml
settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
```
Add `MARKETING_VERSION` as the first entry under `base`:
```yaml
settings:
  base:
    MARKETING_VERSION: "1.0.0"
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
```

- [ ] **Step 2: Use the variable in `Info.plist`**

In `MacScrub/App/Info.plist`, change:
```xml
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
```
to:
```xml
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
```

- [ ] **Step 3: Inject the tag's version in the release workflow**

In `.github/workflows/release.yml`, the "Build Archive" step currently runs:
```yaml
      - name: Build Archive
        run: |
          xcodebuild archive \
            -project MacScrub.xcodeproj \
            -scheme MacScrub \
            -archivePath build/MacScrub.xcarchive \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO
```
Replace it with (adds `MARKETING_VERSION` derived from the tag, e.g. `v1.2.3` → `1.2.3`):
```yaml
      - name: Build Archive
        run: |
          xcodebuild archive \
            -project MacScrub.xcodeproj \
            -scheme MacScrub \
            -archivePath build/MacScrub.xcarchive \
            MARKETING_VERSION="${GITHUB_REF_NAME#v}" \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 4: Regenerate, build, and verify the version resolves**

```bash
xcodegen generate
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build -quiet
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Build/Products/Debug/MacScrub.app/Contents/Info.plist
```
Expected: `BUILD SUCCEEDED` and the printed value is `1.0.0` (the default; CI overrides it from the tag).

- [ ] **Step 5: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add project.yml MacScrub/App/Info.plist .github/workflows/release.yml MacScrub.xcodeproj/project.pbxproj
git commit -m "build: inject MARKETING_VERSION from release tag; default 1.0.0"
```

---

## Task 4: Wire UpdateChecker into the app + idle-window banner + launch check

Adds the `updateChecker` to `MacScrubApp`, passes it to `MainWindowView` (which gains the param), triggers the launch check, and shows the idle banner. `MenuBarView` is updated in Task 5, so its call site stays unchanged here (build stays green).

**Files:**
- Modify: `MacScrub/App/MacScrubApp.swift`
- Modify: `MacScrub/Views/MainWindowView.swift`

- [ ] **Step 1: Construct and inject `UpdateChecker` in `MacScrubApp.swift`**

(a) Add a `@State` property below `@State private var nav: HubNavigation`:
```swift
    @State private var updateChecker: UpdateChecker
```

(b) In `init()`, after `let nav = HubNavigation()`, add:
```swift
        let updateChecker = UpdateChecker()
```
and after `self._nav = State(initialValue: nav)`, add:
```swift
        self._updateChecker = State(initialValue: updateChecker)
```

(c) Change the `Window` scene content from:
```swift
            MainWindowView(manager: manager, settings: settings, nav: nav)
                .onAppear {
                    manager.overlayController = overlayController
                    NSApp.activate(ignoringOtherApps: true)
                }
```
to:
```swift
            MainWindowView(manager: manager, settings: settings, nav: nav, updateChecker: updateChecker)
                .onAppear {
                    manager.overlayController = overlayController
                    NSApp.activate(ignoringOtherApps: true)
                }
                .task {
                    await updateChecker.checkForUpdate()
                }
```
Leave the `MenuBarView(manager: manager, settings: settings, nav: nav)` call unchanged.

- [ ] **Step 2: Add the param + banner to `MainWindowView.swift`**

(a) Add the property below `@Bindable var nav: HubNavigation`:
```swift
    @Bindable var updateChecker: UpdateChecker
```

(b) In `idleView`, the block currently ends with the support text:
```swift
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
```
Replace that with (reduces the support text's bottom padding and adds the conditional banner below it):
```swift
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
```
(`MainWindowView` already imports `AppKit`, so `NSWorkspace` is available.)

- [ ] **Step 3: Build**

Run: `xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/App/MacScrubApp.swift MacScrub/Views/MainWindowView.swift
git commit -m "feat: idle-window update banner + launch update check"
```

---

## Task 5: Menu update item

**Files:**
- Modify: `MacScrub/Views/MenuBarView.swift`
- Modify: `MacScrub/App/MacScrubApp.swift`

- [ ] **Step 1: Add the param + menu item to `MenuBarView.swift`**

(a) Add `import AppKit` below the existing imports:
```swift
import SwiftUI
import AppKit
import ApplicationServices
```

(b) Add the property below `@Bindable var nav: HubNavigation`:
```swift
    @Bindable var updateChecker: UpdateChecker
```

(c) At the very start of `body` (before the `Section(...)`), add the conditional item:
```swift
    var body: some View {
        if let update = updateChecker.availableUpdate {
            Button(String(format: String(localized: "update.available",
                                         defaultValue: "New version available (%@)"), update.version)) {
                NSWorkspace.shared.open(update.pageURL)
            }
            Divider()
        }

        Section(manager.isActive
```
(The rest of `body` is unchanged.)

- [ ] **Step 2: Pass `updateChecker` to `MenuBarView` in `MacScrubApp.swift`**

Change:
```swift
            MenuBarView(manager: manager, settings: settings, nav: nav)
```
to:
```swift
            MenuBarView(manager: manager, settings: settings, nav: nav, updateChecker: updateChecker)
```

- [ ] **Step 3: Build and run the full test suite**

Run: `xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` and `Test run with 49 tests in 10 suites passed`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add MacScrub/Views/MenuBarView.swift MacScrub/App/MacScrubApp.swift
git commit -m "feat: menu update item"
```

---

## Task 6: Manual verification

**Files:** none.

- [ ] **Step 1: Verify no-update path (current version == latest release)**

```bash
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build -quiet
open build/Build/Products/Debug/MacScrub.app
```
The bundle version is `1.0.0` and the latest release is `v1.0.0`, so **no** banner/menu item should appear (they only show when a newer release exists). Confirm the idle window and menu look unchanged. Quit the app.

- [ ] **Step 2: Verify the update-available path with a temporary older version**

Force an "older" running version to simulate an update being available:
```bash
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug -destination 'platform=macOS' -derivedDataPath build MARKETING_VERSION=0.9.0 -quiet
open build/Build/Products/Debug/MacScrub.app
```
Now the running version (0.9.0) is older than the latest release (v1.0.0). After launch, confirm:
- a teal "New version available (v1.0.0)" banner appears at the bottom of the idle window;
- the menu shows a "New version available (v1.0.0)…" item at the top;
- clicking either opens the GitHub release page in the browser.
Quit the app.

- [ ] **Step 3: Commit (only if verification revealed fixes)**

If Step 2 surfaced issues you fixed, commit them; otherwise nothing to commit here.

---

## Self-Review Notes

- **Spec coverage:** launch-time silent check → Task 1 (`UpdateChecker`/`didCheck`) + Task 4 (`.task`); idle banner → Task 4; menu item → Task 5; opens GitHub release page → Tasks 4/5 (`NSWorkspace.open(pageURL)`); version comparison → Task 1 (`isVersion`); tag/bundle version sync → Task 3; localization → Task 2; tests → Task 1.
- **Type consistency:** `ReleaseInfo(tag_name:html_url:)`, `UpdateInfo(version:pageURL:)`, `ReleaseFetching.fetchLatestRelease()`, `UpdateChecker(fetcher:currentVersion:)` + `availableUpdate` + `checkForUpdate()`, and the global `isVersion(_:newerThan:)` are defined in Task 1 and used identically in Tasks 4/5 and the tests. `MockReleaseFetcher` is defined in the Task 1 test file. The `update.available` key (Task 2) matches the `String(localized:)` references in Tasks 4/5. The `updateChecker` parameter is added to each view together with its `MacScrubApp` call site (Task 4 for `MainWindowView`, Task 5 for `MenuBarView`) so every task builds.
- **No placeholders:** every code step is complete; the i18n and version-resolution steps are concrete commands with expected output.
