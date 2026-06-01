# Notarization Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commit messages:** do NOT add any `Co-Authored-By` / Claude / AI attribution trailer (user preference).

**Goal:** Make the released DMG and the app inside it bulletproof under Gatekeeper: notarize + staple the app before packaging, and code-sign + notarize + staple the DMG container.

**Architecture:** Restructure the release workflow's notarization into two `notarytool` submissions — first the exported app (zip → submit → staple the `.app`, so the ticket travels with it offline), then the DMG (code-sign with Developer ID → submit → staple). All other steps (cert import, Developer ID archive/export, create-dmg, release) are unchanged. Workflow-only; no app/source/test changes.

**Tech Stack:** GitHub Actions (`macos-15`), `xcrun notarytool` + `stapler`, `ditto`, `codesign`, App Store Connect API key. Team `FA2WUDBFB8`.

---

## File Structure

- `.github/workflows/release.yml` — **modify**: add "Notarize and staple the app" (before Create DMG) and "Sign DMG" (after Create DMG, before the DMG notarization); the existing DMG notarize step is kept after signing.

**Notes**
- No unit tests — CI/packaging. Notarization is only fully exercised by a real tagged release; functional verification is Task 2 (release-time, guided). The 5 repo secrets are already configured (from the prior notarization work).
- Existing 49 unit tests are unaffected (no source/`project.yml` changes).
- Build-artifact hygiene: revert `MacScrub/Localization/Localizable.xcstrings` before staging if a build touched it; never stage `UserInterfaceState.xcuserstate`.

---

## Task 1: Staple the app + sign the DMG in the release workflow

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Replace the entire contents of `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

# Allow the workflow's GITHUB_TOKEN to create the GitHub Release + upload assets.
permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    env:
      TEAM_ID: FA2WUDBFB8
    steps:
      - uses: actions/checkout@v4

      # XcodeGen emits an objectVersion-77 project (Xcode 16.3+); select the
      # newest stable Xcode so xcodebuild can read it.
      - name: Select Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Install tools
        run: brew install xcodegen create-dmg

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Import Developer ID certificate
        env:
          CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }}
          CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
        run: |
          CERT_PATH="$RUNNER_TEMP/developer_id.p12"
          KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
          KEYCHAIN_PASSWORD="$(uuidgen)"
          echo "$CERT_P12_BASE64" | openssl base64 -d -A > "$CERT_PATH"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security import "$CERT_PATH" -P "$CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security list-keychain -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | sed s/\"//g)
          security find-identity -v -p codesigning

      - name: Create ExportOptions.plist
        run: |
          cat > ExportOptions.plist << EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>method</key>
              <string>developer-id</string>
              <key>teamID</key>
              <string>${TEAM_ID}</string>
              <key>signingStyle</key>
              <string>manual</string>
          </dict>
          </plist>
          EOF

      - name: Build Archive
        run: |
          xcodebuild archive \
            -project MacScrub.xcodeproj \
            -scheme MacScrub \
            -archivePath build/MacScrub.xcarchive \
            MARKETING_VERSION="${GITHUB_REF_NAME#v}" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="${TEAM_ID}" \
            ENABLE_HARDENED_RUNTIME=YES \
            OTHER_CODE_SIGN_FLAGS="--timestamp"

      - name: Export App
        run: |
          xcodebuild -exportArchive \
            -archivePath build/MacScrub.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist

      - name: Notarize and staple the app
        env:
          API_KEY_P8_BASE64: ${{ secrets.AC_API_KEY_P8_BASE64 }}
          API_KEY_ID: ${{ secrets.AC_API_KEY_ID }}
          API_ISSUER_ID: ${{ secrets.AC_API_ISSUER_ID }}
        run: |
          KEY_PATH="$RUNNER_TEMP/ac_api_key.p8"
          echo "$API_KEY_P8_BASE64" | openssl base64 -d -A > "$KEY_PATH"
          ditto -c -k --keepParent "build/export/MacScrub.app" "$RUNNER_TEMP/MacScrub.zip"
          xcrun notarytool submit "$RUNNER_TEMP/MacScrub.zip" \
            --key "$KEY_PATH" \
            --key-id "$API_KEY_ID" \
            --issuer "$API_ISSUER_ID" \
            --wait
          xcrun stapler staple "build/export/MacScrub.app"

      - name: Create DMG
        run: |
          create-dmg \
            --volname "MacScrub" \
            --window-size 560 360 \
            --icon-size 96 \
            --icon "MacScrub.app" 150 180 \
            --app-drop-link 410 180 \
            --no-internet-enable \
            "MacScrub-${GITHUB_REF_NAME}.dmg" \
            "build/export/MacScrub.app"

      - name: Sign DMG
        run: |
          codesign --force --timestamp \
            --sign "Developer ID Application" \
            "MacScrub-${GITHUB_REF_NAME}.dmg"
          codesign -dvv "MacScrub-${GITHUB_REF_NAME}.dmg" 2>&1 | grep -i "Authority=Developer ID" || true

      - name: Notarize and staple the DMG
        env:
          API_KEY_ID: ${{ secrets.AC_API_KEY_ID }}
          API_ISSUER_ID: ${{ secrets.AC_API_ISSUER_ID }}
        run: |
          KEY_PATH="$RUNNER_TEMP/ac_api_key.p8"
          DMG="MacScrub-${GITHUB_REF_NAME}.dmg"
          xcrun notarytool submit "$DMG" \
            --key "$KEY_PATH" \
            --key-id "$API_KEY_ID" \
            --issuer "$API_ISSUER_ID" \
            --wait
          xcrun stapler staple "$DMG"
          xcrun stapler validate "$DMG"
          spctl -a -t open --context context:primary-signature -vv "$DMG" || true

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: "*.dmg"
          generate_release_notes: true
```

