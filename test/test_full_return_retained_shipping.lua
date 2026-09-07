-- Full return with retained shipping: net Rücksendekosten only, no Gutschein/purchase lines.
-- Run: test/run.sh test/test_full_return_retained_shipping.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

local bookingDate = os.time({ year = 2025, month = 8, day = 7 })
local now = os.time() + 86400
local ORDER_CODE = "305-5686988-3710730"
local NET_TEXT = "Rücksendekosten"

local fixtureHtml = [[
<div id="orderDetails">
  <div data-component="orderDate">7. August 2025</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Philips 346E2LAE - 34 Zoll Wqhd Monitor, Adaptive Sync, Lautsprecher</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 222,94</span></div>
    </div>
    <a href="/gp/returns/status/foo">Status der Rücksendung/Erstattung</a>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Gutschein eingelöst:</span>
    <span class="od-line-item-row-content">EUR 1,93</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 0,00</span>
  </div>
</div>
]]

local function parseHtml()
  env.connectShopWithCheck = function() return mm.HTML(fixtureHtml) end
  local order = {
    orderCode = ORDER_CODE,
    orderPositions = {},
    orderSum = 0,
    orderTotal = 0,
    bookingDate = bookingDate,
    detailsDate = 0,
    subAccountKind = "business",
  }
  env.getOrderDetails(order)
  return order
end

local function emitOrder(order)
  local ctx = {
    mixed = true,
    divisor = -100,
    transactions = {},
    accountNumber = "sub:business",
    now = now,
    periodly = false,
    balance = 0,
  }
  env.appendOrderToRefresh(ctx, order, order.orderCode)
  return ctx.transactions
end

local function names(txs)
  local out = {}
  for _, tx in ipairs(txs) do
    table.insert(out, tx.name)
  end
  return table.concat(out, " | ")
end

print("== full return: Gutschein row becomes Rücksendekosten net ==")
do
  env.applyAccountAttribute("keepStorno", "false")
  local order = parseHtml()
  assert(order.returnActivity == true, "return activity must be detected")
  assert(#order.returnedPositions == 1, "monitor must be returned, got " .. tostring(#order.returnedPositions))
  assert(order.returnedPositions[1].amount == 22294, "returned gross 222,94")
  assert(env.adjustmentCreditCents(order) == 22101, "refund inferred 221,01, got " .. tostring(env.adjustmentCreditCents(order)))
  local compact = env.compactPartialReturnCents(order)
  assert(compact ~= nil, "expected compact partial return")
  assert(compact.netExpenseCents == 193, "net retained shipping 1,93")
  local txs = emitOrder(order)
  assert(#txs == 1, "only Rücksendekosten, got " .. names(txs))
  assert(txs[1].name == NET_TEXT, "expected Rücksendekosten, got " .. tostring(txs[1].name))
  assert(math.abs(txs[1].amount - (-1.93)) < 0.001, "amount -1,93, got " .. tostring(txs[1].amount))
  for _, tx in ipairs(txs) do
    assert(not (tx.name or ""):find("Gutschein", 1, true), "must not emit Gutschein, got " .. names(txs))
    assert(not (tx.name or ""):find("Philips", 1, true), "must not emit purchase, got " .. names(txs))
  end
end

print("== zero-total voucher order without return marker stays a purchase ==")
do
  env.applyAccountAttribute("keepStorno", "false")
  local htmlNoLink = fixtureHtml:gsub('<a href="/gp/returns/status/foo">.-</a>', "")
  env.connectShopWithCheck = function() return mm.HTML(htmlNoLink) end
  local order = {
    orderCode = "305-no-link-0000000",
    orderPositions = {},
    orderSum = 0,
    orderTotal = 0,
    bookingDate = bookingDate,
    detailsDate = 0,
    subAccountKind = "business",
  }
  env.getOrderDetails(order)
  assert(#order.orderPositions == 1, "item stays in purchase list without link")
  assert(order.returnActivity == false, "voucher and zero total are not proof of a return")
  assert(env.effectiveReturnedCents(order) == 0, "purchase lines must not be inferred as returned")
  assert(env.orderHasKeptPurchaseItems(order) == true, "purchase must remain emit-ready")
  assert(env.compactPartialReturnCents(order) == nil, "no return costs without return evidence")
end

print("test_full_return_retained_shipping OK")
