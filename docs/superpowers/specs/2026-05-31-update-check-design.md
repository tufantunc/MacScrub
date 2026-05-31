# Automatic Update Notification — Design

**Date:** 2026-05-31
**Status:** Approved

## Background

MacScrub is distributed as a DMG via GitHub Releases (tags like `v1.0.0`). The app
is signed with an Apple Development certificate (not Developer ID) and is not
notarized; CI builds the released app ad-hoc signed. There is currently no way for
a running copy to learn that a newer version exists.

This adds a lightweight, dependency-free update **notification**: on launch the app
checks the latest GitHub release, and if a newer version exists it surfaces a
"New version available" affordance in the idle window and the menu that opens the
GitHub release page for a manual download/install.

## Goals

- On launch, silently check the latest GitHub release once.
- If the latest release is newer than the running version, show a "New version
  available (vX.Y.Z)" affordance at the bottom of the idle window and in the menu.
- Clicking it opens the GitHub release page in the browser.
- Keep the running app's version in sync with release tags so the comparison is
  reliable.

## Non-Goals

- No real self-update (download/replace/relaunch). True self-update needs Developer
  ID + notarization to avoid Gatekeeper friction and would re-prompt the
  Accessibility permission after each ad-hoc-signed build — out of scope.
- No Sparkle / appcast / external update infrastructure.
- No periodic or scheduled re-checks (launch-only).
- No manual "Check for Updates…" menu item (the banner is the affordance).

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Update action | Open the GitHub release page in the browser (manual install) |
| Version source | Inject `MARKETING_VERSION` from the git tag at build time so the bundle version always equals the released tag |
| Check timing | Once on launch, asynchronous, non-blocking; silent on failure |
| Release selection | GitHub `/releases/latest` (excludes drafts and pre-releases) |

## Architecture

### `UpdateChecker` — `MacScrub/State/UpdateChecker.swift` (new)

A `@MainActor @Observable` service, constructed once in `MacScrubApp.init` and
injected into `MainWindowView` and `MenuBarView` (same single-shared-instance
pattern as `SettingsStore` / `CleaningModeManager` / `HubNavigation`).

- `private(set) var availableUpdate: UpdateInfo?` — `nil` means up-to-date,
  unknown, or the check failed. Observed by the views.
- `struct UpdateInfo: Equatable { let version: String; let pageURL: URL }`.
- `func checkForUpdate() async` — fetches the latest release, compares versions,
  and sets `availableUpdate` only when the latest is strictly newer than the
  current bundle version. Any thrown error is swallowed (stays `nil`). Called once
  from the main window's `.task`/`.onAppear` on launch.
- Reads the current version from `Bundle.main` `CFBundleShortVersionString`
  (injectable for tests).

### Release fetching behind a protocol (testable)

Mirrors the existing `EventBlockerProtocol` / `MockEventBlocker` approach:

```swift
struct ReleaseInfo: Decodable, Equatable {
    let tag_name: String
    let html_url: URL
}

protocol ReleaseFetching {
    func fetchLatestRelease() async throws -> ReleaseInfo
}
```

- `GitHubReleaseFetcher: ReleaseFetching` — `URLSession` GET to
  `https://api.github.com/repos/tufantunc/MacScrub/releases/latest`, decodes
  `ReleaseInfo` (the snake_case keys match GitHub's JSON, so no custom keys).
- Tests inject a `MockReleaseFetcher` returning a canned `ReleaseInfo` (or throwing).

### Pure version comparison

A free, unit-tested function (in `UpdateChecker.swift`):

```swift
func isVersion(_ latest: String, newerThan current: String) -> Bool
```

- Strips a leading `v`/`V`, splits on `.`, compares component-by-component as
  integers (missing trailing components treated as 0, so `1.0` == `1.0.0`).
- Non-numeric components are treated as 0 (defensive; never crashes).
- Returns `true` only when `latest` is strictly greater.

`UpdateChecker` sets `availableUpdate` when
`isVersion(release.tag_name, newerThan: currentVersion)` is true, using the
release's `html_url` as `pageURL`.

### UI

Both surfaces render only when `updateChecker.availableUpdate != nil`.

- **Idle window (`MainWindowView`)** — a subtle teal row/pill at the bottom of the
  idle view: localized "New version available (vX.Y.Z)" with a trailing chevron.
  Tapping it calls `NSWorkspace.shared.open(info.pageURL)`. Placed below the
  existing support text.
- **Menu (`MenuBarView`)** — a button near the top: "New version available
  (vX.Y.Z)…", opening the same URL. Appears above the status section.

### Version injection (keeps bundle version == tag)

- `project.yml` base settings gain `MARKETING_VERSION: "1.0.0"` (default for local
  / dev builds).
- `MacScrub/App/Info.plist`: `CFBundleShortVersionString` becomes
  `$(MARKETING_VERSION)`.
- `.github/workflows/release.yml`: the archive step passes
  `MARKETING_VERSION="${GITHUB_REF_NAME#v}"` so a `v1.2.3` tag produces a bundle
  whose short version is `1.2.3`. `CFBundleVersion` is unaffected (the check uses
  only the short version string).

## Data flow

```
launch → MainWindowView.task → UpdateChecker.checkForUpdate()
   → ReleaseFetching.fetchLatestRelease()  (GitHub /releases/latest)
   → isVersion(tag_name, newerThan: bundleShortVersion)
      → true  → availableUpdate = UpdateInfo(version, pageURL)  (@Observable)
      → false/throw → availableUpdate stays nil  (silent)

availableUpdate != nil → idle-window row + menu item shown
   → tap → NSWorkspace.open(pageURL)  (GitHub release page)
```

## Localization

Add `update.available` for en / tr / zh-Hans, formatted with the version, e.g.
`"New version available (%@)"` / `"Yeni sürüm mevcut (%@)"` / `"有新版本可用 (%@)"`.
The menu item reuses the same string.

## Testing

- **`isVersion(_:newerThan:)`** (pure): newer, older, equal; differing component
  counts (`1.0` vs `1.0.0` → not newer); `v` prefix handling; non-numeric input
  doesn't crash.
- **`UpdateChecker`** with `MockReleaseFetcher`: a newer tag sets `availableUpdate`
  with the right version + URL; an equal/older tag leaves it `nil`; a thrown error
  leaves it `nil`.
- Views verified by build + manual check.
- Existing 40 tests stay green.

## Risks / Notes

- Unauthenticated GitHub API allows ~60 requests/hour per IP; one launch-time check
  is well within limits.
- In dev builds the bundle version is the `project.yml` default (`1.0.0`); the check
  still runs and simply reports no update against the matching latest release.
- The injected version only affects released (CI) builds; nothing else relies on
  `CFBundleShortVersionString`.
