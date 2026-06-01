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
