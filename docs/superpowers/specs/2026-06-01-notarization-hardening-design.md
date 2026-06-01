# Notarization Hardening (staple app + sign DMG) — Design

**Date:** 2026-06-01
**Status:** Approved

## Background

The v1.3.0 release pipeline (signed Developer ID, notarized + stapled **DMG**) made
the app launch as "Notarized Developer ID — accepted", resolving the Gatekeeper
malware warning. Verification surfaced two robustness gaps:

1. The DMG container itself is **not code-signed**, so `spctl -a -t open …` reports
   "no usable signature" for the DMG (the stapled notarization ticket is present, but
   the container has no Developer ID signature).
2. The **app is not individually stapled** — the ticket is on the DMG, not the app
   (`stapler validate MacScrub.app` → "does not have a ticket stapled"). Once the app
   is copied to /Applications, an **offline** first launch can't reach Apple's notary
   service and has no local ticket.

This hardens the pipeline so both the DMG and the contained app are bulletproof.

## Goals

- The released DMG passes `spctl -a -t open` (Developer-ID-signed + notarized +
  stapled container).
- The app inside the DMG carries its **own stapled** notarization ticket, so it opens
  cleanly even offline after being copied to /Applications.

## Non-Goals

- No app source / `project.yml` / local-signing changes (local dev stays Apple
  Development). Workflow-only change.
- No Mac App Store path; still Developer ID / direct distribution.
- No new entitlements (hardened runtime already in place; the Accessibility event tap
  is unaffected).

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Scope | Staple the app (before DMG) **and** code-sign + notarize + staple the DMG |
| Cost | A second `notarytool` submission per release (app, then DMG) — accepted |
| Change surface | `.github/workflows/release.yml` only |

## Architecture (release workflow flow)

The certificate import, Developer ID archive, `developer-id` export, and
`create-dmg` steps are unchanged. The notarization is restructured into two
submissions, and the DMG is signed. New order after **Export App** (which produces
the Developer-ID-signed, hardened, timestamped `build/export/MacScrub.app`):

1. **Notarize + staple the app (new — must precede DMG creation).**
   - `ditto -c -k --keepParent build/export/MacScrub.app "$RUNNER_TEMP/MacScrub.zip"`
     (notarytool needs a zip/pkg/dmg, not a bare `.app`).
   - `xcrun notarytool submit "$RUNNER_TEMP/MacScrub.zip" --key key.p8 --key-id … --issuer … --wait`
     (notarizes the app's cdhash; `--wait` fails the job on Invalid).
   - `xcrun stapler staple build/export/MacScrub.app` (the ticket now exists, so it
     staples onto the app — and travels with it when copied out).

2. **Create DMG (unchanged).** `create-dmg` packages the now-stapled app, so the app
   inside the DMG is stapled.

3. **Code-sign the DMG (new).**
   - `codesign --force --timestamp --sign "Developer ID Application" "MacScrub-${GITHUB_REF_NAME}.dmg"`
     — signs the container with the Developer ID identity already in the temporary
     keychain (so `spctl -a -t open` will pass once notarized).

4. **Notarize + staple the DMG (existing step, kept after signing).**
   - `xcrun notarytool submit "MacScrub-${GITHUB_REF_NAME}.dmg" --key key.p8 … --wait`
   - `xcrun stapler staple "MacScrub-${GITHUB_REF_NAME}.dmg"`
   - `xcrun stapler validate "MacScrub-${GITHUB_REF_NAME}.dmg"`
   - `spctl -a -t open --context context:primary-signature -vv "…dmg" || true` (informational)

5. **Create Release (unchanged).** Uploads the signed/notarized/stapled DMG.

The App Store Connect API key `.p8` is decoded once and reused for both `notarytool
submit` calls. The Developer ID identity used to `codesign` the DMG is the same one
imported for the archive (already in the keychain + search list).

## Verification (at the next tagged release)

- `xcrun stapler validate MacScrub-<tag>.dmg` → success.
- `spctl -a -t open --context context:primary-signature -vv MacScrub-<tag>.dmg` →
  `accepted` / `source=Notarized Developer ID` (was "rejected: no usable signature").
- Mount the DMG and run `xcrun stapler validate "/Volumes/MacScrub/MacScrub.app"` →
  reports a valid stapled ticket (was "does not have a ticket stapled").
- Real-world: download via browser, open, drag to /Applications, launch (incl.
  offline) → no Gatekeeper warning.
- Existing 49 unit tests unaffected (no source changes).

## Risks / Notes

- Two notarizations add a few minutes (Apple's notary queue) per release — acceptable
  for tagged releases.
- `codesign` of the DMG must run after `create-dmg` and before the DMG notarization
  submission (signing changes the DMG's hash; notarize the final signed artifact).
- If `notarytool` returns Invalid for either submission, fetch the log
  (`xcrun notarytool log <id> …`) and iterate, as with prior pipeline work.
