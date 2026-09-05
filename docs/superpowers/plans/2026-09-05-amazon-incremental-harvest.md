# Incremental Harvest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After initial full harvest, only fetch orders newer than cutoff C and selectively re-check details for refunds within 90 days; keep incremental sessions cheap (fewer switches/probes).

**Architecture:** Add cutoff helpers (`newestOrderBookingDate`, `incrementalHarvestCutoff`) and tighten `effectiveScanFiltersMonths` + `scheduleIncrementalRefundWatch` candidate rules. Constants: 14d list safety, 90d refund watch. Session opts: details-only skip, discovery reuse, months-3 gate, Business ABA shortcut, HTML-matched switcher skip. Keep full harvest paths unchanged.

**Tech Stack:** Lua MoneyMoney plugin (`amazon-orders.lua`), `test/run.sh` + mm_shim.

**Status:** Umgesetzt (2026-09-05). Spec:
`docs/superpowers/specs/2026-09-05-amazon-incremental-harvest-design.md`.

## Global Constraints

- Behavior-preserving for full/initial harvest
- No silent fallbacks; explicit predicates
- Diff-CRAP gate 5 for touched new helpers
- Write-time refactor bar; German user-facing status only if needed

---

### Task 1: Cutoff helpers + tests

**Files:**
- Create: `test/test_incremental_harvest_cutoff.lua`
- Modify: `amazon-orders.lua` (const + helpers near refresh helpers)
- Modify: `test/measure_diff_crap.lua` (add new function names)

- [x] Write failing tests for `newestOrderBookingDate`, `incrementalHarvestCutoff`, `orderMayNeedIncrementalRefundWatch`
- [x] Implement helpers + consts `incrementalListSafetySec=14*day`, `incrementalRefundWatchMaxAgeSec=90*day`
- [x] Run `./test/run.sh test/test_incremental_harvest_cutoff.lua` — pass

### Task 2: Wire list scan + refund watch

**Files:**
- Modify: `amazon-orders.lua` (`effectiveScanFiltersMonths`, `incrementalRefundWatchSince`, `scheduleIncrementalRefundWatch`)
- Modify: `test/test_incremental_harvest_cutoff.lua` (integration asserts via env functions)

- [x] Red: assert effectiveScanFiltersMonths uses cutoff; refund watch skips settled/unbilled/old
- [x] Green: wire implementations
- [x] Run focused tests + `test_order_filter_scan` / business get tests if affected
- [x] Update `CLAUDE.md` one bullet on incremental behavior
- [x] `./link_ext.sh`

### Task 3: Session optimizations

**Files:**
- Create: `test/test_incremental_session_optimizations.lua`
- Modify: `amazon-orders.lua` (list-harvest skip, discovery reuse, months-3, Business ABA shortcut, switcher HTML match)
- Modify: `test/measure_diff_crap.lua`

- [x] Details-only when last list scan wall-clock (`lastListHarvestAt`) is fresh (`incrementalListMinRescanSec`), including after re-login; `lastHarvestSince` stays MoneyMoney since watermark
- [x] Reuse complete `discoveredSubAccounts` without switcher
- [x] Skip `months-3` when `scanFiltersMonths < 3`
- [x] Business incremental → ABA without SPA order-list probes
- [x] `ensureAmazonSubAccountSession` no-op when HTML already matches kind
- [x] Tests + Diff-CRAP targets for new helpers

### Task 4: Verify

- [x] `./test/run.sh test/test_incremental_harvest_cutoff.lua`
- [x] `./test/run.sh test/test_incremental_session_optimizations.lua`
- [x] `./test/run.sh test/measure_diff_crap.lua`
- [x] Smoke: related harvest tests still OK
