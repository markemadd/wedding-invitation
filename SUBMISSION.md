# Mizan — App Store submission checklist

Single source of truth for shipping Mizan to the App Store. Companion to
`PRIVACY.md` (privacy-label posture) and `AUDIT.md` (security state).
Distribution target: **Egypt only** (simplifies encryption/export paperwork).

## Status legend
✅ done in code/repo · 📝 metadata to enter in App Store Connect · ⛔ blocker
on an external account/action · ⚠️ needs a decision or a manual check

---

## 1. Hard blockers
- ⛔ **Paid Apple Developer Program.** Uploading via a friend's paid account is
  the plan. Their team ID replaces the free personal team in `project.yml`
  (`DEVELOPMENT_TEAM`) for the distribution/archive build. Bundle id stays
  `com.markemad.mizan` (must be registered under that team).
- ⛔ **Privacy Policy URL** (required for every app, Guideline 5.1.1). Content
  is ready in `PRIVACY.md`; host it as a **public Notion page** and paste the
  URL into App Store Connect → App Privacy. *(Blocked in-session: the Notion
  connector needs OAuth authorization before the page can be created here.)*
- ✅ **Encryption export compliance** — `ITSAppUsesNonExemptEncryption = YES`
  set in `App/Info.plist`. Egypt-only ⇒ no French declaration. See PRIVACY.md.

## 2. Names & metadata (📝 entered in App Store Connect, not code)
- **App Store name:** `Mizan — Private Money Tracker`
  - On-device home-screen name stays **`Mizan`** (`CFBundleDisplayName`,
    unchanged — the long name would truncate under the icon). The store
    listing name and the springboard name are intentionally different.
- **Subtitle (30 chars):** e.g. `On-device, encrypted, private`
- **Category:** Finance · **Age rating:** 4+
- **Keywords / description / promo text:** draft separately; lead with
  on-device + encrypted + no-accounts + no-tracking.
- ⚠️ **Name availability:** "Mizan" is a common word — confirm the exact
  store name isn't taken when the record is created.
- **Support URL** (required) and **Marketing URL** (optional): can also be
  public Notion pages (same connector, once authorized).

## 3. Screenshots & assets
- ✅ 1024×1024 marketing icon present (`App/Assets.xcassets/AppIcon`).
- ✅ **Raw 6.9" captures generated** (`Screenshots/` — wallet/bills/buckets/
  insights, 1320×2868, real UI with seeded demo data). Regenerate any time:
  build Debug, then launch on the iPhone 16 Pro Max sim with
  `SIMCTL_CHILD_MIZAN_SCREENSHOT=1 SIMCTL_CHILD_MIZAN_SCREENSHOT_TAB=<tab>`
  and `xcrun simctl io <udid> screenshot`. The screenshot harness
  (`App/ScreenshotSupport.swift`) is **DEBUG-only** (fixed key, seeded ledger,
  no Face ID) and compiled out of Release.
- Next: drop these onto styled marketing backgrounds (Higgsfield) with captions.
- 📝 **6.9"/6.7" iPhone screenshots** (iPhone-only app ⇒ no iPad set); the
  16 Pro Max 6.9" captures satisfy the current largest-size requirement.
  - ⚠️ App Store **screenshots must show the real app UI** (Guideline 2.3.3) —
    take them from the running app on the 6.7" simulator, then optionally
    place those real frames on styled marketing backgrounds. Fully AI-generated
    "screenshots" that don't depict the actual UI are a rejection risk; use
    Higgsfield (or similar) for **backgrounds/captions around real captures**,
    not to fabricate the screens themselves.
- 📝 App preview video: optional, skip for v1.

## 4. Guideline / review-risk items
- ✅ **AI feature (Guideline 2.1).** The "Ask Mizan AI" entry is now hidden
  unless a backend truly exists (`aiEntryAvailable` in `WalletView`), so a
  reviewer never sees a non-functional AI surface.
- ✅ **Empty states.** Fresh install seeds accounts/categories but zero
  transactions; Insights now shows a friendly empty state instead of a wall
  of zero-value cards. Wallet/Bills/Buckets already have empty states.
- ✅ **"Not financial advice"** disclaimer present on the AI screen.
- ⚠️ **Trademarks (Guideline 5.2).** "InstaPay", "ValU", "Halan", bank names
  appear as plain-text compatibility labels (nominative use — OK). Do **not**
  use their logos, and keep them out of the app *name/subtitle*. Fine in
  description body as "works with…".
- ⚠️ **Transfers don't move money.** `TransferView` only records two ledger
  legs; confirm no copy implies Mizan executes a real transfer (avoids
  money-transmitter scrutiny). Quick manual copy check before submit.
- ✅ **No accounts** ⇒ the in-app account-deletion requirement (5.1.1 v) does
  not apply. An **"Erase all data"** control now exists anyway (Settings →
  Data) as a privacy nicety.

## 5. Known caveat to verify on a real device
- ⚠️ **Face ID / `.biometryCurrentSet` key.** Unlock uses
  `.deviceOwnerAuthentication` (falls back to passcode ✅), but the DB key is
  bound to `.biometryCurrentSet`, which requires **enrolled biometrics** to
  create/read. On a reviewer device with a passcode but no Face ID enrolled,
  first unlock could fail. Reviewers normally use Face-ID-capable devices, but
  test the "passcode set, no Face ID enrolled" path before submitting; if it
  locks out, provide review notes explaining the biometric requirement or
  relax the access-control class. (Security decision — do not change silently.)

## 6. Decided against (state as selling points)
- **No analytics / no crash SDKs / no ad or attribution SDKs.** Verified: the
  only third-party dependency is the SQLCipher GRDB fork. This is a headline
  trust signal — say so in the listing and keep it true.
