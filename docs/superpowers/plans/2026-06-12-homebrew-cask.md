# Homebrew Cask Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users install MacScrub with `brew install --cask tufantunc/tap/macscrub`, kept up to date automatically by the release CI.

**Architecture:** A pinned-version cask (`Casks/macscrub.rb`) lives in the existing external tap repo `tufantunc/homebrew-tap`. The MacScrub release workflow gains a final "Update Homebrew tap" step that regenerates the cask with the new version + sha256 and pushes it to the tap using a fine-grained PAT (`HOMEBREW_TAP_TOKEN`). The README gains a Homebrew install section.

**Tech Stack:** Homebrew cask DSL (Ruby), GitHub Actions (bash), `gh` CLI for the external repo, fine-grained PAT for cross-repo push.

**Spec:** `docs/superpowers/specs/2026-06-02-homebrew-cask-design.md`

**Important conventions for all tasks:**
- Commit messages: plain English, conventional-commit style. **NEVER add any `Co-Authored-By` / "Generated with Claude" trailer.**
- Two repos are involved. Tasks 2–3 commit to the local MacScrub repo (branch `feature/homebrew-cask`). Task 1 pushes directly to `main` of `github.com/tufantunc/homebrew-tap` (the maintainer's tap; the user has push access via `gh`).
- No app/source/test changes anywhere in this plan — MacScrub's 49 tests are unaffected.

---

### Task 1: Seed `Casks/macscrub.rb` into the existing tap repo

**Files:**
- Create (external repo `tufantunc/homebrew-tap`, branch `main`): `Casks/macscrub.rb`
- Working area: clone the tap into a temp dir (e.g. `/tmp/homebrew-tap`); nothing in the MacScrub repo changes in this task.

- [ ] **Step 1: Clone the tap repo**

```bash
rm -rf /tmp/homebrew-tap
gh repo clone tufantunc/homebrew-tap /tmp/homebrew-tap
ls /tmp/homebrew-tap
```

Expected: clone succeeds; listing shows `Formula/` and `README.md` (no `Casks/` yet).

- [ ] **Step 2: Write the cask file**

Create `/tmp/homebrew-tap/Casks/macscrub.rb` with exactly:

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

- [ ] **Step 3: Verify the sha256 matches the published v1.4.0 DMG (the "failing test" for this task)**

```bash
cd /tmp && curl -sSLo MacScrub-v1.4.0.dmg \
  https://github.com/tufantunc/MacScrub/releases/download/v1.4.0/MacScrub-v1.4.0.dmg
shasum -a 256 /tmp/MacScrub-v1.4.0.dmg
```

Expected output hash: `c688e8bdb9f69246a9e7f9d12447147daca4ff9caae8e21c5a7ecefcaf53a7b4`. If it differs, STOP and report — do not push a wrong hash.

- [ ] **Step 4: Run brew style and audit against the cask**

```bash
brew style /tmp/homebrew-tap/Casks/macscrub.rb
```

Expected: `1 file inspected, no offenses detected`. Then:

```bash
brew tap tufantunc/tap 2>/dev/null || true
```

(Audit of a pathless cask file requires the tap context; full `brew audit --cask macscrub` is run in Step 6 after push. If `brew style` reports offenses, fix the cask file and re-run until clean.)

- [ ] **Step 5: Commit and push to the tap's main branch**

```bash
cd /tmp/homebrew-tap
git add Casks/macscrub.rb
git commit -m "macscrub 1.4.0"
git push origin main
```

Expected: push succeeds (the maintainer owns this repo; `gh` auth has push rights). **No Claude trailer in the commit.**

- [ ] **Step 6: End-to-end audit + install test from the live tap**

```bash
brew update
brew tap tufantunc/tap
brew audit --cask tufantunc/tap/macscrub
```

Expected: audit passes (no errors; style warnings would have been caught in Step 4). Then the careful local install test — `/Applications/MacScrub.app` may already exist from manual installation, so move it aside first:

```bash
[ -d /Applications/MacScrub.app ] && sudo mv /Applications/MacScrub.app /tmp/MacScrub.app.manual-backup || true
brew install --cask tufantunc/tap/macscrub
ls -d /Applications/MacScrub.app
spctl -a -t exec -vv /Applications/MacScrub.app
```

Expected: install succeeds; `spctl` reports `accepted` / `source=Notarized Developer ID`. (If `sudo` is unavailable non-interactively, ask the user to run the move command, or use `brew install --cask --force`.)

- [ ] **Step 7: Restore the original app and uninstall the brew copy**

```bash
brew uninstall --cask macscrub
[ -d /tmp/MacScrub.app.manual-backup ] && sudo mv /tmp/MacScrub.app.manual-backup /Applications/MacScrub.app || true
rm -f /tmp/MacScrub-v1.4.0.dmg
```

Expected: uninstall removes `/Applications/MacScrub.app`; the manual copy is restored afterward. (Do NOT use `--zap` — that would delete the user's real preferences plist.)

---

### Task 2: Add "Update Homebrew tap" step to the release workflow

**Files:**
- Modify: `.github/workflows/release.yml` (append after the "Create Release" step, which is currently the last step, lines 138–142)
- Test: none (CI YAML; validated by syntax check + next release run)

- [ ] **Step 1: Append the step to `.github/workflows/release.yml`**

Add after the `Create Release` step, at the same indentation as the other steps:

```yaml
      # Push the updated cask to the maintainer's tap so `brew upgrade` picks up
      # the new release. Runs last: if the token is missing/expired this fails
      # loudly, but the DMG + GitHub Release have already published above.
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

Notes baked into the design (do not "fix" these):
- The heredoc is intentionally **unquoted** (`<< EOF`): the shell expands `${VERSION}`/`${SHA}` while Ruby's `#{version}` passes through literally (`#{` is not shell syntax).
- GitHub Actions strips the leading indentation of `run:` blocks, and the heredoc body lines share the same indentation as the `cat` command, so the written file is flush-left after YAML processing — matching Task 1's file byte-for-byte (with version/sha substituted).
- `|| echo "no change"` tolerates re-running a tag with no diff.
- `GITHUB_TOKEN` cannot push cross-repo; `HOMEBREW_TAP_TOKEN` is required.

- [ ] **Step 2: Validate the YAML parses**

```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'
```

Expected: `yaml ok`. Then sanity-check the generated cask body locally by simulating the heredoc:

```bash
VERSION="9.9.9"; SHA="deadbeef"
bash -c '
VERSION="9.9.9"; SHA="deadbeef"
cat << EOF
cask "macscrub" do
  version "${VERSION}"
  sha256 "${SHA}"
  url "https://github.com/tufantunc/MacScrub/releases/download/v#{version}/MacScrub-v#{version}.dmg"
end
EOF'
```

Expected output contains `version "9.9.9"`, `sha256 "deadbeef"`, and the **literal** `v#{version}` in the url line.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: auto-update Homebrew tap cask on release"
```

(**No Claude trailer.** Before staging, run `git status` — if `MacScrub/Localization/Localizable.xcstrings` shows churn, `git checkout -- MacScrub/Localization/Localizable.xcstrings`; never stage `UserInterfaceState.xcuserstate`.)

---

### Task 3: Add Homebrew install section to README

**Files:**
- Modify: `README.md` (the `## Installation` section, currently lines 28–32)

- [ ] **Step 1: Rewrite the Installation section**

Replace this exact block in `README.md`:

```markdown
## Installation

Download the latest DMG from [Releases](../../releases), drag **MacScrub** to your Applications folder, and open it.

On first launch you may need to right-click → **Open** to bypass Gatekeeper.
```

with:

````markdown
## Installation

### Homebrew

```bash
brew install --cask tufantunc/tap/macscrub
```

### Direct download

Download the latest DMG from [Releases](../../releases), drag **MacScrub** to your Applications folder, and open it.
````

Note: the "right-click → Open" Gatekeeper line is intentionally dropped — releases have been notarized + stapled since v1.3.0, so it no longer applies.

- [ ] **Step 2: Verify rendering sanity**

```bash
grep -n -A 12 "^## Installation" README.md
```

Expected: shows the `### Homebrew` fenced code block and `### Direct download` subsection, and the following `## Usage` heading is intact.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Homebrew install instructions"
```

(**No Claude trailer.**)

---

### Task 4: Maintainer token setup (user-guided) + final verification

**Files:** none (manual GitHub settings + checks)

- [ ] **Step 1: Guide the user to create the PAT and secret**

Tell the user (in Turkish) to:
1. GitHub → Settings → Developer settings → **Fine-grained personal access tokens** → Generate new token; **Repository access: Only select repositories → `tufantunc/homebrew-tap`**; **Permissions → Contents: Read and write**. Nothing else.
2. Add it to the **MacScrub** repo: Settings → Secrets and variables → Actions → New repository secret, name **`HOMEBREW_TAP_TOKEN`**.

- [ ] **Step 2: Confirm the secret exists**

```bash
gh secret list --repo tufantunc/MacScrub
```

Expected: list includes `HOMEBREW_TAP_TOKEN` (plus the 5 existing notarization secrets). Wait for the user's confirmation before checking.

- [ ] **Step 3: Note the release-time verification (deferred)**

The CI automation is fully verified only on the next `v*` tag: confirm the "Update Homebrew tap" step pushes a new `Casks/macscrub.rb` to the tap, then `brew update && brew upgrade --cask macscrub` picks it up. Record this as a known follow-up in the final summary — do not tag a release just to test it.
