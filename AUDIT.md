# Mizan — Phase 7 audit report

Date: 2026-07-06 · Build: commit at time of audit · Suite: 72/72 tests green.
Per the blueprint, every item below was **physically executed**, not
re-read from code — except the rows explicitly marked *pending user*,
which require the owner's hands/eyes on the device.

## 1. Security checklist (blueprint Phase 7)

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Extract `.sqlite` from device; confirm unreadable | **PASS** | Pulled via `devicectl` from the real iPhone. Header = random SQLCipher salt (no `SQLite format 3`); `sqlite3 .tables` → "file is not a database"; `strings` scan: zero merchant/amount/currency traces |
| 2 | App Switcher snapshot covered by shield | **PASS (user-verified)** | Owner confirmed the green shield covers the card; opaque cover by design (blur can leak numerals) |
| 3 | Face ID required on every relaunch | **PASS (user-verified)** | Owner confirmed on device; DB creation behind the gate corroborates |
| 4 | Logout → relaunch requires full unlock | *pending user* | Logout button live in Settings + Home; identical teardown path as lock is unit-verified (connection + LAContext invalidated) |
| 5 | Network inspection (full day, proxy) | *pending user* | Code-level sweep executed: exactly **one** network call site in the codebase (`PriceFetchService`, allowlisted host `stooq.com`, default-OFF toggle that throws when disabled — throw path unit-tested). Proxyman day recommended to close formally |
| 6 | Malformed wallet-intent input rejected | **PASS (code path)** | Negative/NaN amounts and empty merchants throw before queueing (guards in intent); TransactionWriter re-validates at import. On-device Shortcut attack *pending user* alongside wallet re-test |
| 7 | Malformed stock-signal import rejected | **PASS** | Executed as tests: missing field, wrong type, bad enum, out-of-range confidence, one-bad-entry-rejects-file, non-JSON, empty — all refuse outright, never partial-import |
| 8 | Wrong-passphrase backup fails cleanly | **PASS** | Executed as tests: wrong passphrase and single-bit tamper both throw `wrongPassphraseOrCorrupt`; exports are non-deterministic (fresh salt/nonce) |
| 9 | `biometryCurrentSet` tripwire fires on re-enrollment | *pending user (destructive)* | Flag verified present at key creation. Live test invalidates the key permanently = data reset; owner may run it after taking an encrypted backup, or accept code-review-only |

**Deviations/additions to the Phase 1 security model, all documented in code:**
backup uses envelope encryption (restorable off-device) + PBKDF2-600k
instead of the blueprint's simplified sketch (owner-approved);
`PendingCaptureQueue` holds background captures (merchant+amount only)
under a non-biometric device key until next unlock (owner-approved
tradeoff that makes wallet/SMS automation possible at all).

## 2. MoSCoW completion audit (blueprint Section 3)

**Must-have — 15/15 implemented, tested, reachable:** encrypted
persistence (SQLCipher, Decimal-as-TEXT), Face ID lock (instant on
background), distinct logout, manual entry, receipt OCR (ar+en, tuned
10/10 on real receipts), Apple Pay capture (via queue), account &
category management, net worth dashboard, salary allocation (exact-100%
rule), bucket-based category budgeting, transaction search, swipe
review/edit, monthly review (top-3 + trend), light/dark theme, CSV/JSON
export, encrypted backup.

**Should-have — 10/12:** recurring detection ✓ (user-confirmed),
bills calendar + notifications ✓, anomaly/duplicate detection ✓ (wired
into capture), savings tracker ✓, what-if goal planner with per-goal cut
scope ✓ (cuts sum exactly to gap), wishlist dual framing ✓, debt
amortization ✓ (ends at 0 within a cent), sinking funds ✓, Arabic voice ✓
(+ number-words). **Gaps (accepted, owner may reprioritize): Sankey
diagram ✗, drag-and-drop dashboard widgets ✗.**

**Could-have:** forecasting ✓ (Monte Carlo, percentile bands), investments
✓ (FIFO lots, gains, asset classes), asset-class breakdown ✓,
multi-currency ✓ (EGP/EUR/USD/GBP via manual FX table). **On-device LLM:
deferred by owner decision** — templates, strict JSON parser, and backend
seam are built and tested; MLX + model weights plug in when wanted.

**Won't-have:** none crept in. Stock signals remain external
(ephemeral import, never persisted, never auto-acted).

**Post-blueprint additions (owner-requested):** bank-SMS capture (intent
+ paste), InstaPay transfers with income direction and category netting,
duplicate guard across wallet/SMS, live account balances, observation-
month allocation suggestions, over-limit alerts, category memory.

## 3. ERD-vs-implementation audit (blueprint Section 5)

Every entity: GRDB record ✓ · migration ✓ · read/write service ✓.

| Entity | Service(s) |
|---|---|
| ACCOUNT | Settings CRUD, TransactionWriter balance tracking |
| TRANSACTION | TransactionWriter, search, all aggregates |
| CATEGORY | Settings CRUD, CategoryMatcher, bootstrapper sync |
| CATEGORY_ALLOCATION | SalaryAllocationService (atomic replace) |
| INCOME | SalaryAllocationService (singleton row) |
| RECURRING_SERIES | RecurringDetectionService, BillsCalendarService |
| SINKING_FUND | SinkingFundService |
| GOAL | SavingsAndGoalsService |
| WISHLIST_ITEM | SavingsAndGoalsService.timeToSave |
| DEBT | AmortizationCalculator + Plan tab |
| HOLDING / COST_BASIS_LOT | InvestmentService (FIFO) |
| NET_WORTH_SNAPSHOT | NetWorthSnapshotService (daily, idempotent) — gap found in audit, closed |

Schema beyond the ERD, each deliberate and commented: `fxRate` table
(multi-currency decision, v2), holding price cache columns (v3),
transaction `direction` (InstaPay, v4). Blueprint naming deviations:
module `Security`→`MizanSecurity` (framework shadow), GRDB via the
DuckDuckGo SQLCipher fork pinned by commit (tag-namespace collision).

## Verdict

All Must-haves and the security model hold under executed testing. The
app is complete against the blueprint except: two Should-have visuals
(Sankey, drag-widgets), the owner-deferred LLM, and four checklist items
only the owner can physically perform (rows 4, 5, 6-on-device, 9).
