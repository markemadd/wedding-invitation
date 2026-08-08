# Mizan

A privacy-first, on-device personal finance app for iPhone. Personal use only
(Xcode / TestFlight, never published). Security is the non-negotiable
priority: encrypted at rest (GRDB + SQLCipher), gated by Face ID, no cloud
backend, no bank linking, no third-party data sharing.

The authoritative implementation source is
[`CLAUDE/finance_app_blueprint.md`](CLAUDE/finance_app_blueprint.md) —
read that before changing anything structural.
[`CLAUDE/post_mvp_roadmap.md`](CLAUDE/post_mvp_roadmap.md) is a code-free
planning restatement of the later phases, not additional scope.

## Building

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate   # after editing project.yml
open Mizan.xcodeproj
```

The generated `Mizan.xcodeproj` is committed, so simply opening it in Xcode
also works — `project.yml` is the source of truth for target settings.

Requirements: Xcode 16+, iOS 17.0 deployment target, `brew install swiftlint`
(lint runs as a build phase and degrades to a warning if missing).

## Module layout

Local Swift packages under `Packages/`, per blueprint Section 4:

| Package | Contents | Built in |
|---|---|---|
| `Persistence` | GRDB records, migrations, `DatabaseManager` | Phase 1 |
| `MizanSecurity` | Keychain key manager, app lock, logout, encrypted backup | Phase 1 |
| `Capture` | Manual entry, receipt OCR, wallet App Intent, voice | Phase 2 |
| `Budgeting` | `SalaryAllocationService`, category logic | Phase 3 |
| `SavingsAndGoals` | Goals, wishlist, debt, sinking funds, recurring detection | Phase 4 |
| `Forecasting` | Monte Carlo engine | Phase 5 |
| `LLM` | MLX Swift wrapper, prompt templates | Phase 5 |
| `UI` | Theme tokens, `GlassCard`, `RadialGauge`, screens | ongoing |

## Phase 0 decisions worth knowing about

- **GRDB + SQLCipher via the DuckDuckGo fork** (`duckduckgo/GRDB.swift`):
  upstream GRDB doesn't offer an SQLCipher-enabled target through SPM, and
  this fork exists exactly to provide one. Full-database encryption is
  required by the blueprint, so this is the faithful SPM resolution of
  "GRDB.swift with the SQLCipher build target".
- **`MizanSecurity`, not `Security`**: a Swift module named `Security` would
  shadow Apple's Security.framework, which the Keychain code inside the
  module has to import. Name prefixed to avoid the collision; structure
  otherwise matches the blueprint.
- **MLX Swift and WhisperKit are not dependencies yet**, per the blueprint's
  own Phase 0 watch-out: MLX lands in Phase 5, WhisperKit only if
  `SFSpeechRecognizer` proves insufficient for Egyptian Arabic in Phase 2.
- **Git stays local.** No remote is configured, deliberately — the "no cloud"
  principle covers version history too.

## Manual steps that need a human

- **Apple Developer Program membership** ($99/yr) so signing lasts a year
  instead of the free tier's 7-day resign cycle — enroll and select the team
  in Xcode's Signing & Capabilities tab before installing on a device.
