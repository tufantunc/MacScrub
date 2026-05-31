# App Icon + Proper DMG Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commit messages:** do NOT add any `Co-Authored-By` / Claude / AI attribution trailer (user preference).

**Goal:** Give MacScrub a real branded app icon and turn the released DMG into a proper drag-to-Applications installer.

**Architecture:** A Swift/AppKit script renders a 1024px master icon (light squircle + teal sparkles), `sips` produces every macOS size into `AppIcon.appiconset`, and the icon is committed (built into the app, not generated in CI). The release workflow's DMG step switches from a bare `hdiutil create` to `create-dmg` with an Applications-folder drop link and positioned icons (no background image).

**Tech Stack:** Swift/AppKit + `sips` (icon), `create-dmg` via Homebrew (DMG), GitHub Actions. No app source/behavior changes.

---

## File Structure

- `scripts/generate-icon.swift` — **create**: AppKit script that renders the 1024px master icon PNG.
- `MacScrub/Assets.xcassets/AppIcon.appiconset/*.png` — **create**: the 10 sized icon PNGs.
- `MacScrub/Assets.xcassets/AppIcon.appiconset/Contents.json` — **modify**: add `filename` to each entry.
- `.github/workflows/release.yml` — **modify**: replace the "Create DMG" step with `create-dmg`.

**Notes**
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` is already set by XcodeGen, so committed PNGs are picked up automatically — no `project.yml` change.
- The current `Contents.json` declares 10 `mac` entries: 16/32/128/256/512 at @1x and @2x.
- No unit tests (asset/packaging work); the existing 49 tests must stay green.
- Build-artifact: revert `MacScrub/Localization/Localizable.xcstrings` before staging if a build reformats it; never stage `UserInterfaceState.xcuserstate`.

---

## Task 1: Generate and wire the app icon

**Files:**
- Create: `scripts/generate-icon.swift`
- Create: `MacScrub/Assets.xcassets/AppIcon.appiconset/AppIcon-16.png` (and the other 9)
- Modify: `MacScrub/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Create `scripts/generate-icon.swift`**

```swift
import AppKit

// Renders a 1024x1024 app-icon master: a light squircle with the teal "sparkles"
// mark centered. Usage: swift scripts/generate-icon.swift <output.png>
let px = 1024
let size = CGFloat(px)
let canvas = NSSize(width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }
rep.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// transparent canvas (corners outside the squircle stay clear)
NSColor.clear.set()
NSRect(origin: .zero, size: canvas).fill()

// squircle
let inset: CGFloat = 96
let r = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = r.width * 0.2237
let squircle = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)

// light vertical gradient fill
let gradient = NSGradient(colors: [
    NSColor.white,
    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
])!
gradient.draw(in: squircle, angle: -90)

// subtle hairline border
NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06).set()
squircle.lineWidth = 2
squircle.stroke()

// teal sparkles glyph, centered
let teal = NSColor(srgbRed: 0.12, green: 0.56, blue: 0.64, alpha: 1)
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
if let base = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let glyph = NSImage(size: base.size)
    glyph.lockFocus()
    teal.set()
    let gr = NSRect(origin: .zero, size: base.size)
    base.draw(in: gr)
    gr.fill(using: .sourceAtop)
    glyph.unlockFocus()
    let gx = (size - base.size.width) / 2
    let gy = (size - base.size.height) / 2
    glyph.draw(in: NSRect(x: gx, y: gy, width: base.size.width, height: base.size.height))
}

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(px)x\(px))")
```

- [ ] **Step 2: Render the master and verify it's 1024×1024**

```bash
swift scripts/generate-icon.swift /tmp/icon_1024.png
sips -g pixelWidth -g pixelHeight /tmp/icon_1024.png
```
Expected: `pixelWidth: 1024` and `pixelHeight: 1024`, and `/tmp/icon_1024.png` exists.

- [ ] **Step 3: Produce all 10 sizes into the appiconset**

```bash
ICONSET="MacScrub/Assets.xcassets/AppIcon.appiconset"
sips -z 16 16     /tmp/icon_1024.png --out "$ICONSET/AppIcon-16.png"
sips -z 32 32     /tmp/icon_1024.png --out "$ICONSET/AppIcon-16@2x.png"
sips -z 32 32     /tmp/icon_1024.png --out "$ICONSET/AppIcon-32.png"
sips -z 64 64     /tmp/icon_1024.png --out "$ICONSET/AppIcon-32@2x.png"
sips -z 128 128   /tmp/icon_1024.png --out "$ICONSET/AppIcon-128.png"
sips -z 256 256   /tmp/icon_1024.png --out "$ICONSET/AppIcon-128@2x.png"
sips -z 256 256   /tmp/icon_1024.png --out "$ICONSET/AppIcon-256.png"
sips -z 512 512   /tmp/icon_1024.png --out "$ICONSET/AppIcon-256@2x.png"
sips -z 512 512   /tmp/icon_1024.png --out "$ICONSET/AppIcon-512.png"
cp /tmp/icon_1024.png "$ICONSET/AppIcon-512@2x.png"
ls "$ICONSET"/*.png | wc -l
```
Expected: `10` PNG files in the appiconset. (`sips -z H W` resizes to height H, width W.)

