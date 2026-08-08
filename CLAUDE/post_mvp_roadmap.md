# Post-MVP roadmap — versions after v1

This picks up exactly where the MVP (v1) leaves off. v1 already covers the full "Must have" list from the blueprint: encrypted persistence, Face ID lock, the four capture methods, accounts/categories, the net worth dashboard, salary allocation, category-based budgeting, search, swipe-edit, monthly review, light/dark theme, export, and encrypted backup. Everything below assumes v1 is built, tested, and in daily use before starting.

No code in this document, by request — just direction, dependencies, coding-level guidance, and the UI/color evolution for each version.

---

## v2 — Behavioral intelligence

**What gets added:** recurring-transaction detection, the bills/subscriptions calendar with notifications, anomaly/duplicate detection, the monthly savings tracker, the what-if goal planner with proactive cut suggestions, the wishlist with time-to-save, debt payoff/amortization tracking, and sinking funds.

**What it connects to from v1:** every one of these reads from v1's `transaction` and `category` tables and the `SalaryAllocationService`'s monthly summary — none of it is a new data source, it's intelligence layered on top of data v1 already collects. Specifically: the goal planner's cut suggestions depend on the `bucket` classification (fixed / non-monthly recurring / flexible) you assign to each category back in v1 — if that classification was skipped or done carelessly during v1, go back and fix it before starting v2, since the whole cut-suggestion feature is only as good as that labeling.

**Coding level and direction:** this entire version stays deterministic — periodicity clustering, z-score-style anomaly checks, and a standard amortization formula. No machine learning belongs here yet; these are well-defined statistical problems, and solving them with plain arithmetic is both more reliable and dramatically cheaper than reaching for a model. Keep every scan bounded — group by merchant or category before looping, so nothing accidentally becomes an O(n²) pass over your full transaction history as it grows across months and years. This is the version where the habit of commenting *why* a threshold or heuristic was chosen (not just what the code does) matters most, since these are exactly the kind of tunable constants (tolerance bands, z-score cutoffs, confidence formulas) a future reader — including future you — will want to understand the reasoning behind, not just the value.

**Worth citing:** the goal-gradient effect (Kivetz, Urminsky & Zheng, 2006) — showing concrete progress and a specific next step drives follow-through more than a static red/green indicator, which is the whole justification for "proactive suggestions" rather than passive over-budget flags. The wishlist's dual framing still rests on Vicki Robin & Joe Dominguez's life-energy cost concept (*Your Money or Your Life*, 1992, revised 2018) — nothing newer has meaningfully displaced this as the reference for reframing price as time.

**UI and color direction:** this version introduces the multi-segment progress bar as a recurring UI element, not just a one-off dashboard piece — goal cards, sinking-fund cards, and the wishlist all reuse it. Color meaning should be consistent everywhere it appears: mint for on-track, cream for "approaching but not yet over," coral/red for over. Proactive suggestions need their own distinct visual treatment so they read as *insight*, not just another data readout — a small callout card with a subtle accent border (not a full colored background) works well here, keeping it noticeable without turning the whole screen into an alert.

---

## v3 — Depth and intelligence

**What gets added:** the on-device LLM assistant (categorization suggestions, chat, forecast narration), Monte Carlo net worth/retirement forecasting, investment and holdings tracking with cost-basis lots and gains/losses, the self-built asset-class breakdown, and narrow public price/FX fetching.

**What it connects to from v1 and v2:** the LLM's categorization prompt should be constrained to output only categories that already exist in your v1 taxonomy — treat it as a classifier choosing among known options, not a free-text generator, since that's both more reliable and easier to validate. The chat assistant's grounding context should pull from v1's transaction/allocation data and v2's goals and wishlist, so answers reference your actual numbers rather than the model's general knowledge. Forecast narration consumes this version's own Monte Carlo output. Investment tracking is the one genuinely new vertical here, but it still feeds the same net worth aggregate v1 already established on the dashboard — don't build a second, separate "portfolio value" number that lives apart from net worth.

**Coding level and direction:** this is the one part of the whole project where your Python-first workflow genuinely belongs, not just as a training-pipeline afterthought. Before writing a single line of Swift for the categorization prompt, prototype and evaluate it in Python on your laptop: build a small labeled dataset from your own real transactions, try a few prompt variations against your chosen quantized model (or a same-family cloud version for faster iteration), and measure accuracy before porting the finalized prompt template into the Swift/MLX inference code. This keeps the experimentation loop in the language you're fastest and most comfortable in, and only commits to Swift once you know the prompt actually works. On the Swift side, keep the LLM strictly to language tasks — categorization suggestion, conversational answers, narration — and never let it touch arithmetic that v1/v2's deterministic code already does correctly; a model has no advantage there and only introduces a new source of error.

