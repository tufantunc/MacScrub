# Homebrew Cask Distribution — Design

**Date:** 2026-06-02
**Status:** Approved

## Background

MacScrub ships a Developer-ID-signed, notarized DMG via GitHub Releases
(`MacScrub-vX.Y.Z.dmg`), one per `v*` tag. Many macOS users prefer
`brew install --cask`. This adds a Homebrew cask so users can install (and update)
MacScrub with one command, and keeps the cask in sync automatically on every release.

The maintainer already has a personal tap repo, **`tufantunc/homebrew-tap`** (public,
default branch `main`), currently containing `Formula/hi-shell.rb` and a minimal
README. A Homebrew tap may hold both `Formula/` and `Casks/` in the same repo.

## Goals

- Users install with `brew install --cask tufantunc/tap/macscrub` (auto-taps).
- Each MacScrub release automatically updates the cask's `version` + `sha256` in the
  tap, with no manual step beyond a one-time token.

## Non-Goals

- No submission to the official `homebrew-cask` (deferred until the project gains the
  notability Homebrew requires).
- No CI/tests added to the tap repo (Homebrew validates casks).
- No change to MacScrub's app/source or the existing `Formula/hi-shell.rb`.

## Decisions (confirmed with user)

| Topic | Decision |
|-------|----------|
| Location | Personal tap `tufantunc/homebrew-tap`, new `Casks/macscrub.rb` (repo already exists) |
| Updates | Automated from the MacScrub release CI (push updated cask to the tap) |
| Cross-repo auth | A fine-grained PAT `HOMEBREW_TAP_TOKEN` (Contents: read+write on the tap repo), added by the maintainer |
| macOS floor | `>= :sonoma` (matches the app's macOS 14 deployment target) |

## Architecture

### The cask — `tufantunc/homebrew-tap` → `Casks/macscrub.rb`

Seeded with the current release (v1.4.0) so it works immediately:

```ruby
cask "macscrub" do
  version "1.4.0"
  sha256 "c688e8bdb9f69246a9e7f9d12447147daca4ff9caae8e21c5a7ecefcaf53a7b4"

  url "https://github.com/tufantunc/MacScrub/releases/download/v#{version}/MacScrub-v#{version}.dmg"
  name "MacScrub"
  desc "Temporary input lock for safely cleaning your Mac keyboard and trackpad"
  homepage "https://github.com/tufantunc/MacScrub"

  depends_on macos: ">= :sonoma"

  app "MacScrub.app"

  zap trash: [
    "~/Library/Preferences/com.macscrub.app.plist",
  ]
end
```

- `url` uses Ruby `#{version}` interpolation against the `version` stanza, so the
  download path always matches the tag (`v1.4.0/MacScrub-v1.4.0.dmg`).
- `zap` removes the app's `UserDefaults` plist on `brew uninstall --zap`.
- The cask must pass `brew audit --cask` / `brew style` (no leading article / trailing
  period in `desc`, etc.).

### CI automation — new step in MacScrub `.github/workflows/release.yml`

After "Create Release", a **"Update Homebrew tap"** step:

```yaml
      - name: Update Homebrew tap
        env:
          TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          DMG="MacScrub-${GITHUB_REF_NAME}.dmg"
          SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
          git clone "https://x-access-token:${TAP_TOKEN}@github.com/tufantunc/homebrew-tap.git" tap
          mkdir -p tap/Casks
          cat > tap/Casks/macscrub.rb << EOF
          cask "macscrub" do
            version "${VERSION}"
            sha256 "${SHA}"

            url "https://github.com/tufantunc/MacScrub/releases/download/v#{version}/MacScrub-v#{version}.dmg"
            name "MacScrub"
            desc "Temporary input lock for safely cleaning your Mac keyboard and trackpad"
            homepage "https://github.com/tufantunc/MacScrub"

            depends_on macos: ">= :sonoma"

            app "MacScrub.app"

            zap trash: [
              "~/Library/Preferences/com.macscrub.app.plist",
            ]
          end
          EOF
          cd tap
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Casks/macscrub.rb
          git commit -m "macscrub ${VERSION}" || echo "no change"
          git push
```

- The heredoc is **unquoted** (`<< EOF`), so the shell expands `${VERSION}` and
  `${SHA}` (baked per release) while Ruby's `#{version}` is left literal (`#{` is not
  shell syntax) — exactly what's wanted.
- `git commit … || echo "no change"` tolerates a re-run that produces no diff.
- `GITHUB_TOKEN` cannot push to another repo, hence the dedicated `HOMEBREW_TAP_TOKEN`.

### README — MacScrub install section

Add a Homebrew option at the top of "## Installation":

```
### Homebrew

    brew install --cask tufantunc/tap/macscrub
```

(Keep the existing DMG download instructions below it.)

## Manual setup (maintainer, one-time)

1. Create a **fine-grained Personal Access Token** scoped to **only**
   `tufantunc/homebrew-tap`, with **Repository permissions → Contents: Read and
   write**.
2. Add it to the **MacScrub** repo as the secret **`HOMEBREW_TAP_TOKEN`** (Settings →
   Secrets and variables → Actions).

The initial `Casks/macscrub.rb` (v1.4.0) is committed to the tap during
implementation, so `brew install` works even before the next release.

## Verification

- **Cask quality:** `brew audit --cask Casks/macscrub.rb` and `brew style
  Casks/macscrub.rb` pass (run locally; Homebrew is installed on the dev machine).
- **Install (local, careful):** `brew install --cask tufantunc/tap/macscrub` installs
  `MacScrub.app`; since `/Applications/MacScrub.app` may already exist from manual
  installation, test with `--force` or after removing the manual copy, and
  `brew uninstall --cask macscrub` to confirm clean removal.
- **CI automation:** verified on the next tagged release — confirm the
  "Update Homebrew tap" step pushes an updated `Casks/macscrub.rb` (new `version` +
  `sha256`) to the tap, then `brew update && brew upgrade --cask macscrub` picks it up.
- MacScrub's 49 unit tests are unaffected (no app/source changes).

## Risks / Notes

- Two repos are involved: the cask lives in `tufantunc/homebrew-tap`; only the CI
  step + README + this spec live in the MacScrub repo.
- If `HOMEBREW_TAP_TOKEN` is missing/expired, the "Update Homebrew tap" step fails the
  release job (loud, not silent) — acceptable; the DMG + GitHub Release still publish
  before this step. (The step is last, after "Create Release".)
- `version :latest` / `sha256 :no_check` are intentionally avoided; pinned
  version + sha is the correct, auditable form and is what the CI keeps current.