- [ ] **Step 4: Replace `MacScrub/Assets.xcassets/AppIcon.appiconset/Contents.json`**

```json
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "AppIcon-16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "AppIcon-16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "AppIcon-32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "AppIcon-32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "AppIcon-128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "AppIcon-128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "AppIcon-256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "AppIcon-256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "AppIcon-512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "AppIcon-512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 5: Build and confirm the icon compiles in with no asset warnings**

```bash
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build 2>&1 | grep -iE "BUILD (SUCCEEDED|FAILED)|warning: .*(icon|AppIcon|unassigned)" | tail -10
ls build/Build/Products/Debug/MacScrub.app/Contents/Resources/Assets.car
```
Expected: `** BUILD SUCCEEDED **`, no AppIcon/unassigned-child warnings, and `Assets.car` exists (icons compiled into the bundle). Open the app in Finder to visually confirm the new icon (manual, also re-checked in Task 3).

- [ ] **Step 6: Commit** (no Co-Authored-By trailer)

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add scripts/generate-icon.swift MacScrub/Assets.xcassets/AppIcon.appiconset
git commit -m "feat: branded app icon (light squircle + teal sparkles)"
```

---

## Task 2: Proper installer DMG via create-dmg

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Validate the `create-dmg` command locally (best effort)**

This de-risks the CI change. If Homebrew isn't available, skip to Step 2 (CI is the real gate); otherwise:

```bash
brew install create-dmg
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
rm -f /tmp/MacScrub-test.dmg
create-dmg \
  --volname "MacScrub" \
  --window-size 560 360 \
  --icon-size 96 \
  --icon "MacScrub.app" 150 180 \
  --app-drop-link 410 180 \
  --no-internet-enable \
  /tmp/MacScrub-test.dmg \
  build/Build/Products/Release/MacScrub.app
# verify the produced DMG contains the app + an Applications symlink
MP=$(hdiutil attach /tmp/MacScrub-test.dmg -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
ls -la "$MP"
hdiutil detach "$MP" >/dev/null
```
Expected: `create-dmg` exits 0 and produces `/tmp/MacScrub-test.dmg`; the mounted volume lists `MacScrub.app` and an `Applications` symlink (→ `/Applications`). (Icon positions live in the volume's `.DS_Store`; the meaningful headless checks are the app + the Applications drop link.)

- [ ] **Step 2: Replace the "Create DMG" step in `.github/workflows/release.yml`**

The step currently is:
```yaml
      - name: Create DMG
        run: |
          DMG_NAME="MacScrub-${{ github.ref_name }}.dmg"
          hdiutil create -volname "MacScrub" \
            -srcfolder build/export/MacScrub.app \
            -ov -format UDZO \
            "$DMG_NAME"
```
Replace it with:
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
(The output name `MacScrub-<tag>.dmg` still matches the `files: "*.dmg"` glob in the "Create Release" step, which is unchanged.)

- [ ] **Step 3: Validate the workflow YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"
```
Expected: `yaml ok`.

- [ ] **Step 4: Commit** (no Co-Authored-By trailer)

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add .github/workflows/release.yml
git commit -m "ci: build a drag-to-Applications installer DMG via create-dmg"
```

---

## Task 3: Verification

**Files:** none.

- [ ] **Step 1: App icon — visual check**

```bash
rm -rf build
xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -quiet
open -R build/Build/Products/Debug/MacScrub.app
```
Confirm in Finder that `MacScrub.app` shows the new light squircle + teal sparkles icon (not the generic placeholder). If it still looks generic, the icon wiring is wrong — investigate `Assets.car`/`ASSETCATALOG_COMPILER_APPICON_NAME` before proceeding.

- [ ] **Step 2: Tests still green**

```bash
xcodebuild test -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS' 2>&1 | grep -E "Test run with|TEST (SUCCEEDED|FAILED)" | tail -2
```
Expected: `Test run with 49 tests in 10 suites passed`.

- [ ] **Step 3: DMG — verified at release time**

The styled DMG is produced only by the release workflow on a `v*` tag. After this branch merges and a release is tagged, download the produced `MacScrub-<tag>.dmg`, open it, and confirm: the MacScrub icon appears on the left, the Applications folder on the right, and the app can be dragged onto Applications. (No commit here.)

---

## Self-Review Notes

- **Spec coverage:** branded app icon (light squircle + teal sparkles), generated locally & committed → Task 1; picked up via the already-set `ASSETCATALOG_COMPILER_APPICON_NAME` (noted, no change needed); proper installer DMG with Applications drop link, minimal layout B (no background) via `create-dmg` → Task 2; icon + DMG verification → Task 3.
- **Consistency:** the 10 `Contents.json` filenames in Task 1 Step 4 exactly match the 10 PNGs produced in Step 3; the `create-dmg` command is identical in the local validation (Task 2 Step 1) and the committed workflow (Step 2), except the output path (`/tmp/...` vs `MacScrub-${GITHUB_REF_NAME}.dmg`).
- **No placeholders:** the icon script and the full `Contents.json` are complete; every command has expected output.
- **No source/test changes:** purely assets + workflow, so the 49 existing tests are unaffected.