**Worth citing:** for the on-device model itself, the 2024 survey "On-Device Language Models: A Comprehensive Review" is a solid, current reference on personalization and the practical limits of on-device continual learning — worth reading before deciding whether your model needs periodic re-tuning against your own data or whether a static model is sufficient. For forecasting, update the design from the earlier static 4%-rule framing: Morningstar's *State of Retirement Income* report is republished annually and is the most current authority here — the 2025 edition (published December 2025, covering 2026 planning) puts the base-case safe withdrawal rate at 3.9%, using **forward-looking capital-market assumptions rather than historical backtests**, targeting a 90% success probability across Monte Carlo trials rather than a fixed guarantee. Your forecasting engine should follow this same logic: don't just replay your own historical variance forward blindly, weight it against forward-looking return/inflation assumptions the way Morningstar's methodology does, and report a success probability rather than a single confident number.

**UI and color direction:** keep the LLM chat interface visually distinct from the data screens around it — a modal or sheet presentation with a slightly different background treatment signals "this is a conversation," not another ledger view, and prevents the assistant from feeling like just another tab competing with your actual data. Forecast percentile bands read better as translucent, overlapping mint-toned layers (lighter for the outer 10th/90th bounds, a solid darker line for the median) rather than three flatly-colored separate series — this keeps the "layered, alive" glass language from v1 consistent instead of reverting to a generic charting-library default the moment the data gets more complex.

---

## v4 — Visual system and full theming

**What gets added:** uniform application of the full design system across every screen built across v1-v3, the Sankey cash-flow diagram, drag-and-drop dashboard widget customization, and a deliberate light/dark parity pass.

**What it connects to:** everything — this version doesn't add data or logic, it retrofits presentation across the entire app built so far. That's precisely why it comes after the feature versions rather than being spread across them: doing a full visual pass while data logic is still changing underneath it means redoing the same work twice.

**Coding level and direction:** this should be almost entirely SwiftUI view-layer work with no new business logic. The one discipline worth being strict about: resist the temptation to "clean up" or refactor service-layer code while you're in there for a visual pass — mixing presentation changes with logic changes is exactly how a working, already-tested feature quietly breaks. Keep the two kinds of change in separate commits even if they touch the same screen.

**Worth citing:** Jakob Nielsen's consistency heuristic (1994, still one of the most cited usability principles today) is the underlying justification for this whole version — a unified visual language reduces the cognitive load of relearning each screen, which matters more as the app now spans a dozen-plus screens across four versions of features.

**UI and color direction:** the Sankey diagram should stay to the same two-hue language as everything else — income flows in mint, expense flows in the warm cream/coral tone — rather than the rainbow-per-category coloring Sankey diagrams often default to; a two-color flow diagram stays readable, a ten-color one turns into noise. Drag-and-drop widget customization should use a long-press-to-enter-edit-mode pattern with a subtle lift effect on the active widget. Note this is a case where the actual shipped app has more visual freedom than the chat-based mockup tool we used earlier in this project — the mockup tool's flat, no-shadow design rules were a constraint of that specific preview surface, not a rule for your real SwiftUI app, so a soft shadow or slightly stronger material blur to indicate "this widget is lifted and moveable" is entirely appropriate here even though it wasn't used in the earlier mockups.

---

## v5 — Export, external integration, and security hardening

**What gets added:** CSV/JSON export, the external Cowork stock-signal import channel, a full STRIDE security re-audit against the now much larger feature surface, the MoSCoW completion audit, and the ERD-vs-implementation audit.

**What it connects to:** all four prior versions — this is the verification version, not a feature version. Nothing here is user-facing in the way v1-v4 were; it exists to confirm everything already built actually holds up.

**Coding level and direction:** any new code in this version (export serializers, the stock-signal import schema validator) should be the simplest and most defensively written code in the entire project — reject malformed input outright rather than trying to be lenient or clever about partial recovery, since this is the last checkpoint before considering the app finished. This is not the place to introduce anything sophisticated.

**Worth citing:** STRIDE (Kohnfelder & Garg, Microsoft, 1999) again, since the re-audit is literally structured around it — worth re-walking all six categories (spoofing, tampering, repudiation, information disclosure, denial of service, elevation of privilege) against the full v1-v4 feature set, not just the v1 subset it was originally checked against.

**UI and color direction:** minimal by design — mostly a settings/export screen using the established system as-is. This version shouldn't introduce any new visual language; if it does, that's a sign a feature crept in that belongs in a future version instead.
