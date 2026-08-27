-- Partial return: default nets to Rücksendekosten; keepStorno shows item+refund.
-- Run: test/run.sh test/test_partial_return.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local bookingDate = os.time({ year = 2026, month = 7, day = 22 })
local now = os.time() + 86400
local NET_TEXT = "Rücksendekosten"
local REFUND_PREFIX = "Erstattung für Bestellung"

local fixtureHtml = [[
<div id="orderDetails">
  <div data-component="orderDate">22. Juli 2026</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Seac Extreme 50, Tauch- und Speerfischermaske</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 22,49</span></div>
    </div>
  </div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Seac Extreme optische Glaeser, Korrekturlinse für Tauchmaske in beide Richtungen</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 50,37</span></div>
    </div>
    <a href="/gp/returns/status/foo">Status der Rücksendung/Erstattung</a>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 149,69</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Summe der Erstattung</span>
    <span class="od-line-item-row-content">EUR 48,38</span>
  </div>
</div>
]]

local function parseHtml()
  env.connectShopWithCheck = function() return mm.HTML(fixtureHtml) end
  local order = {
    orderCode = "303-4257459-5320353",
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
    balancesByPeriod = {},
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

print("== partial return default: kept items + Rücksendekosten net ==")
do
  env.applyAccountAttribute("keepStorno", "false")
  local order = parseHtml()
  assert(#order.orderPositions == 1, "kept item only, got " .. tostring(#order.orderPositions))
  assert(#order.returnedPositions == 1, "returned item stored, got " .. tostring(#(order.returnedPositions or {})))
  assert(order.returnedPositions[1].amount == 5037, "returned gross 50,37")
  assert(env.compactPartialReturnCents(order).netExpenseCents == 199, "net 1,99")
  local txs = emitOrder(order)
  local refunds, netLines, returnedItems = 0, 0, 0
  for _, tx in ipairs(txs) do
    if (tx.name or ""):find(REFUND_PREFIX, 1, true) then
      refunds = refunds + 1
    elseif tx.name == NET_TEXT then
      netLines = netLines + 1
      assert(math.abs(tx.amount - (-1.99)) < 0.001, "Rücksendekosten -1,99, got " .. tostring(tx.amount))
    elseif (tx.name or ""):find("Seac Extreme optische", 1, true) then
      returnedItems = returnedItems + 1
    end
  end
  assert(refunds == 0, "default must not emit refund line, got " .. names(txs))
  assert(returnedItems == 0, "default must not emit returned item, got " .. names(txs))
  assert(netLines == 1, "default must emit Rücksendekosten, got " .. names(txs))
end

print("== keepStorno shows returned item and refund ==")
do
  env.applyAccountAttribute("keepStorno", "true")
  local order = parseHtml()
  local txs = emitOrder(order)
  env.applyAccountAttribute("keepStorno", "false")
  local refunds, returnedItems = 0, 0
  for _, tx in ipairs(txs) do
    if (tx.name or ""):find(REFUND_PREFIX, 1, true) then
      refunds = refunds + 1
      assert(math.abs(tx.amount - 48.38) < 0.001, "refund +48,38")
    elseif (tx.name or ""):find("Seac Extreme optische", 1, true) then
      returnedItems = returnedItems + 1
      assert(math.abs(tx.amount - (-50.37)) < 0.001, "returned item -50,37")
    elseif tx.name == NET_TEXT then
      error("keepStorno must not emit Rücksendekosten, got " .. names(txs))
    end
  end
  assert(returnedItems == 1, "keepStorno must emit returned item, got " .. names(txs))
  assert(refunds == 1, "keepStorno must emit refund, got " .. names(txs))
end

print("== partial return excess refund emits credit and marks adjustments ==")
do
  env.applyAccountAttribute("keepStorno", "false")
  local order = {
    orderCode = "303-excess-0000000",
    bookingDate = bookingDate,
    returnedPositions = {
      { purpose = "Returned item", amount = 1000, qty = 1 },
    },
    refundTransactions = {
      [bookingDate] = {
        [2500] = {},
      },
    },
    subAccountKind = "business",
  }
  local compact = env.compactPartialReturnCents(order)
  assert(compact ~= nil, "expected compact partial return")
  assert(compact.netExpenseCents == 0, "refund exceeds returned gross")
  assert(compact.excessRefundCents == 1500, "excess refund 15 EUR")
  local ctx = {
    mixed = true,
    divisor = -100,
    transactions = {},
    accountNumber = "sub:business",
    now = now,
    periodly = false,
    balance = 0,
    balancesByPeriod = {},
  }
  env.emitOrderAdjustments(ctx, order, order.orderCode, true)
  local refunds = 0
  for _, tx in ipairs(ctx.transactions) do
    if (tx.name or ""):find(REFUND_PREFIX, 1, true) then
      refunds = refunds + 1
      assert(math.abs(tx.amount - 15.0) < 0.001, "excess refund capped to +15,00, got " .. tostring(tx.amount))
    end
  end
  assert(refunds == 1, "excess path must emit one refund, got " .. names(ctx.transactions))
  assert(env.isOrderEmittedForAccount(order.refundTransactions[bookingDate][2500], ctx.accountNumber),
    "refund leaf must be marked emitted after excess path")
end

print("test_partial_return OK")
