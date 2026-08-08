# Mizan — Privacy posture & App Store privacy label

Mizan is on-device and privacy-first by default. This file records exactly
what to declare on the App Store "privacy nutrition label" (App Store Connect
→ App Privacy) so the declaration stays honest as the AI backends evolve.

## Baseline (no AI, or on-device AI only)

With AI off, or running on Apple's on-device Foundation Models, **no user
data leaves the device**:

- Encrypted SQLite (SQLCipher) on-device, Face ID gated.
- No analytics, no crash reporting, no accounts, no bank login, no servers.
- **No third-party SDKs at all except the SQLCipher-patched GRDB** used for
  local encrypted storage — verified: the only external SPM dependency in the
  whole project is `duckduckgo/GRDB.swift`. No Firebase / Crashlytics /
  Sentry / Amplitude / Segment / ad or attribution SDKs are linked.
- Widgets read only a small derived App Group snapshot; nothing is uploaded.
- The AI entry is **hidden entirely** unless a backend actually exists on the
  device (Apple on-device model, or the user's own opt-in server), so a
  standard install shows no network-AI surface at all.
- Settings → Data → **"Erase all data"** wipes every record on device and
  returns the app to a clean starter state.

**Privacy label for this baseline: "Data Not Collected."** This is the
headline trust signal — keep the baseline able to make this claim.

## Backend tiers (privacy order)

| Tier | Where inference runs | What leaves the device | Consent |
|---|---|---|---|
| 1. Apple Foundation Models | On-device (A17 Pro+/iOS 26) | Nothing | Automatic; on-device |
| 2. Your own AI server (LAN/Tailscale) | The user's own Mac (Ollama/LM Studio) | The question + the injected `MizanContext` aggregates (net worth, month totals, top categories, budget %) — **not** the raw ledger | Explicit opt-in, off by default |
| 3. Cloud (BYO Claude key) — *planned* | Anthropic API | Same small aggregates + question | Explicit opt-in, off by default |

Only ever aggregated figures + the user's question are sent — the model
narrates numbers Mizan already computed; it never sees individual
transactions.

## What to declare when a network AI path exists

Tier 1 alone does not change the "Data Not Collected" baseline. Once a
**network** AI path (tier 2 or 3) ships as a feature, the label must reflect
that data *can* be sent, even if off by default:

- **Financial Info** → used for **App Functionality**, **not** linked to
  identity (Mizan attaches no identifier), **not** used for tracking.
- For tier 2 (user's own server) the developer still collects nothing — data
  goes to the user's own machine. For tier 3 (Anthropic) disclose that
  financial-info summaries are sent to a third party, used only to answer the
  question, and **not** used to train (Anthropic does not train on API data by
  default; zero-retention is available).
- Mark the AI feature as **optional** and describe the opt-in in the label
  notes.

## In-app disclosures (already present)

- Settings → Mizan AI: the "use my AI server" toggle carries a plain-language
  warning that the question + figures leave the phone for the user's own host.
- The Mizan AI screen shows a persistent one-line disclaimer: on-device mode
  says nothing is sent; server mode says the question + figures are sent to
  the connected server. Both say **"not financial advice."**

## Not financial advice

Mizan AI narrates the user's own figures. It does not provide personalized
investment advice. The disclaimer line on the AI screen states this; keep it.

## Related compliance (see AUDIT.md / project.yml)

- Encryption export compliance: `ITSAppUsesNonExemptEncryption` is now set to
  **YES** in `App/Info.plist` (SQLCipher/AES is non-exempt but qualifies for the
  standard-cryptography exemption). In App Store Connect answer: uses
  encryption → yes; only standard algorithms / no proprietary crypto →
  qualifies for exemption. The annual U.S. self-classification report still
  applies to the developer account. **Distribution is Egypt-only, so the
  French import declaration does not apply** (it is only required when the app
  is available in France).
- Local-network usage description + ATS `NSAllowsLocalNetworking` are declared
  for the tier-2 server path only.
