-- Named extras instead of "Difference (shipping costs, coupon etc.)".
-- Unbilled cancellations must not create bookings.
-- Run: test/run.sh test/test_summary_adjustments.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local ENGLISH_DIFF = "Difference (shipping costs, coupon etc.)"

local function parseHtml(html)
  env.connectShopWithCheck = function() return mm.HTML(html) end
  local order = {
    orderCode = "303-8179986-7068357",
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
    accountNumber = "mix",
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

local function findByName(txs, name)
  for _, tx in ipairs(txs) do
    if tx.name == name then
      return tx
    end
  end
  return nil
end

------------------------------------------------------------------ CANCEL
print("== unbilled cancellation is not booked ==")
do
  local order = parseHtml([[
<div id="orderDetails">
  <div data-component="orderDate">22. Juni 2026</div>
  <div data-component="shipmentStatus">
    <h4 class="od-status-message"><span>Storniert</span></h4>
    <div class="od-status-message">Deine Bestellung wurde storniert. Diese Bestellung wurde dir nicht in Rechnung gestellt.</div>
  </div>
  <div data-component="purchasedItemsRightGrid">
    <div data-component="itemTitle">Dr. Becher Urinstein Entferner WC-Reiniger 1532000-750ml</div>
    <div data-component="unitPrice"><span class="a-offscreen">EUR 6,70</span></div>
  </div>
</div>
]])
  assert(order.unbilledCancel == true, "unbilled cancel must be flagged")
  assert(order.orderSum == 670, "unbilled cancel keeps item sum for optional Storno, got " .. tostring(order.orderSum))
  assert(#(order.orderPositions or {}) == 1, "unbilled cancel keeps positions for optional Storno")
  local txs = emitMix(order)
  assert(#txs == 0, "unbilled cancel must emit no purchase lines, got " .. names(txs))
  assert(math.abs(env.orderRealAmount(order, -100)) < 0.001, "unbilled cancel ledger amount is 0")

  env.applyAccountAttribute("keepStorno", "true")
  local kept = emitMix(order)
  env.applyAccountAttribute("keepStorno", "false")
  local item = findByName(kept, "Dr. Becher Urinstein Entferner WC-Reiniger 1532000-750ml")
  local storno = findByName(kept, "Storno")
  assert(item ~= nil, "keepStorno unbilled must emit item, got " .. names(kept))
  assert(storno ~= nil, "keepStorno unbilled must emit Storno, got " .. names(kept))
  assert(math.abs(item.amount + storno.amount) < 0.001, "item+Storno must net to 0")
end

------------------------------------------------------------------ SHIPPING
print("== Verpackung & Versand from summary, not English Difference ==")
do
  local order = parseHtml([[
<div id="orderDetails">
  <div data-component="orderDate">20. Juli 2026</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Heizkörper Reflexionstapeten</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 6,57</span></div>
    </div>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Zwischensumme:</span>
    <span class="od-line-item-row-content">EUR 5,52</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Verpackung &amp; Versand:</span>
    <span class="od-line-item-row-content">EUR 13,40</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Anzurechnende MwSt.:</span>
    <span class="od-line-item-row-content">EUR 3,60</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 22,52</span>
  </div>
</div>
]])
  assert(order.orderTotal == 2252, "orderTotal 22,52, got " .. tostring(order.orderTotal))
  assert(order.orderSum == 657, "item stays incl. USt 6,57, got " .. tostring(order.orderSum))
  local txs = emitMix(order)
  for _, tx in ipairs(txs) do
    assert(tx.name ~= ENGLISH_DIFF, "must not use English difference name")
    assert(not (tx.name or ""):find("MwSt", 1, true), "must not emit MwSt booking, got " .. names(txs))
    assert(not (tx.name or ""):find("USt", 1, true), "must not emit USt booking, got " .. names(txs))
    assert(tx.name ~= "Bestelldifferenz", "must not emit Bestelldifferenz")
  end
  local item = nil
  for _, tx in ipairs(txs) do
    if type(tx.name) == "string" and tx.name:find("Reflexionstapeten", 1, true) then
      item = tx
    end
  end
  assert(item ~= nil, "must emit item incl. USt, got " .. names(txs))
  assert(math.abs(item.amount - (-6.57)) < 0.001, "item incl. USt 6,57, got " .. tostring(item.amount))
  local ship = findByName(txs, "Verpackung & Versand")
  assert(ship ~= nil, "must emit Verpackung & Versand, got " .. names(txs))
  assert(math.abs(ship.amount - (-13.40)) < 0.001, "Versand 13,40, got " .. tostring(ship.amount))
end

------------------------------------------------------------------ COUPON
print("== Werbeaktion credit from summary ==")
do
  local order = parseHtml([[
<div id="orderDetails">
  <div data-component="orderDate">20. Dezember 2025</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Artikel A</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 33,97</span></div>
    </div>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Zwischensumme:</span>
    <span class="od-line-item-row-content">EUR 33,97</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Werbeaktion:</span>
    <span class="od-line-item-row-content">-EUR 1,82</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 32,15</span>
  </div>
</div>
]])
  local txs = emitMix(order)
  for _, tx in ipairs(txs) do
    assert(tx.name ~= ENGLISH_DIFF, "must not use English difference name")
  end
  local promo = findByName(txs, "Werbeaktion")
  assert(promo ~= nil, "must emit Werbeaktion, got " .. names(txs))
  assert(math.abs(promo.amount - 1.82) < 0.001, "Werbeaktion is a 1,82 credit, got " .. tostring(promo.amount))
end

------------------------------------------------------------------ GUTSCHEIN LABEL
print("== Gutschein eingelöst keeps Amazon label ==")
do
  local order = parseHtml([[
<div id="orderDetails">
  <div data-component="orderDate">20. Dezember 2025</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Artikel B</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 20,86</span></div>
    </div>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Gutschein eingelöst:</span>
    <span class="od-line-item-row-content">EUR 2,32</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 18,54</span>
  </div>
</div>
]])
  local txs = emitMix(order)
  local coupon
  for _, tx in ipairs(txs) do
    if (tx.name or ""):find("Gutschein", 1, true) then
      coupon = tx
      break
    end
  end
  assert(coupon ~= nil, "must emit Gutschein, got " .. names(txs))
  assert(math.abs(coupon.amount - 2.32) < 0.001, "Gutschein is a 2,32 credit, got " .. tostring(coupon.amount))
end

------------------------------------------------------------------ BUSINESS GROSS ITEMS, NO VAT LINE
print("== Business: item prices incl. USt, no MwSt or Bestelldifferenz ==")
do
  local order = parseHtml([[
<div id="orderDetails">
  <div data-component="orderDate">22. Juli 2026</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Seac Extreme 50</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 22,49</span></div>
    </div>
  </div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Seac Extreme Glaeser</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 45,33</span></div>
    </div>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Zwischensumme:</span>
    <span class="od-line-item-row-content">EUR 56,99</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Gesamt vor USt.:</span>
    <span class="od-line-item-row-content">EUR 56,99</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Geschätzte USt.:</span>
    <span class="od-line-item-row-content">EUR 8,04</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 65,03</span>
  </div>
</div>
]])
  assert(order.orderSum == 6782, "items stay incl. USt 67,82, got " .. tostring(order.orderSum))
  local txs = emitMix(order)
  assert(#txs == 2, "only the two items, got " .. names(txs))
  for _, tx in ipairs(txs) do
    assert(not (tx.name or ""):find("USt", 1, true), "must not emit USt, got " .. names(txs))
    assert(not (tx.name or ""):find("MwSt", 1, true), "must not emit MwSt, got " .. names(txs))
    assert(tx.name ~= "Bestelldifferenz", "must not emit Bestelldifferenz")
  end
  local mask, glasses
  for _, tx in ipairs(txs) do
    if (tx.name or ""):find("50", 1, true) then mask = tx end
    if (tx.name or ""):find("Glaeser", 1, true) then glasses = tx end
  end
  assert(mask ~= nil and math.abs(mask.amount - (-22.49)) < 0.001, "mask 22,49 incl. USt")
  assert(glasses ~= nil and math.abs(glasses.amount - (-45.33)) < 0.001, "glasses 45,33 incl. USt")
end

------------------------------------------------------------------ CACHE FALLBACK
print("== cached order without extras has no Bestelldifferenz ==")
do
  local order = {
    orderCode = "303-0000000-0000001",
    orderPositions = { { purpose = "Item", amount = 1000, qty = 1 } },
    orderSum = 1000,
    orderTotal = 1120,
    bookingDate = os.time({ year = 2026, month = 6, day = 22 }),
  }
  local txs = emitMix(order)
  assert(findByName(txs, ENGLISH_DIFF) == nil, "must not use English difference")
  assert(findByName(txs, "Bestelldifferenz") == nil, "must not emit Bestelldifferenz")
  assert(#txs == 1, "only the item line, got " .. names(txs))
  assert(math.abs(txs[1].amount - (-10.00)) < 0.001, "item 10,00 incl. tax, got " .. tostring(txs[1].amount))
end

print("test_summary_adjustments OK")
