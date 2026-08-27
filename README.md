# Amazon Plugin for MoneyMoney

Repository: https://github.com/rosch100/Amazon-MoneyMoney

## Installation
You can get the signed version from https://moneymoney-app.com/extensions/amazon-orders.lua. The unsigned [latest](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-orders.lua) version is available from this repository.

To activate the extension, copy the file into `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions`. If you have cloned this repository you can use the `link_ext.sh` script in a shell. A restart is not required, it will load automatically. You can verify installation using *Window → Log*.

**Look out:** MoneyMoney only runs unsigned plugins in the **beta version** and you need to **disable signature check** in the extentsion settings.

## Usage
After installation go to *Add new account* → *Others* → *Amazon Orders*. There are a few different account types:
* **Normal**: List your spendings like a normal bank account: Purchases are negative, refunds and bonuses are positive.
* **Inverted**: Like a normal account, but inverted: Purchases are positive, refunds and bonuses are negative.
* **Mix**: Purchases, refunds and returns as real bookings. One pending **Amazon Ausgleich** (month-end date, `booked=false`) keeps the account at zero. Reported `balance` is 0. MoneyMoney lists these as **Sonstige** accounts excluded from sidebar total wealth (`withTotalSum=false`), overview bar chart (`showDailyBalance=false`), and evaluation diagrams (`showInDiagrams=false`).

### Upgrade from older plugin versions

This version does **not** migrate existing MoneyMoney bookings. After updating the extension:

1. In MoneyMoney: delete **all** transactions on every Amazon account (mix and sub-accounts).
2. Right-click each Amazon account → settings → notes → set `resetCache` to a new value (e.g. today's date).
3. Refresh the account once. The status line explains if a full reimport is still required.

Until step 2–3 are done, the plugin blocks new imports to avoid duplicate or inconsistent bookings.

**Sidebar total wealth (Gesamtsumme) and default transaction view:** New and re-discovered accounts get `withTotalSum=false`, `showInDiagrams=false`, `showDailyBalance=false`, and `perspective={chart=1}` from `ListAccounts` (`chart=1` = *Ansicht → Liste*, ⌘1; `2` = Balkendiagramm, `3` = Tortendiagramm). **Existing accounts must be updated via *Bankzugang → Nach neuen Konten suchen*** so MoneyMoney picks up `perspective`, account type *Sonstige*, and the other flags. If the bar chart still opens by default, switch *Ansicht → Liste* once or disable *Balkendiagramm anzeigen* under *Konto → Einstellungen* (separate from the *Tagessaldo* toggle in the transaction list).

### First import (Erstimport) and sub-accounts

Unlike the [original Amazon plugin](https://github.com/Michael-Beutling/Amazon-MoneyMoney) (one shared cache, dummy *“Please reload!”* on the very first refresh only), this fork supports **personal + business** sub-accounts:

1. **Account finder** (*Konten werden gesucht*): no bookings are loaded (`Konten einrichten: keine Umsätze laden`).
2. **First refresh after setup** (`since=0`): full order history harvest + up to 250 order details per run.
3. **Repeat refresh** until the status line no longer shows incomplete sub-account fetch or open order details, and until the dummy booking *“Es sind noch weitere Bestellungen offen…”* no longer appears.
4. When you refresh **Amazon Business** (`sub:business`), that business identity is harvested **first** (ABA reports + order list), not the personal account.

Business history uses Amazon Business Analytics in 12-month batches (several refreshes may be needed for orders older than 12 months).

* **Monthly**: Negative bookings for each purchase. A monthly positive counter booking to zero out the account.
* **Yearly**: Negative bookings for each purchase. A yearly postitive counter booking to zero out the account.

Normal refreshes import new Amazon orders automatically (keyed by Bestellnummer). No notes or second “reload” click are required. During incremental refreshes, already-imported orders from the last 366 days are re-checked for refunds and returns (without the old message-center scrape).

## Optional notes (account settings)
Only needed for troubleshooting. In MoneyMoney right-click the account → settings → notes.

`ListAccounts` registers the note fields (`resetCache`, `blacklistOrders`, `rescanOrder`, `keepStorno`) with **default values** when you add or re-discover accounts (empty strings / `keepStorno=false`). **Existing accounts** need *Bankzugang → Nach neuen Konten suchen* once so MoneyMoney picks up the defaults; a normal refresh does not change the Notes table.

| Attribute | Purpose |
|-----------|---------|
| `resetCache` | After this plugin version: required once (change the value, e.g. today's date) following a full delete of the Amazon account’s transactions. Also used later to clear the order cache and re-read history on the **same** refresh. |
| `blacklistOrders` | Comma-separated order numbers to skip when details fail. |
| `rescanOrder` | Single order number to force re-fetch of details. |
| `keepStorno` | `true`: keep booking and matching Storno (full refund, full return, unbilled cancellation, partial return). Default: `false`. Already imported bookings cannot be deleted; a later full refund is still imported. |

![](moneymoney_settings.png)

## Performance
The script caches some data, but the first time it scrapes your whole order history. In facts ~10 years of shopping with about 230 orders with 340 positions takes 12 minutes in the first run! The second run needs 2 minutes. After that all data is cached so a normal run needs 20-30 seconds.

## Warranty
Nope, no warranty! When the script orders 10 tons of dog food every day, it's your problem!
