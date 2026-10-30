-- Summary rows must only be booked when they explain the gap between items and order total.
-- Run: test/run.sh test/test_summary_reconciles_to_total.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local function parseHtml(html)
  local page = html:gsub('<div id="orderDetails">',
    '<div id="orderDetails">\n  <div data-component="orderDate">20. Juli 2026</div>', 1)
  env.connectShopWithCheck = function() return mm.HTML(page) end
  local order = {
    orderCode = "303-0000000-0000001",
    orderPositions = {},
    orderSum = 0,
    orderTotal = 0,
    refund = 0,
    bookingDate = 0,
    detailsDate = 0,
  }
  env.getOrderDetails(order)
  return order
end

local function emitMix(order)
  local ctx = {
    mixed = true,
    divisor = -100,
    transactions = {},
    accountNumber = "test@example.com",
  }
  env.emitPurchaseLines(ctx, order, order.orderCode)
  return ctx.transactions
end

local function names(txs)
  local out = {}
  for _, tx in ipairs(txs) do
    table.insert(out, tx.name)
  end
  return table.concat(out, " | ")
end

local function itemRow(title, price)
  return string.format([[
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">%s</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR %s</span></div>
    </div>
  </div>]], title, price)
end

local function summaryRow(label, price)
  return string.format([[
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">%s</span>
    <span class="od-line-item-row-content">%s</span>
  </div>]], label, price)
end

------------------------------------------------------------------ items already equal the total
print("== shipping and voucher are not booked when items equal the order total ==")
do
  local order = parseHtml("<div id=\"orderDetails\">\n"
    .. itemRow("Artikel A", "14,99") .. "\n"
    .. itemRow("Artikel B", "18,95") .. "\n"
    .. itemRow("Artikel C", "8,99") .. "\n"
    .. summaryRow("Zwischensumme:", "EUR 39,10") .. "\n"
    .. summaryRow("Verpackung &amp; Versand:", "EUR 4,45") .. "\n"
    .. summaryRow("Gutschein eingelöst:", "-EUR 4,99") .. "\n"
    .. summaryRow("Gesamtsumme:", "EUR 42,93") .. "\n"
    .. "</div>")
  assert(order.orderSum == 4293, "item sum must be 42.93, got " .. tostring(order.orderSum))
  assert(order.orderTotal == 4293, "order total must be 42.93, got " .. tostring(order.orderTotal))
  local txs = emitMix(order)
  assert(#txs == 3, "expected only the three items, got " .. #txs .. ": " .. names(txs))
  for _, tx in ipairs(txs) do
    assert(not tx.name:find("Versand", 1, true) and not tx.name:find("Gutschein", 1, true),
      "summary row must not be booked: " .. names(txs))
  end
end

------------------------------------------------------------------ total rows are not bookings
print("== Gesamtbetrag rows are totals, not bookings ==")
do
  local order = parseHtml("<div id=\"orderDetails\">\n"
    .. itemRow("Artikel D", "10,00") .. "\n"
    .. summaryRow("Gesamtbetrag vor Steuern:", "EUR 8,40") .. "\n"
    .. summaryRow("MwSt:", "EUR 1,60") .. "\n"
    .. summaryRow("Gesamtbetrag für diese Bestellung:", "EUR 10,00") .. "\n"
    .. "</div>")
  local txs = emitMix(order)
  assert(#txs == 1, "expected only the item, got " .. names(txs))
  assert(not names(txs):find("Gesamtbetrag", 1, true), "Gesamtbetrag must not be booked: " .. names(txs))
end

------------------------------------------------------------------ genuine shipping still booked
print("== shipping that the total does include is still booked ==")
do
  local order = parseHtml("<div id=\"orderDetails\">\n"
    .. itemRow("Artikel E", "40,00") .. "\n"
    .. summaryRow("Verpackung &amp; Versand:", "EUR 4,99") .. "\n"
    .. summaryRow("Gesamtsumme:", "EUR 44,99") .. "\n"
    .. "</div>")
  local txs = emitMix(order)
  assert(#txs == 2, "expected item and shipping, got " .. names(txs))
  local shipping = nil
  for _, tx in ipairs(txs) do
    if tx.name:find("Versand", 1, true) then
      shipping = tx
    end
  end
  assert(shipping ~= nil, "shipping must be booked when the total includes it: " .. names(txs))
end

------------------------------------------------------------------ zero-net orders are hidden
print("== an order that nets to 0 EUR emits nothing ==")
do
  local order = parseHtml("<div id=\"orderDetails\">\n"
    .. itemRow("Artikel F", "10,00") .. "\n"
    .. summaryRow("Werbeaktionen:", "-EUR 10,00") .. "\n"
    .. summaryRow("Gesamtsumme:", "EUR 0,00") .. "\n"
    .. "</div>")
  local txs = emitMix(order)
  assert(#txs == 2, "expected item and promotion before the zero-net check, got " .. names(txs))
  assert(env.dropZeroNetOrderTransactions(txs, 1) == true, "zero-net order must be dropped")
  assert(#txs == 0, "no transactions may remain for a zero-net order, got " .. names(txs))
end

print("== an order that does not net to 0 EUR keeps its lines ==")
do
  local order = parseHtml("<div id=\"orderDetails\">\n"
    .. itemRow("Artikel G", "10,00") .. "\n"
    .. summaryRow("Werbeaktionen:", "-EUR 9,50") .. "\n"
    .. summaryRow("Gesamtsumme:", "EUR 0,50") .. "\n"
    .. "</div>")
  local txs = emitMix(order)
  assert(#txs == 2, "expected item and promotion, got " .. names(txs))
  assert(env.dropZeroNetOrderTransactions(txs, 1) == false, "order with 0.50 EUR left must stay")
  assert(#txs == 2, "lines must remain, got " .. names(txs))
end

print("test_summary_reconciles_to_total: OK")
