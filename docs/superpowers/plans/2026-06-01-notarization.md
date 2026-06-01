# Developer ID Signing + Notarization Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commit messages:** do NOT add any `Co-Authored-By` / Claude / AI attribution trailer (user preference).

**Goal:** Make the released DMG open with no Gatekeeper warning by signing the app with the DENEBOX Developer ID Application certificate (hardened runtime + secure timestamp) and notarizing + stapling the DMG in the release CI.

**Architecture:** The release workflow imports the Developer ID cert into a temporary keychain, archives + exports the app with Developer ID signing, builds the DMG (unchanged), then notarizes the DMG with `notarytool` (App Store Connect API key) and staples the ticket. A committed `docs/NOTARIZATION_SETUP.md` guides the one-time maintainer credential setup. No app source changes.

**Tech Stack:** GitHub Actions (`macos-15`), `xcodebuild` archive/export (Developer ID), `security` keychain, `xcrun notarytool` + `stapler`, App Store Connect API key. Team `FA2WUDBFB8`.

---

## File Structure

- `docs/NOTARIZATION_SETUP.md` — **create**: the maintainer's one-time setup guide (certificate, API key, the 5 GitHub secrets).
- `.github/workflows/release.yml` — **modify**: add cert import + notarize/staple steps; switch archive + export to Developer ID.

**Notes**
- No unit tests — this is CI/packaging. Notarization is only fully exercised by a real tagged release (after the maintainer adds the secrets), so the functional verification is Task 3 (post-merge, guided).
- Existing 49 tests are unaffected (no source/`project.yml` changes; local signing stays Apple Development).
- Build-artifact hygiene: revert `MacScrub/Localization/Localizable.xcstrings` before staging if a build touched it; never stage `UserInterfaceState.xcuserstate`.

---

## Task 1: Maintainer setup guide

**Files:**
- Create: `docs/NOTARIZATION_SETUP.md`

- [ ] **Step 1: Create `docs/NOTARIZATION_SETUP.md` with exactly this content**

````markdown
# Notarization Setup (one-time, maintainer)

The release workflow signs MacScrub with the **DENEBOX** Developer ID Application
certificate and notarizes the DMG with Apple. To enable it, create the credentials
below once and add them as GitHub Actions secrets. Apple Developer Program
membership is required (DENEBOX, team `FA2WUDBFB8`).

## A. Developer ID Application certificate

In an **organization** account, only the **Account Holder** can create a Developer ID
certificate. If you are not the Account Holder, ask them to do step A (or to grant the
role), then continue.

1. Xcode → **Settings → Accounts** → select the **DENEBOX** team → **Manage
   Certificates…** → click **+** → **Developer ID Application**. The certificate and
   its private key are added to your login keychain.
2. Open **Keychain Access**, find **"Developer ID Application: DENEBOX … (FA2WUDBFB8)"**,
   right-click → **Export "Developer ID Application: …"** → save as `DeveloperID.p12`
   and set an export password.
3. Base64-encode it for the secret:
   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```
   - `DEVELOPER_ID_CERT_P12_BASE64` = the copied base64 string.
   - `DEVELOPER_ID_CERT_PASSWORD` = the export password you set in step 2.

## B. App Store Connect API key (for notarization)

1. Go to **App Store Connect → Users and Access → Integrations → App Store Connect
   API** (Keys). Click **+** to generate a key; role **Developer** is sufficient for
   the notary service.
2. **Download the `.p8` file now** — it can only be downloaded once. Note the **Key
   ID** (next to the key) and the **Issuer ID** (shown at the top of the Keys page).
3. Base64-encode it:
   ```bash
   base64 -i AuthKey_<KeyID>.p8 | pbcopy
   ```
   - `AC_API_KEY_P8_BASE64` = the copied base64 string.
   - `AC_API_KEY_ID` = the Key ID.
   - `AC_API_ISSUER_ID` = the Issuer ID.

## C. Add the secrets to GitHub

Repo → **Settings → Secrets and variables → Actions → New repository secret**, and add
all five:

| Secret | Value |
|--------|-------|
| `DEVELOPER_ID_CERT_P12_BASE64` | from A.3 |
| `DEVELOPER_ID_CERT_PASSWORD` | from A.2 |
| `AC_API_KEY_P8_BASE64` | from B.3 |
| `AC_API_KEY_ID` | from B.2 |
| `AC_API_ISSUER_ID` | from B.2 |

The team ID `FA2WUDBFB8` is not secret and is hardcoded in the workflow.

## D. Cut a release

Push a `v*` tag (e.g. `git tag -a v1.3.0 -m "…" && git push origin v1.3.0`). The
release workflow signs, notarizes, staples, and uploads `MacScrub-<tag>.dmg`. Verify
with:
```bash
xcrun stapler validate MacScrub-<tag>.dmg
spctl -a -t open --context context:primary-signature -vv MacScrub-<tag>.dmg
```
The first reports success; the second reports `accepted` / `source=Notarized Developer
ID`. Opening the downloaded DMG and launching the app should show no Gatekeeper
warning.
````

- [ ] **Step 2: Commit** (no Co-Authored-By trailer)

```bash
git add docs/NOTARIZATION_SETUP.md
git commit -m "docs: notarization setup guide (Developer ID cert + API key + secrets)"
```

---

## Task 2: Developer ID signing + notarization in the release workflow

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

      - name: Notarize and staple
        env:
          API_KEY_P8_BASE64: ${{ secrets.AC_API_KEY_P8_BASE64 }}
          API_KEY_ID: ${{ secrets.AC_API_KEY_ID }}
          API_ISSUER_ID: ${{ secrets.AC_API_ISSUER_ID }}
        run: |
          KEY_PATH="$RUNNER_TEMP/ac_api_key.p8"
          echo "$API_KEY_P8_BASE64" | openssl base64 -d -A > "$KEY_PATH"
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

Notes on the changes vs. the previous workflow:
- `brew install xcodegen create-dmg` is consolidated into one "Install tools" step (create-dmg was previously installed inside the DMG step; same effect).
- New "Import Developer ID certificate" step builds a temporary keychain from the `.p12` secret and adds it to the user search list so `codesign`/`xcodebuild` can use it.
- "Build Archive" now signs with `Developer ID Application` (manual), hardened runtime, and `--timestamp` (previously ad-hoc / no signing).
- "Create ExportOptions.plist" now uses `method: developer-id` + `teamID` + manual style (previously `mac-application` / `adhoc`).
- New "Notarize and staple" step submits the DMG to Apple with the API key and staples the ticket. `--wait` fails the job on an `Invalid` result.
- "Create Release" is unchanged; the stapled `MacScrub-<tag>.dmg` is uploaded.

- [ ] **Step 2: Validate the workflow YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"
```
Expected: `yaml ok`. (If `pyyaml` is missing, `pip3 install pyyaml` first.)

