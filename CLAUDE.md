# CLAUDE.md — Amazon-MoneyMoney plugin

## What this is
A MoneyMoney web-banking extension (`amazon-orders.lua`) that scrapes a user's
Amazon.de order history and exposes it as bank-account transactions. It must
stay a **single, self-contained Lua file** to be recognized by MoneyMoney.
API docs: https://moneymoney.app/api/webbanking/

## Current state
The 2024+ order-history layout migration is implemented and covered by the
offline tests. This fork additionally supports Amazon sub-accounts, Amazon
Business Analytics reports, resumable initial sync, round-robin harvesting,
detail rescans and explicit incomplete-refresh transactions.

## How MoneyMoney runs the plugin (important constraints)
- `HTML(content)` parses with **libxml2's HTML parser + XPath** — no JavaScript
  is executed. So we must target the **raw server HTML** (View Source), NOT the
  browser's post-JS DOM. If a page is client-side rendered, the data won't be in
  the raw HTML and we must find the underlying data/endpoint instead.
- Amazon serves the response bytes as UTF-8 even when an individual page has a
  stale legacy charset hint. All Amazon HTML therefore goes through
  `parseAmazonHtml(content)`, which explicitly selects UTF-8 before XPath
  extraction.
- HTML node-set API used by the plugin: `:xpath(q)`, `:text()`, `:attr(name)`,
  `:attr(name,val)` (setter), `:each(fn(index,el))` (1-based), `:length()`,
  `:get(n)` (1-based), `:children()`, `:select(val)`, `:submit()`, `:click()`.
- Signed builds have `io`/`io.open` == nil (no filesystem). Debug/webCache code
  is guarded on `io ~= nil`.

## Scraper architecture (where the layout-specific selectors live)
- `enterOrderList()` — navigate to the classic or retail order history.
- Time/year filter: `const.xpathOrderMonthForm` / `xpathOrderMonthSelect`
  (`<select name="orderFilter|timeFilter">`).
- `scanOrderFilterPages()` / `collectOrdersFromOrderList()` — filter and
  pagination orchestration. Pagination uses
  `//li[contains(@class,"a-last")]/a[@href]`.
- `getOrdersFromSummary(html)` — enumerate order codes from
  `div.order-card` / `data-csa-c-slot-id`; encrypted card bodies are not parsed.
- `getOrderDetails(order)` — parse the plaintext `#orderDetails` page via
  `data-component` anchors (`orderDate`, `purchasedItemsRightGrid`,
  `shippingAddress`) plus `getPositionsFromDetails`, `getTotalsFromDetails` and
  `getRefundFromDetails`.
- `collectBusinessSpaOrders()` — Business-SPA/ABA route with classic GET
  year-filter coverage for full-harvest gaps.
- `fetchAbaRollupTable()` / `takeAbaFullHarvestJobBatch()` — paginated,
  resumable Amazon Business Analytics report harvesting.
- Price/date/qty/orderCode helpers: `getPrice`/`getDate`/`getQty`/`getOrderCode`
  Order-code regex: `[D%d]%d%d-%d%d%d%d%d%d%d-%d%d%d%d%d%d%d`.
  Prices: new `€(%d+),(%d%d)`, old `EUR (%d+),(%d%d)`.

The former summary-header/shipment parsers and message-center scraper are not
part of the current architecture.

## Offline test harness (built, working)
- Runtime: LuaJIT 2.1 + xmlua (libxml2 binding), installed via Homebrew +
  `luarocks --lua-version=5.1 install xmlua`. Rocks live in `~/.luarocks`.
- `test/run.sh <script.lua>` — wrapper that sets PATH + luarocks 5.1 module
  paths and runs the script under luajit. Use this to run any harness script.
- `test/mm_shim.lua` — emulates MoneyMoney's host: `HTML()` returning a
  NodeSet (array-like AND method-bearing) with `:xpath/:text/:attr/:each/`
  `:length/:get/:children`, plus `loadPlugin(path)` which loads
  `amazon-orders.lua` into a sandboxed env (stubs MM/JSON/LocalStorage/
  Connection/WebBanking; io=nil so it behaves like the signed build) and
  returns the env so tests can call its globals (e.g. `getOrdersFromSummary`).
