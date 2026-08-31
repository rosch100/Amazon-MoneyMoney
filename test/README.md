# Offline test harness

MoneyMoney runs `amazon-orders.lua` inside its own host, parsing Amazon HTML with
libxml2 (HTML parser + XPath) — **no JavaScript is executed**. This harness lets
you run the plugin's parsing functions against *saved* Amazon pages on your own
machine, so you can adjust selectors when Amazon changes its layout without
needing a live login each time.

It emulates the MoneyMoney host environment on top of LuaJIT + libxml2, loads the
real (unmodified) `amazon-orders.lua`, and calls its global functions
(`getOrdersFromSummary`, `getOrderDetails`, …) against HTML files you provide.

## Prerequisites (one-time)

```sh
brew install luajit luarocks
luarocks --lua-version=5.1 install xmlua   # libxml2 binding (pulls luacs, luautf8)
```

`xmlua` installs into `~/.luarocks` for Lua 5.1 (LuaJIT). `test/run.sh` wires up
the right module paths for you.

## Running the tests

```sh
./test/run.sh test/selftest.lua     # sanity check: shim works (synthetic page)
./test/run.sh test/test_parse.lua   # deterministic parser regression tests
for test_file in test/test_*.lua; do ./test/run.sh "$test_file"; done
```

`test/run.sh <script.lua>` just sets `PATH` + the luarocks 5.1 module paths and
runs the script under `luajit`. You can point it at any Lua script.

### Test catalog

The complete suite is organized by behavior:

| Area | Tests |
|------|-------|
| Host shim and HTML parser | `selftest.lua`, `test_parse.lua`, `test_html_encoding.lua`, `test_akamai_interstitial.lua` |
| Account discovery, attributes and migration | `test_list_accounts.lua`, `test_account_attributes.lua`, `test_account_switcher.lua`, `test_migrate_legacy_emit.lua` |
| Account setup and initial sync | `test_account_setup_no_harvest.lua`, `test_initial_sync_*.lua`, `test_full_refresh.lua`, `test_full_reimport.lua`, `test_empty_emit_misaligned.lua` |
| Sub-account scheduling | `test_sub_account_scan_refresh.lua`, `test_mix_scan_round_robin.lua`, `test_realign_scan_priority.lua`, `test_preserve_incomplete_scan_login.lua` |
| Order-list and Business harvest | `test_order_filter_scan.lua`, `test_scan_filters_months.lua`, `test_business_*.lua`, `test_ab_order_history.lua` |
| Amazon Business Analytics | `test_aba_*.lua` |
| Detail retrieval and incomplete-refresh marker | `test_details_rescan.lua`, `test_incomplete_refresh_dummy.lua`, `test_emit_no_dummies.lua`, `test_login_nil_page.lua` |
| Transactions, refunds, returns and cancellations | `test_transaction_fields.lua`, `test_summary_adjustments.lua`, `test_refund_reimport.lua`, `test_storno_omit.lua`, `test_partial_return.lua`, `test_full_return_retained_shipping.lua`, `test_floating_ausgleich.lua`, `test_messagelist.lua` |

The wildcard rows refer to every matching `test/test_*.lua` file, so the loop
above remains the source of truth for running the whole suite.

## Inspecting captured pages

Automated parser tests use synthetic, anonymized HTML directly in the test files,
so they run in every clean checkout. Real Amazon pages may be stored locally in
`test/pages/` for selector analysis; that directory is gitignored because those
pages contain personal data and must never be committed.

To capture a page the way the plugin actually receives it, save the **raw server
HTML**, not the browser's post-JavaScript DOM:

- Best: open the page, **View Source** (`Cmd+Option+U`), then `Cmd+S`.
- Or: DevTools → **Network** → reload → click the top "document" request →
  **Response** tab → copy that HTML.
- Avoid "Save Page As → Complete", which can capture the rendered DOM.

Sanity check after saving: you should be able to find your real order numbers /
product titles as plain text in the file. If a page is mostly empty `<div>`s and
scripts, Amazon is rendering it client-side and the plugin can't parse it as-is
(see the order-list note below).

## Files

- `mm_shim.lua` — emulates the host. `HTML(content)` returns a NodeSet that is
  both array-like (`result[1]`) and method-bearing (`:xpath/:text/:attr/:each/`
  `:length/:get/:children`). `loadPlugin(path)` loads `amazon-orders.lua` into a
  sandbox (stubbing `MM`/`JSON`/`LocalStorage`/`Connection`/`WebBanking`; `io=nil`
  so it behaves like the signed build) and returns its environment table.
- `test_parse.lua` — deterministic parser assertions over synthetic HTML.
- `selftest.lua` — validates the shim against a synthetic page (no real data).
- `skeleton.py` — stdlib-only HTML structure explorer; prints an indented tree of
  tags/classes/text, skipping `<script>`/`<style>` noise. Handy for
  reverse-engineering a new layout:
  `python3 test/skeleton.py PAGE.html --class order-card --nth 0 --max-depth 8`
- `run.sh` — luajit launcher with module paths set.

## Layout notes (what to watch when Amazon changes things)

- **Order list** (`/your-orders/orders`): order *cards* are encrypted
  client-side, but the order code is plaintext in `data-csa-c-slot-id`. The
  plugin only enumerates codes from the list, then fetches each (plaintext)
  details page. The time-filter `<select name="timeFilter">` and `li.a-last`
  pagination are still plaintext.
- **Order details** (`/your-orders/order-details?orderID=…`): plaintext, with a
  clean `data-component` interface (`orderDate`, `orderId`,
  `purchasedItemsRightGrid` → `itemTitle`/`unitPrice`/`quantity`, the
  `od-line-item-row` totals incl. `Gesamtsumme`, `shippingAddress`,
  `Summe der Erstattung` for refunds). Prefer `data-component` anchors over CSS
  classes — they have been the most stable.
- **Amazon Business SPA**: the shell exposes
  `ab-your-orders-anticsrf-token`; order data can come from the Business API
  response rather than server-rendered cards.
- **Business Analytics reports** (`/b2b/aba/`): tests cover report scheduling,
  status/download responses, rollup JSON pagination, `PAST_12_MONTHS`,
  `CUSTOM_RANGE`, batching and the classic GET year-filter gap path. Synthetic
  fixtures for these surfaces live in `test/fixtures/`.

See `../CLAUDE.md` for the full layout/architecture write-up and
`../docs/superpowers/specs/` for the sub-account and switch-auth designs.

## Constraint

`amazon-orders.lua` must remain a **single self-contained file** to be recognized
by MoneyMoney. The harness loads it and calls its globals; it never splits or
modifies the plugin's structure.
