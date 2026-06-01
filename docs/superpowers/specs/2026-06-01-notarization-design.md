# Developer ID Signing + Notarization Pipeline — Design

**Date:** 2026-06-01
**Status:** Approved

## Background

The released DMG is built ad-hoc signed (`CODE_SIGNING_ALLOWED=NO`) and is not
notarized, so macOS Sequoia's Gatekeeper blocks first launch with "Apple could not
verify 'MacScrub' is free of malware…". To distribute the app so it opens with no
warning, the release must be signed with a **Developer ID Application** certificate
(hardened runtime + secure timestamp) and **notarized** by Apple, with the
notarization ticket stapled to the DMG.

The app is published under the **DENEBOX** organization Apple Developer account
(team `FA2WUDBFB8`).

## Goals

- The released `MacScrub-<tag>.dmg` opens with **no Gatekeeper warning** on a clean Mac.
- Signing + notarization happen entirely in the release CI (GitHub Actions) on a
  `v*` tag, using secrets — no manual signing per release.
- Provide a clear manual-setup guide for the one-time credential steps the maintainer
  must perform (certificate + API key + secrets).

## Non-Goals

- No Mac App Store distribution (this is Developer ID / direct distribution).
- No change to local development signing (`project.yml` keeps the Apple Development
  identity for TCC stability); only CI uses Developer ID.
- No separate codesigning of the `.dmg` container (notarize + staple the DMG is
  sufficient; the `.app` inside is Developer-ID-signed).
- No app entitlements changes (the CGEvent tap relies on the Accessibility TCC grant,
  which hardened runtime does not restrict).

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Publisher | DENEBOX organization (team `FA2WUDBFB8`) |
| Notarization credentials | App Store Connect **API key** (`.p8` + Key ID + Issuer ID) |
| What gets notarized/stapled | The **DMG** (containing the Developer-ID-signed app) |
| Local signing | Unchanged (Apple Development); CI overrides to Developer ID |

## Architecture (release workflow changes)

The `.github/workflows/release.yml` job gains/changes these steps, in order:

1. **Import signing certificate (new).** Decode `DEVELOPER_ID_CERT_P12_BASE64` to a
   file, create a temporary keychain with a generated password, import the `.p12`
   (using `DEVELOPER_ID_CERT_PASSWORD`), run `security set-key-partition-list` so
   `codesign` can use the key non-interactively, and add the keychain to the search
   list / unlock it.

2. **Build Archive (changed).** Replace the ad-hoc flags with Developer ID signing:
   `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="Developer ID Application"`,
   `DEVELOPMENT_TEAM=FA2WUDBFB8`, `ENABLE_HARDENED_RUNTIME=YES`,
   `OTHER_CODE_SIGN_FLAGS="--timestamp"` (keep `MARKETING_VERSION="${GITHUB_REF_NAME#v}"`).

3. **ExportOptions.plist (changed).** `method: developer-id`, `teamID: FA2WUDBFB8`,
   `signingStyle: manual`. (Was `mac-application` / `adhoc`.) The export produces the
   Developer-ID-signed, hardened, timestamped `build/export/MacScrub.app`.

4. **Create DMG (unchanged).** `create-dmg` packages the signed app into
   `MacScrub-${GITHUB_REF_NAME}.dmg` (icon left, Applications right).

5. **Notarize + staple (new).** Decode `AC_API_KEY_P8_BASE64` to `key.p8`, then:
   ```
   xcrun notarytool submit "MacScrub-${GITHUB_REF_NAME}.dmg" \
     --key key.p8 --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" --wait
   xcrun stapler staple "MacScrub-${GITHUB_REF_NAME}.dmg"
   ```
   `--wait` blocks until Apple returns Accepted/Invalid; an Invalid result fails the
   job (and the notarytool log is fetched for diagnosis).

6. **Create Release (unchanged).** Uploads the now-stapled `*.dmg`.

### Secrets (configured once by the maintainer)

| Secret | Contents |
|--------|----------|
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of the exported Developer ID Application `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `AC_API_KEY_P8_BASE64` | base64 of the App Store Connect API key `.p8` |
| `AC_API_KEY_ID` | the API key's Key ID |
| `AC_API_ISSUER_ID` | the API key's Issuer ID |

Team ID `FA2WUDBFB8` is not secret and is hardcoded in the workflow. The temporary
keychain password is generated within the job (no secret needed) and the keychain is
deleted at the end.

## Manual setup guide (committed as `docs/NOTARIZATION_SETUP.md`)

A step-by-step doc the maintainer follows once:

**A. Developer ID Application certificate**
- In the DENEBOX org account this can only be created by the **Account Holder**. (If
  you are not the Account Holder, request it from them.)
- Xcode → Settings → Accounts → DENEBOX team → Manage Certificates → `+` → "Developer
  ID Application". The private key lands in your login keychain.
- Keychain Access → find "Developer ID Application: DENEBOX… (FA2WUDBFB8)" → right-click
  → Export → save as `.p12` with a password.
- `base64 -i DeveloperID.p12 | pbcopy` → `DEVELOPER_ID_CERT_P12_BASE64`; the password →
  `DEVELOPER_ID_CERT_PASSWORD`.

**B. App Store Connect API key**
- App Store Connect → Users and Access → Integrations → App Store Connect API →
  generate a key (role **Developer** is sufficient for the notary service). **Download
  the `.p8` once** (it can't be re-downloaded). Note the **Key ID** and the page's
  **Issuer ID**.
- `base64 -i AuthKey_<KeyID>.p8 | pbcopy` → `AC_API_KEY_P8_BASE64`; Key ID →
  `AC_API_KEY_ID`; Issuer ID → `AC_API_ISSUER_ID`.

**C. Add the 5 secrets** under GitHub → repo → Settings → Secrets and variables →
Actions → New repository secret.

## Verification

Notarization can only be exercised by a real tagged release run. After a release:
- Download the produced `MacScrub-<tag>.dmg` and confirm:
  - `xcrun stapler validate MacScrub-<tag>.dmg` → "The validate action worked".
  - `spctl -a -t open --context context:primary-signature -vv MacScrub-<tag>.dmg`
    reports `accepted` / `source=Notarized Developer ID`.
  - Mounting the DMG and launching the app shows **no Gatekeeper warning**.
- If notarytool returns Invalid, fetch the log
  (`xcrun notarytool log <submission-id> --key …`) and iterate (mirrors how the v1.0.0
  pipeline was stabilized).
- The existing 49 unit tests are unaffected (no source changes).

## Risks / Notes

- The first release run depends on the maintainer's correct certificate/key/secrets
  setup; we watch it with `gh` and iterate on any signing/notarization error.
- Hardened runtime does not affect the Accessibility (TCC) event-tap permission, so no
  entitlement exceptions are needed. If a future capability requires one, an
  entitlements file would be added then.
- notarization adds a few minutes to the release (Apple's notary queue) due to
  `--wait`; acceptable for tagged releases.
