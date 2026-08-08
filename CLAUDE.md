# Mizan — working notes for Claude

Privacy-first, on-device iOS finance app. Personal use (Mark's iPhone 14
Pro), never published. Authoritative docs: `CLAUDE/finance_app_blueprint.md`
(spec), `AUDIT.md` (verified security/completion state), `README.md`
(structure + Phase-0 decisions).

## Commands (every Apple command needs the DEVELOPER_DIR prefix)

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate                      # after ANY project.yml edit
# Full test suite (all 8 packages via the one scheme):
xcodebuild -project Mizan.xcodeproj -scheme Mizan \
  -destination 'platform=iOS Simulator,name=Mizan-iPhone' \
  CODE_SIGNING_ALLOWED=NO test > /tmp/t.log 2>&1; echo "exit: $?"
# Device build + install (Mark's iPhone):
xcodebuild -project Mizan.xcodeproj -scheme Mizan \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcrun devicectl device install app \
  --device AF7B4FD4-F2A7-5A4F-8E9E-E8A4374E584C \
  ~/Library/Developer/Xcode/DerivedData/Mizan-*/Build/Products/Debug-iphoneos/Mizan.app
```

Never pipe xcodebuild through `tail` directly — exit codes vanish. Log to
a file, echo `$?`, grep for `error:`.

## Architecture invariants (breaking these is a bug, not a refactor)

- ALL persistence goes through `DatabaseManager.dbQueue()` (Persistence
  package). Nothing opens SQLite directly; services never cache the queue.
- ALL transaction writes go through `TransactionWriter` (Capture) — it
  owns validation, account-balance adjustment, and recurring-series
  auto-linking. Balance math must stay inside the same write transaction.
- Money is `Decimal` end-to-end, stored as exact TEXT. `Double` only for
  chart geometry / Monte Carlo. Shortcuts doubles → `Decimal(string:
  String(x))`. SQL never SUMs money columns — GROUP_CONCAT + add in Swift.
- Directions: spending aggregates net income against expenses in exactly
  the places already implemented (SalaryAllocationService, story, cuts) —
  adding netting anywhere else double-counts.
- Migrations (`DatabaseManager.runMigrations`) are append-only; v1–v5 are
  live on the real device.
- GRDB dependency is the DuckDuckGo SQLCipher fork **pinned by commit**
  (tag namespaces collide — see comment in Persistence/Package.swift).
  Records with auto-ids must be `MutablePersistableRecord`.
- App Intents (wallet/SMS) can't touch the biometric DB — they append to
  `PendingCaptureQueue`; the app drains on unlock. Keep it that way.
- Parser changes (BankSMSParser, ReceiptOCRService) must keep the
  verbatim real-sample tests green; new user samples become new verbatim
  tests. OCR fixtures regenerate via `Tools/ReceiptProbe.swift`
  (`receipts/` photos are git-ignored on purpose — never commit them).
- After data mutations post `.mizanDataDidChange` so dashboard refreshes.

## Operational

- Free Apple ID signing: profile expires every 7 days → rebuild+install
  ("re-sign"); data survives in-place installs. Paid program = 1 year.
- User-side items still open: Proxyman network day, logout-relaunch
  re-check, malformed-Shortcut attack, optional Face ID tripwire test
  (destructive — backup first). See AUDIT.md.
- Deferred by choice: on-device LLM (templates + parser + backend seam
  ready in LLM package; needs MLX + ~1 GB weights bundled manually).
- Commit style: what + why + "Suite: N green"; author Mark Emad
  <markemad@aucegypt.edu>; Claude co-author trailer.