- `test/selftest.lua` — runs the real `getOrdersFromSummary` against a synthetic
  2024+ order-card page; passes. Proves the shim + sandbox loading works.
- `test/pages/` — drop saved raw HTML pages here (named per scenario).
- The Lua file must stay single-file for MoneyMoney; the harness loads it and
  calls its global functions rather than modifying its structure.
- xmlua `node:search(q)` mirrors libxml2 XPath; `//x` is doc-absolute even from
  a context node, `.//x` / `./x` are relative — same as MoneyMoney.

## New layout findings (2026-06, from saved pages in test/pages/)
- **Order list** `/your-orders/orders?timeFilter=year-YYYY&startIndex=N`:
  - Order cards are `div.order-card.js-order-card`; the **card body is encrypted
    client-side** (Siege CSD, `div.csd-encrypted-sensitive`). MoneyMoney can't
    decrypt it. BUT the order code is plaintext in
    `data-csa-c-slot-id="amzn1.yourorders.order-card.<ORDERCODE>"`.
  - Escape hatch exists: appending `disableCsd=no-js` to the URL makes the server
    return plaintext cards — currently NOT used (we fetch details instead).
  - Time filter still `select[name="timeFilter"]#time-filter` in
    `form.js-time-filter-form` (action `/your-orders/orders`) — existing
    xpathOrderMonthForm/Select selectors still match. Options: `last30`,
    `months-3`, `year-YYYY`.
  - Pagination: `ul.a-pagination li.a-last a[href]` (startIndex steps of 10) —
    existing selector still matches.
- **Order details** page (title "Bestelldetails"), still has `div#orderDetails`,
  now PLAINTEXT with a clean `data-component` interface:
  - `orderDate` ("20. Dezember 2025"), `orderId` ("304-…").
  - Items: each `div[data-component="purchasedItemsRightGrid"]` holds sibling
    `itemTitle`, `unitPrice` (price in `span.a-offscreen`, e.g. "169,98€"),
    `quantity` (this component is ALWAYS empty), `orderedMerchant`. The real
    quantity for qty>1 is a badge over the image: `div.od-item-view-qty > span`
    in the item's left grid (read via ancestor `a-fixed-left-grid-inner`).
    `unitPrice` is the PER-ITEM price, so the line total = unitPrice * qty.
  - Totals: `div.od-line-item-row` rows with `.od-line-item-row-label` /
    `.od-line-item-row-content`. Grand total = **Gesamtsumme** (bold, last row);
    e.g. multi: items 33,97 − coupon 1,82 = Gesamtsumme 32,15.
  - Address: `div[data-component="shippingAddress"]` → `<li>` lines.
  - **Price format changed**: currency now AFTER amount ("169,98€" / "169,98 €")
    and the totals use a non-breaking space (`&#160;` = UTF-8 `\194\160`).
    getPrice now has regexPriceEur + nbsp normalization.

## Architecture change
Old: list page provided per-order date/total/items; details fetched lazily.
New: list cards are encrypted, so getOrdersFromSummary only **enumerates order
codes** (from slot-id) with detailsDate=0; getOrderDetails fetches each order's
plaintext details page and fills date/total/items/address. Caching unchanged, so
repeat runs stay fast. detailsUrl built via const.orderDetailsUrl + code.

## Status / TODO
- DONE & tested (`test/test_parse.lua`, seven parser scenarios): list enumeration,
  single/multi-item detail parsing, totals incl. coupon difference, address,
  price format + nbsp, REFUND, DIGITAL order, GIFT CARD.
- CONFIRMED: order-details URL = `/your-orders/order-details?orderID=<code>`
  (set as const.orderDetailsUrl; legacy /gp/css/... paths 301-redirect here;
  overridable via the `orderDetailsUrl` account-settings attribute).
- Refunds: 2024+ layout keeps all items in the summary and adds a
  "Summe der Erstattung" od-line-item-row. getRefundFromDetails reads that amount
  and books it as a refundTransaction on the ORDER date (no refund date is in the
  DOM). getTotalsFromDetails skips "Erstattung" rows so a refund can't be taken
  for the grand total. Legacy getReturnsFromDetails/getRefundTransActions
  (od-returns-panel / a-color-success) are no longer called.
