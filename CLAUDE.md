# CLAUDE.md — Amazon-MoneyMoney plugin

## What this is
A MoneyMoney web-banking extension (`amazon-orders.lua`) that scrapes a user's
Amazon.de order history and exposes it as bank-account transactions. It must
stay a **single, self-contained Lua file** to be recognized by MoneyMoney.
API docs: https://moneymoney.app/api/webbanking/

## Current task (2026-06)
Amazon changed the order-history page layout; the scraper's selectors no longer
match reliably. Goal: update parsing/scraping to the new layout without breaking
the MoneyMoney plugin contract.

## How MoneyMoney runs the plugin (important constraints)
- `HTML(content)` parses with **libxml2's HTML parser + XPath** — no JavaScript
  is executed. So we must target the **raw server HTML** (View Source), NOT the
  browser's post-JS DOM. If a page is client-side rendered, the data won't be in
  the raw HTML and we must find the underlying data/endpoint instead.
- HTML node-set API used by the plugin: `:xpath(q)`, `:text()`, `:attr(name)`,
  `:attr(name,val)` (setter), `:each(fn(index,el))` (1-based), `:length()`,
  `:get(n)` (1-based), `:children()`, `:select(val)`, `:submit()`, `:click()`.
- Signed builds have `io`/`io.open` == nil (no filesystem). Debug/webCache code
  is guarded on `io ~= nil`.

## Scraper architecture (where the layout-specific selectors live)
- `enterOrderList()` (~L1094) — navigate to order history.
- Time/year filter: `const.xpathOrderMonthForm` / `xpathOrderMonthSelect`
  (`<select name="orderFilter|timeFilter">`) (~L91-92, L1574-1609).
- Pagination: `//li[contains(@class,"a-last")]/a[@href]` (~L1596).
- `getOrdersFromSummary(html)` (~L894) — order-list page → order boxes
  (`#ordersContainer`/`.orders-content-container` → `.order` → `.order-info`).
- `getOrderInfosFromSummaryHeader()` (~L600) — header values read from
  `span.a-color-secondary.value` (3/4/5 = customer/business account shapes).
- `getArticleFromShipment()` (~L716) — item rows `.a-fixed-left-grid-inner`,
  qty `span.item-view-qty`.
- `getOrderDetails(order)` (~L860) — detail page `#orderDetails`, subtotals
  `#od-subtotals`, shipments `.a-box.shipment`, returns `#od-returns-panel`,
  refund rows `.a-color-success`.
- Price/date/qty/orderCode helpers: `getPrice`/`getDate`/`getQty`/`getOrderCode`
  (~L530-586). Order-code regex: `[D%d]%d%d-%d%d%d%d%d%d%d-%d%d%d%d%d%d%d`.
  Prices: new `€(%d+),(%d%d)`, old `EUR (%d+),(%d%d)`.

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
  OLD-layout page; passes. Proves the shim + sandbox loading works.
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
- DONE & tested (test/test_parse.lua, 5 pages, all pass): list enumeration,
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
- STILL PENDING: business account (poNumber/orderedMerchant not wired) needs a
  sample; per-item partial refund detail; refund date approximated by order date.
- Minor: address `<br>` between street and city yields "Chattenweg 4Hünfeld"
  (no space). Cosmetic (endToEndReference only).
- FIXED (2026-07, from a user-reported MoneyMoney log): `getMessageList()`
  (~L1086, checks Amazon's message center to flag orders needing a rescan)
  crashed the whole run. New `/gp/message` layout no longer has the
  `script[@type contains "a-state"]` it read the ajaxToken from, so
  `ajaxToken` came back `nil` — but the old `if ajaxToken ~= "" then` check
  let it fall through anyway into a hardcoded fallback URL that literally sent
  `token=stateData.token` (a JS placeholder, never a real token) to
  `/gp/msg/cntr/message-list/`. That 404'd, which the MoneyMoney host turns
  into a fatal, run-aborting error. Fix: bail out and return no orders when
  ajaxToken is missing, and removed the dead stateData.token fallback in
  `getMessageListURL`/`getMessageURL`/`getMessageList` (it never worked).
  Covered by `test/test_messagelist.lua`.