- [ ] **Step 3: Sanity-check the embedded ExportOptions heredoc renders the team id**

```bash
TEAM_ID=FA2WUDBFB8
sed -n '/Create ExportOptions.plist/,/EOF/p' .github/workflows/release.yml | grep -A1 "<key>teamID</key>"
```
Expected: shows the `teamID` key followed by `<string>${TEAM_ID}</string>` (the workflow substitutes `FA2WUDBFB8` at run time because the heredoc is unquoted `<< EOF`).

- [ ] **Step 4: Commit** (no Co-Authored-By trailer)

```bash
git checkout -- MacScrub/Localization/Localizable.xcstrings 2>/dev/null || true
git add .github/workflows/release.yml
git commit -m "ci: sign with Developer ID + notarize and staple the release DMG"
```

---

## Task 3: Release-time verification (after maintainer adds secrets)

This cannot run until the maintainer has completed `docs/NOTARIZATION_SETUP.md` (cert,
API key, 5 secrets). It is performed once, on the first notarized release.

**Files:** none.

- [ ] **Step 1: Confirm the 5 secrets exist**

The maintainer follows `docs/NOTARIZATION_SETUP.md` and confirms these repository
secrets are set: `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`,
`AC_API_KEY_P8_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`.

- [ ] **Step 2: Cut a release and watch the run**

Tag and push (e.g. `git tag -a v1.3.0 -m "notarized release" && git push origin v1.3.0`),
then watch:
```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id> --exit-status
```
Expected: all steps succeed, including "Import Developer ID certificate", "Build
Archive" (Developer ID), "Notarize and staple" (notarytool returns Accepted), and
"Create Release". If a step fails, fetch details (`gh run view <id> --log-failed`, or
`xcrun notarytool log <submission-id> …` for notarization) and iterate.

- [ ] **Step 3: Verify the published DMG opens cleanly**

```bash
gh release download <tag> -R tufantunc/MacScrub -p "*.dmg"
xcrun stapler validate MacScrub-<tag>.dmg
spctl -a -t open --context context:primary-signature -vv MacScrub-<tag>.dmg
```
Expected: stapler validate succeeds; spctl reports `accepted` / `source=Notarized
Developer ID`. Open the DMG and launch the app — no Gatekeeper malware warning.

---

## Self-Review Notes

- **Spec coverage:** Developer ID signing + hardened runtime + timestamp → Task 2 (Build Archive); developer-id export → Task 2 (ExportOptions); cert import to temp keychain → Task 2 (Import step); notarize + staple the DMG via API key → Task 2 (Notarize step); 5 secrets + manual setup guide → Task 1 + the env wiring in Task 2; release-time verification → Task 3.
- **Consistency:** the 5 secret names (`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `AC_API_KEY_P8_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`) and `TEAM_ID=FA2WUDBFB8` are identical across the guide (Task 1) and the workflow (Task 2). The DMG name `MacScrub-${GITHUB_REF_NAME}.dmg` is used identically in Create DMG and Notarize steps and matches the `files: "*.dmg"` upload glob.
- **No placeholders:** full guide text and full workflow are provided; every command has expected output.
- **Risk (documented):** if `exportArchive` with `developer-id`/manual proves finicky on the runner, the fallback is to sign the exported `.app` directly with `codesign --force --options runtime --timestamp --sign "Developer ID Application: … (FA2WUDBFB8)"`; not adopted up front to keep the archive→export flow already in place. This is exercised/decided at Task 3 if needed.
