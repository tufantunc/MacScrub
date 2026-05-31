# App Icon + Proper DMG Installer — Design

**Date:** 2026-05-31
**Status:** Approved

## Background

When the released DMG is opened, the window shows only the app bundle with no
Applications folder and no drag affordance, and the app itself displays macOS's
generic placeholder icon — `MacScrub/Assets.xcassets/AppIcon.appiconset/` contains
only `Contents.json` with no image files. The release workflow builds the DMG with
a bare `hdiutil create` (just the `.app`, no layout).

This adds a real branded app icon and a proper macOS-style installer DMG (app icon
on the left, Applications folder on the right, drag-to-install).

## Goals

- Ship a real **app icon**: a light/white gradient squircle with the teal sparkles
  (✨) mark, consistent with the in-app branding. It must render in Dock, Finder,
  and the DMG window.
- Produce a **proper installer DMG**: the app icon and an Applications-folder alias
  laid out side by side in a sized window so the user can drag-to-install — the
  standard macOS experience.

## Non-Goals

- No custom DMG background image or arrow graphic (layout "B", minimal, was chosen).
- No custom DMG volume (mounted-disk) icon.
- No change to in-app visuals (in-app branding keeps using the `sparkles` SF Symbol;
  the bundle `AppIcon` is separate).
- No code signing / notarization changes (ad-hoc distribution is retained).

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Icon style | White/light gradient squircle + teal sparkles (matches in-app idle icon) |
| Icon generation | Generated locally and committed (not built in CI) |
| DMG tooling | `create-dmg` (the `brew install create-dmg` shell tool) |
| DMG layout | Minimal "B": app icon left + Applications alias right, no background image |

## Architecture

### App icon — `MacScrub/Assets.xcassets/AppIcon.appiconset/`

A real icon is generated locally and committed; CI just builds the app (icon baked in).

- **Master render:** a small Swift script (run with `swift`) draws a 1024×1024 PNG
  using CoreGraphics/AppKit: a continuous-corner rounded square ("squircle") filled
  with a near-white vertical gradient and a subtle hairline border, with the three
  sparkles bezier shapes (the same paths used in the in-app mark) drawn centered in
  the teal accent. The script writes `icon_1024.png`.
- **Size set:** `sips` downscales the master to every size the macOS asset catalog
  declares — 16, 32, 128, 256, 512 at @1x and @2x (i.e. 16, 32, 64, 256, 512, 1024
  px, etc.) — written into the `AppIcon.appiconset`.
- **Catalog:** `Contents.json` is updated so each existing size/scale entry gains a
  `filename` pointing at its PNG. The PNGs + updated `Contents.json` are committed.
- The generator script is kept in the repo (e.g. `scripts/generate-icon.swift`) so
  the icon can be regenerated, but it is a build-time-independent tool — not run by
  Xcode or CI.

### DMG — `.github/workflows/release.yml` "Create DMG" step

Replace the bare `hdiutil create` with `create-dmg`:

```yaml
      - name: Create DMG
        run: |
          brew install create-dmg
          create-dmg \
            --volname "MacScrub" \
            --window-size 560 360 \
            --icon-size 96 \
            --icon "MacScrub.app" 150 180 \
            --app-drop-link 410 180 \
            --no-internet-enable \
            "MacScrub-${GITHUB_REF_NAME}.dmg" \
            "build/export/MacScrub.app"
```

- `--app-drop-link` adds the Applications-folder alias on the right; `--icon`
  positions the app on the left; `--window-size`/`--icon-size` set the window.
- No `--background` → minimal layout B (no background image/arrow).
- Output filename and the downstream "Create Release" upload are unchanged
  (`MacScrub-<tag>.dmg`, matching the existing `files: "*.dmg"` glob).

## Risks / Notes

- `create-dmg` styles the window via AppleScript/Finder, which is occasionally flaky
  on headless GitHub runners. It's the standard tool and usually works on the
  `macos-15` runner; if a run fails on the styling step we iterate (as we did
  stabilizing the v1.0.0 release pipeline). The deterministic fallback, if needed, is
  a pre-built committed `.DS_Store` assembled with `hdiutil` (more setup, no
  AppleScript) — not adopted now to keep the change simple.
- `create-dmg` can exit non-zero in some edge cases even when the DMG is produced;
  if observed, the step is adjusted to tolerate its documented quirks.
- Icon generation runs once locally; the runner only needs the committed PNGs.

## Testing / Verification

- **Icon:** build the app and confirm the bundled `.app` shows the new branded icon
  in Finder/Dock (not the generic placeholder).
- **DMG:** run the release workflow on a tag, download the produced DMG, open it, and
  confirm the window shows the MacScrub icon on the left, the Applications folder on
  the right, and that the app can be dragged onto it.
- No unit tests — this is packaging/asset work. The existing 49 tests stay green
  (no source behavior changes).
