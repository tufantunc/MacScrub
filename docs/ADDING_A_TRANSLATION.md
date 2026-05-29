# Adding a Translation to MacScrub

MacScrub is localized with a **String Catalog** (`MacScrub/Localization/Localizable.xcstrings`). It currently ships three languages:

| Language | Code |
|----------|------|
| English (source) | `en` |
| Turkish | `tr` |
| Simplified Chinese | `zh-Hans` |

This guide walks through adding a new one — for example German (`de`). It has two parts:

1. **Translate the strings** so the app speaks your language when macOS (or the user's selection) is set to it.
2. **(Optional) Add it to the in-app Language picker** so users can choose it explicitly in Preferences.

Use your language's standard code (BCP-47 / Apple region code): `de` (German), `fr` (French), `ja` (Japanese), `es` (Spanish), `pt-BR` (Brazilian Portuguese), `zh-Hant` (Traditional Chinese), and so on.

---

## Part 1 — Translate the strings

You can do this either in Xcode (recommended if you have it) or by editing the catalog JSON directly (good for scripting / no Xcode).

### Option A — In Xcode (recommended)

1. Open the project: `open MacScrub.xcodeproj` (run `xcodegen generate` first if it doesn't exist).
2. Select **`MacScrub/Localization/Localizable.xcstrings`** in the navigator.
3. Click the **`+`** at the bottom of the language list and choose your language.
4. Xcode adds a column for it with every key marked **New**. Fill in each value.
5. Set each row's state to **translated** (the green checkmark) as you go.
6. Build (⌘B). Xcode compiles the catalog into your language's resources automatically.

### Option B — Edit the catalog JSON directly

`Localizable.xcstrings` is plain JSON. Each entry looks like this:

```json
"menu.settings" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Preferences…" } },
    "tr" : { "stringUnit" : { "state" : "translated", "value" : "Tercihler…" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "偏好设置…" } }
  }
}
```

To add a language, every key needs a `stringUnit` for your code. The script below seeds your language with **English placeholders** for any key that doesn't have it yet, so you can then go through and translate each value:

```bash
# Run from the repo root. Replace "de" with your language code.
LANG_CODE=de python3 - <<'PY'
import json, os
code = os.environ["LANG_CODE"]
path = "MacScrub/Localization/Localizable.xcstrings"
d = json.load(open(path, encoding="utf-8"))

added = 0
for key, entry in d["strings"].items():
    locs = entry.setdefault("localizations", {})
    if code in locs:
        continue
    # seed from English (fall back to the key itself), marked "needs_review"
    en = locs.get("en", {}).get("stringUnit", {}).get("value", key)
    locs[code] = {"stringUnit": {"state": "needs_review", "value": en}}
    added += 1

json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print(f"seeded {added} keys for '{code}' (now translate them and set state to 'translated')")
PY
```

Then open the file and replace each seeded English value with your translation. When a value is final, change its `"state"` from `"needs_review"` to `"translated"`.

> **Tip:** keys whose value contains `%lld` (a number) must keep that exact placeholder — e.g. `overlay.instruction` is `"Hold all modifier keys for %lld seconds to exit."`. Don't translate or remove `%lld`; just move it to wherever it reads naturally in your language.

### What to keep untranslated

- **Modifier key names** shown on the overlay/preferences keycaps — `Command`, `Option`, `Control`, `Shift` — are intentional literals in the views and are **not** in the catalog. Leave them as-is.
- The `"SEC"` label and the app name **MacScrub** are not translated.

### Verify the catalog still parses

```bash
python3 -c "import json; json.load(open('MacScrub/Localization/Localizable.xcstrings')); print('valid JSON')"
```

After a build, the new language is bundled automatically — no `project.yml` change is needed (the String Catalog declares its own languages, and the project's sources are directory-globbed).

---

## Part 2 — Add it to the in-app Language picker (optional)

Preferences → **Language** lets users pick a language explicitly (overriding the system language). That list is driven by the `AppLanguage` enum, **not** by the catalog — so a new translation works when the *system* is set to it even without this step, but won't appear as an explicit choice until you add a case.

Edit `MacScrub/State/AppLanguage.swift`:

```swift
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english = "en"
    case turkish = "tr"
    case chinese = "zh-Hans"
    case german  = "de"      // ← add your case; raw value MUST equal the catalog code

    var id: String { rawValue }

    /// `nil` means "follow the system" (no `AppleLanguages` override).
    var localeCode: String? {
        self == .system ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .system:  return String(localized: "language.system", defaultValue: "System")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .chinese: return "中文"
        case .german:  return "Deutsch"   // ← shown in the picker (use the endonym)
        }
    }
}
```

That's all the wiring you need:

- The picker iterates `AppLanguage.allCases`, so your case appears automatically.
- Selecting it writes the raw value (e.g. `de`) to `AppleLanguages`; selecting **System** clears the override.
- A "Restart Required" alert is shown automatically — language changes apply on next launch (standard macOS behaviour).

The `displayName` for real languages is shown in the language's own name (endonym), e.g. `Deutsch`, `Français`, `日本語` — not localized.

---

## Part 3 — Test it

1. Regenerate/build:
   ```bash
   xcodegen generate
   xcodebuild build -project MacScrub.xcodeproj -scheme MacScrub -destination 'platform=macOS'
   ```
2. Run the app, open **Preferences → Language**, choose your language, and **quit and reopen** (the restart alert reminds you).
3. Confirm the idle window, preferences, menu, and cleaning overlay all read correctly — watch for clipped or wrapped text in the fixed-width window, and confirm any `%lld` numbers appear in the right place.

If something reads oddly long and clips, that's a translation-length issue — tighten the wording; the layout targets concise, Apple-style copy.

---

## Submitting your translation

Open a pull request that includes:

- the updated `MacScrub/Localization/Localizable.xcstrings` (all keys `translated` for your code),
- the `AppLanguage` case (if you added the explicit picker entry),

and mention which language/code you added. Thank you for helping localize MacScrub! 🧼
