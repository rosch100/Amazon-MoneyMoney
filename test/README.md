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
./test/run.sh test/test_parse.lua   # real tests against pages in test/pages/
```

`test/run.sh <script.lua>` just sets `PATH` + the luarocks 5.1 module paths and
runs the script under `luajit`. You can point it at any Lua script.

## Providing test pages

`test/test_parse.lua` reads HTML files from `test/pages/` (gitignored — they
contain personal data and are never committed). The expected files are named per
scenario, e.g. `list.html`, `details-single.html`, `details-multi.html`,
`details-multi-with-refund.html`, `details-digital.html`, `details-giftcard.html`.

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
- `test_parse.lua` — the actual assertions over `test/pages/`.
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

See `../CLAUDE.md` for the full layout/architecture write-up.

## Constraint

`amazon-orders.lua` must remain a **single self-contained file** to be recognized
by MoneyMoney. The harness loads it and calls its globals; it never splits or
modifies the plugin's structure.