- Digital orders (D01-) and gift cards parse via the same generic detail path
  (no special URL); gift cards have no shippingAddress, which is fine.
- Return detection (`orderDetailsHasReturnActivity` / `isReturnedOrderItemRow`)
  keys on return-*status* links (`href` contains `returns/status` /
  `return-status`) or "Rücksendung"/"Erstattung" text, NOT the generic
  "Rückgabe oder Widerruf" CTA (`/spr/returns/cart`) which every delivered order
  carries during its return window. A false positive there makes
  `getSummaryExtrasFromDetails` drop credit rows — e.g. the Amazon-Warehouse
  ("Retourenkauf") ~20% checkout discount that shows as a "Gutschein eingelöst"
  od-line-item-row. Covered by `test/test_warehouse_voucher.lua`.
- Business harvesting through ABA, Business SPA and classic GET gap coverage is
  implemented. `poNumber` / `orderedMerchant` are not mapped to transactions.
  Per-item partial refund detail remains unavailable; the aggregate refund date
  is approximated by the order date because Amazon does not expose it here.
- Minor: address `<br>` between street and city yields "Beispielweg 1Musterstadt"
  (no space). Cosmetic (endToEndReference only).
- The message-center scraper (`getMessageList` and related URL helpers) was
  removed. Refund/return rescans are now queued from harvest/ABA reappearance
  and `scheduleIncrementalRefundWatch`; `test/test_messagelist.lua` asserts
  that the obsolete API remains absent.

## Fork orchestration
- `InitializeSession2` discovers available personal/business sub-accounts.
  `ListAccounts` always emits the internal account `mix`; when both kinds were
  discovered, its visible name combines the unchanged Amazon labels in
  personal/business order. `sub:personal` / `sub:business` are then added
  without harvesting transactions.
- Initial sync starts after the account-setup session and persists progress in
  `LocalStorage`. The combined account advances sub-account batches round-robin.
- Full Business history uses `PAST_12_MONTHS` plus `CUSTOM_RANGE` jobs in
  batches of six per refresh. Rollup pagination is resumable.
- `AMAZON-INCOMPLETE-HARVEST` is emitted only for an incomplete scan/report or
  truncated/failed due-detail batch, never during account setup.
- After a completed initial full harvest, incremental refreshes use cutoff
  `max(MoneyMoney since, newest OrderCache bookingDate) − 14 days` for list/filter
  scan width. Refund/return detail re-checks are limited to emitted orders in the
  last **90 days**, skipping `unbilledCancel` and fully settled refunds; scheduled
  `detailsDate` in the future is still respected.
- Incremental session optimizations: reuse complete `discoveredSubAccounts` without
  opening the account switcher; skip list harvest (and switches) when the last list
  scan wall-clock (`lastListHarvestAt`) is still within `incrementalListMinRescanSec`
  (default 4h) and only details are due — including after re-login;
  `lastHarvestSince` remains the MoneyMoney since watermark. With a 1-month scan
  window skip `months-3` / „letzten 3 Monaten“; Business incremental goes straight
  to ABA (no SPA order-history probes); skip `ensureAmazonSubAccountSession` when
  the current HTML already matches the kind.
- Cancelled order-details SSR stubs without `orderDate` (banner only) are
  completed so they do not keep the details queue due; `unbilledCancel` is set
  only when the stub states the cancel was not billed.
  Unloadable detail shells schedule a rescan delay instead of staying
  immediately due. Business `fullHarvest` GET year filters that stay SPA-unready
  are abandoned without sticky-marking incomplete on not-ready years; when no
  year is ready, sticky incomplete is cleared.
- Akamai interstitials prefer the meta-refresh `bm-verify` GET first; POST
  `/_sec/verify` is only used if the refresh still leaves an interstitial
  (MoneyMoney may abort the session on HTTP 400 from that POST).
- Login response failures are transient unless Amazon explicitly rejects the
  credentials; transient errors preserve persisted cookies.