Changes vs. the previous workflow:
- New **"Notarize and staple the app"** step (after Export App, before Create DMG): decodes the API key `.p8` to `$RUNNER_TEMP/ac_api_key.p8` (reused later), zips the exported app with `ditto`, submits it to `notarytool --wait`, then `stapler staple`s the `.app` so the ticket is embedded in the app before it's packaged.
- New **"Sign DMG"** step (after Create DMG): `codesign`s the DMG with the Developer ID identity already in the keychain, with `--timestamp`.
- The existing DMG notarization step is renamed **"Notarize and staple the DMG"** and now reuses the already-decoded `$RUNNER_TEMP/ac_api_key.p8` (so it only needs the Key ID + Issuer ID env). It still runs after the DMG is signed, so the final signed artifact is what gets notarized + stapled.
- All other steps are byte-for-byte unchanged.

- [ ] **Step 2: Validate the workflow YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')" || (pip3 install pyyaml -q && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')")
```
Expected: `yaml ok`.

- [ ] **Step 3: Confirm step order (app-notarize before Create DMG; Sign DMG before DMG-notarize)**

```bash
grep -n "name: " .github/workflows/release.yml
```
Expected: the step names appear in this order — `Notarize and staple the app`, then `Create DMG`, then `Sign DMG`, then `Notarize and staple the DMG`, then `Create Release`.

- [ ] **Step 4: Commit** (no Co-Authored-By trailer)

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add .github/workflows/release.yml
git commit -m "ci: staple the app and sign the DMG (bulletproof notarization)"
```

---

## Task 2: Release-time verification

Runs on the next tagged release (the 5 secrets are already configured). Verifies both
the DMG container and the contained app are bulletproof.

**Files:** none.

- [ ] **Step 1: Cut a release and watch the run**

Tag and push (e.g. `git tag -a v1.4.0 -m "bulletproof notarization" && git push origin v1.4.0`), then:
```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id> --exit-status
```
Expected: all steps succeed, including "Notarize and staple the app", "Sign DMG", and
"Notarize and staple the DMG" (both `notarytool` submissions return Accepted). If a
step fails, fetch details (`gh run view <id> --log-failed`; `xcrun notarytool log
<submission-id> --key … --key-id … --issuer …` for a notarization failure) and iterate.

- [ ] **Step 2: Verify the published DMG and the app inside**

```bash
gh release download <tag> -R tufantunc/MacScrub -p "*.dmg"
DMG="MacScrub-<tag>.dmg"
# DMG container: now signed + notarized + stapled
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
# App inside: now carries its own stapled ticket
MP=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
xcrun stapler validate "$MP/MacScrub.app"
spctl -a -t exec -vv "$MP/MacScrub.app"
hdiutil detach "$MP"
```
Expected:
- `stapler validate "$DMG"` → "The validate action worked!".
- `spctl -a -t open … "$DMG"` → `accepted` / `source=Notarized Developer ID` (previously "rejected: no usable signature").
- `stapler validate "$MP/MacScrub.app"` → reports a valid stapled ticket (previously "does not have a ticket stapled").
- `spctl -a -t exec … "$MP/MacScrub.app"` → `accepted` / `source=Notarized Developer ID`.

- [ ] **Step 3: Real-world confirmation**

Download the DMG via a browser, open it, drag MacScrub to /Applications, and launch —
including with networking off after copying — to confirm no Gatekeeper warning. (No
commit here.)

---

## Self-Review Notes

- **Spec coverage:** staple the app before DMG (ditto → notarytool → stapler staple .app) → Task 1 "Notarize and staple the app"; code-sign the DMG → Task 1 "Sign DMG"; notarize + staple the signed DMG → Task 1 "Notarize and staple the DMG"; reuse the decoded API key across both submissions → the app step decodes to `$RUNNER_TEMP/ac_api_key.p8` and the DMG step reuses it; verification (DMG spctl-open accepted + app has stapled ticket) → Task 2.
- **Consistency:** the API key file path `$RUNNER_TEMP/ac_api_key.p8` is written in the app step and read in the DMG step; `MacScrub-${GITHUB_REF_NAME}.dmg` is identical across Create DMG / Sign DMG / Notarize DMG and matches the `files: "*.dmg"` glob; the Developer ID identity `"Developer ID Application"` used to sign the DMG is the same one imported for the archive.
- **Ordering:** Sign DMG is between Create DMG and the DMG notarization, so the notarized artifact is the final signed one. The app is stapled before Create DMG, so the packaged app carries the ticket.
- **No placeholders:** full workflow provided; every command has expected output.
