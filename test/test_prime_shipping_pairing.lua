-- Prime shipping refunds: a shipping row and a "Gutschein eingelöst" voucher that cancel out
-- (net or gross at 19 % or 7 % VAT) are not booked, also in return orders. Other vouchers stay.
-- Run: test/run.sh test/test_prime_shipping_pairing.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local function fixture(rows, itemPriceText)
  local parts = {
    '<div id="orderDetails">',
    '<div data-component="orderDate">20. Dezember 2025</div>',
  }
  if itemPriceText then
    parts[#parts + 1] = '<div class="a-fixed-left-grid-inner">'
      .. '<div data-component="purchasedItemsRightGrid">'
      .. '<div data-component="itemTitle">Testartikel</div>'
      .. '<div data-component="unitPrice"><span class="a-offscreen">' .. itemPriceText .. '</span></div>'
      .. '</div></div>'
  end
  for _, row in ipairs(rows) do
    parts[#parts + 1] = '<div class="od-line-item-row">'
      .. '<span class="od-line-item-row-label">' .. row[1] .. '</span>'
      .. '<span class="od-line-item-row-content">' .. row[2] .. '</span></div>'
  end
  parts[#parts + 1] = "</div>"
  return table.concat(parts, "\n")
end

local function parseOrder(rows, itemPriceText)
  local html = fixture(rows, itemPriceText)
  env.connectShopWithCheck = function() return mm.HTML(html) end
  local order = {
    orderCode = "303-0000000-0000001",
    orderPositions = {},
    orderSum = 0,
    orderTotal = 0,
    refund = 0,
    bookingDate = 0,
    detailsDate = 0,
  }
  assert(env.getOrderDetails(order) == true, "order details must parse")
  return order
end

local function emitMix(order)
  local ctx = { mixed = true, divisor = -100, transactions = {}, accountNumber = "test@example.com" }
  env.emitPurchaseLines(ctx, order, order.orderCode)
  return ctx.transactions
end

local function findByName(txs, name)
  for _, tx in ipairs(txs) do
    if tx.name == name then
      return tx
    end
  end
  return nil
end

local function countNamed(txs, name)
  local count = 0
  for _, tx in ipairs(txs) do
    if tx.name == name then
      count = count + 1
    end
  end
  return count
end

local SHIPPING = "Verpackung &amp; Versand:"
local VOUCHER = "Gutschein eingelöst:"

print("== pair matching: net or gross at 19 % and 7 % ==")
do
  assert(env.shippingVoucherAmountsMatch(420, -420), "identical net amounts match")
  assert(env.shippingVoucherAmountsMatch(420, -500), "4,20 net shipping = 5,00 gross voucher at 19 %")
  assert(env.shippingVoucherAmountsMatch(500, -420), "5,00 gross shipping = 4,20 net voucher at 19 %")
  assert(env.shippingVoucherAmountsMatch(420, -449), "4,20 net shipping = 4,49 gross voucher at 7 %")
  assert(env.shippingVoucherAmountsMatch(449, -420), "4,49 gross shipping = 4,20 net voucher at 7 %")
  assert(not env.shippingVoucherAmountsMatch(420, -460), "no statutory rate yields 4,60")
  assert(not env.shippingVoucherAmountsMatch(419, -554), "4,19 shipping does not cancel a 5,54 coupon")
  assert(not env.shippingVoucherAmountsMatch(0, -500), "zero shipping never pairs")
end

print("== Prime voucher at 19 % gross: shipping and voucher omitted ==")
do
  local order = parseOrder({ { SHIPPING, "EUR 4,20" }, { VOUCHER, "-EUR 5,00" } })
  local txs = emitMix(order)
  assert(countNamed(txs, "Verpackung & Versand") == 0, "covered shipping must not be booked")
  assert(countNamed(txs, "Gutschein eingelöst") == 0, "covering voucher must not be booked")
end

print("== Prime voucher at 7 % gross: shipping and voucher omitted ==")
do
  local order = parseOrder({ { SHIPPING, "EUR 4,20" }, { VOUCHER, "-EUR 4,49" } })
  local txs = emitMix(order)
  assert(countNamed(txs, "Verpackung & Versand") == 0, "7 % covered shipping must not be booked")
  assert(countNamed(txs, "Gutschein eingelöst") == 0, "7 % covering voucher must not be booked")
end

print("== return order: Prime refund of shipping is omitted too ==")
do
  local order = parseOrder({
    { SHIPPING, "EUR 10,00" },
    { VOUCHER, "-EUR 10,00" },
    { "Summe der Erstattung", "EUR 4,47" },
  })
  assert(order.returnActivity == true, "refund row marks a return order")
  local txs = emitMix(order)
  assert(countNamed(txs, "Verpackung & Versand") == 0,
    "shipping covered by a voucher must not be booked in a return order")
  assert(countNamed(txs, "Gutschein eingelöst") == 0,
    "covering voucher must not be booked in a return order")
end

print("== return order: unpaired voucher is still not booked ==")
do
  local order = parseOrder({
    { SHIPPING, "EUR 10,00" },
    { VOUCHER, "-EUR 3,00" },
    { "Summe der Erstattung", "EUR 4,47" },
  })
  local txs = emitMix(order)
  assert(countNamed(txs, "Gutschein eingelöst") == 0,
    "unrelated voucher in a return order stays unbooked")
  assert(countNamed(txs, "Verpackung & Versand") == 1,
    "shipping without a matching voucher stays booked")
end

print("== gift card of equal amount is not a Prime voucher ==")
do
  local order = parseOrder({ { SHIPPING, "EUR 4,99" }, { "Geschenkgutschein(e):", "-EUR 4,99" } })
  local txs = emitMix(order)
  assert(countNamed(txs, "Verpackung & Versand") == 1,
    "shipping must stay booked when only a gift card matches it")
end

print("== coupon that does not cancel shipping stays booked ==")
do
  local order = parseOrder({ { SHIPPING, "EUR 4,19" }, { VOUCHER, "-EUR 5,54" } })
  local txs = emitMix(order)
  assert(countNamed(txs, "Gutschein eingelöst") == 1, "5,54 coupon must stay booked")
  assert(countNamed(txs, "Verpackung & Versand") == 1, "4,19 shipping must stay booked")
end

-- Business layout: net item and shipping rows, "Summe ohne MwSt." and "Anzurechnende MwSt.".
-- Item price is gross (23,80 € = 20,00 € net + 19 %), shipping 4,20 € net, VAT on shipping 0,80 €.
print("== Business account: Prime pair is omitted next to VAT rows ==")
do
  local order = parseOrder({
    { "Zwischensumme:", "EUR 20,00" },
    { SHIPPING, "EUR 4,20" },
    { "Summe ohne MwSt.:", "EUR 24,20" },
    { "Anzurechnende MwSt.:", "EUR 4,60" },
    { "Summe:", "EUR 28,80" },
    { VOUCHER, "-EUR 5,00" },
    { "Gesamtsumme:", "EUR 23,80" },
  }, "EUR 23,80")
  assert(order.orderTotal == 2380, "business total 23,80, got " .. tostring(order.orderTotal))
  local txs = emitMix(order)
  assert(countNamed(txs, "Verpackung & Versand") == 0,
    "Prime-covered business shipping must not be booked")
  assert(countNamed(txs, "Gutschein eingelöst") == 0,
    "covering business voucher must not be booked")
  assert(countNamed(txs, "Testartikel") == 1, "item stays booked")
end

print("== Business account: shipping without voucher is booked incl. VAT ==")
do
  local order = parseOrder({
    { "Zwischensumme:", "EUR 20,00" },
    { SHIPPING, "EUR 4,20" },
    { "Summe ohne MwSt.:", "EUR 24,20" },
    { "Anzurechnende MwSt.:", "EUR 4,60" },
    { "Summe:", "EUR 28,80" },
    { "Gesamtsumme:", "EUR 28,80" },
  }, "EUR 23,80")
  local txs = emitMix(order)
  local shipping = findByName(txs, "Verpackung & Versand")
  assert(shipping ~= nil, "charged business shipping must stay booked")
  assert(math.abs(shipping.amount - (-5.00)) < 0.001,
    "net 4,20 + 19 % VAT = 5,00 booked, got " .. tostring(shipping.amount))
  assert(countNamed(txs, "Testartikel") == 1, "item stays booked")
end

print("== pair that the order total includes is kept (total decides) ==")
do
  -- 19,99 items + 3,35 shipping - 3,99 discount = 19,35 total: the pair is charged, not covered.
  local order = parseOrder({
    { SHIPPING, "EUR 3,35" },
    { "Aktionsrabatt:", "-EUR 3,99" },
    { "Gesamtsumme:", "EUR 19,35" },
  }, "EUR 19,99")
  local txs = emitMix(order)
  local shipping = findByName(txs, "Verpackung & Versand")
  assert(shipping ~= nil and math.abs(shipping.amount - (-3.35)) < 0.001,
    "shipping included in the total must stay booked, got " .. tostring(shipping and shipping.amount))
  assert(findByName(txs, "Aktionsrabatt") ~= nil, "its discount must stay booked with it")
end

print("== full return (total 0): items stay in the sum, so the total must not decide the pair ==")
do
  local extras = env.resolvedSummaryExtras({
    orderCode = "303-0000000-0000001",
    orderSum = 1000,
    orderTotal = 0,
    summaryExtras = {
      { name = "Verpackung & Versand", amount = 335 },
      { name = "Gutschein eingelöst", amount = -399, returnCredit = true },
    },
  })
  assert(#extras == 0, "the Prime shipping pair must be removed after a full return, got " .. #extras)
end

print("== crossed pairs: first-fit would leave the 3,35 shipping row unpaired ==")
do
  -- 3,99 shipping pairs with the 4,75 voucher (gross 19 %), 3,35 with the 3,99 voucher.
  local order = { orderCode = "303-0000000-0000001" }
  local found = env.shippingVoucherPairs(order, {
    { name = "Verpackung & Versand", amount = 399 },
    { name = "Verpackung & Versand", amount = 335 },
    { name = "Gutschein eingelöst", amount = -399 },
    { name = "Gutschein eingelöst", amount = -475 },
  })
  assert(#found == 2, "both shipping rows must be paired, got " .. #found)
  for _, pair in ipairs(found) do
    assert(pair.shipping ~= nil and pair.voucher ~= nil, "pair must reference both rows")
  end
end

print("test_prime_shipping_pairing OK")
