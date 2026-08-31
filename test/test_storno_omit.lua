-- Full Storno (refund/return/unbilled cancel) omits booking+storno unless keepStorno.
-- Run: test/run.sh test/test_storno_omit.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local now = os.time() + 86400
local bookingDate = os.time({ year = 2026, month = 6, day = 22 })

local function mixCtx()
  return {
    mixed = true,
    divisor = -100,
    transactions = {},
    accountNumber = "mix",
    now = now,
    periodly = false,
    balance = 0,
    balancesByPeriod = {},
  }
end

local function purchaseOrder(code, cents)
  return {
    orderCode = code,
    orderPositions = { { purpose = "Item " .. code, amount = cents, qty = 1 } },
    orderSum = cents,
    orderTotal = cents,
    bookingDate = bookingDate,
    detailsDate = now,
    detailsParsed = true,
    subAccountKind = "business",
  }
end

local function names(txs)
  local out = {}
  for _, tx in ipairs(txs) do
    table.insert(out, tx.name)
  end
  return table.concat(out, " | ")
end

local function countBy(txs, pred)
  local n = 0
  for _, tx in ipairs(txs) do
    if pred(tx) then
      n = n + 1
    end
  end
  return n
end

local function emitOrder(order)
  local ctx = mixCtx()
  env.appendOrderToRefresh(ctx, order, order.orderCode)
  return ctx.transactions
end

local STORNO_NAME = "Storno"

local function setKeepStorno(on)
  env.applyAccountAttribute("keepStorno", on and "true" or "false")
end

setKeepStorno(false)

------------------------------------------------------------------ FULL REFUND
print("== full refund omits booking and storno ==")
do
  local order = purchaseOrder("303-full-refund", 670)
  env.registerRefundTransaction(order, bookingDate + 86400, 670)
  local txs = emitOrder(order)
  assert(#txs == 0, "full refund must omit purchase+refund, got " .. names(txs))
  assert(env.isOrderEmittedForAccount(order, "mix") == true, "omitted purchase must be marked emitted")
end

print("== keepStorno keeps booking and full refund ==")
do
  setKeepStorno(true)
  local order = purchaseOrder("303-keep-refund", 670)
  env.registerRefundTransaction(order, bookingDate + 86400, 670)
  local txs = emitOrder(order)
  setKeepStorno(false)
  local purchases = countBy(txs, function(tx)
    return tx.name == "Item 303-keep-refund"
  end)
  local refunds = countBy(txs, function(tx)
    return (tx.name or ""):find("Erstattung für Bestellung", 1, true) ~= nil
  end)
  assert(purchases == 1, "keepStorno must emit purchase, got " .. names(txs))
  assert(refunds == 1, "keepStorno must emit refund, got " .. names(txs))
end

print("== partial refund keeps booking and credit ==")
do
  local order = purchaseOrder("303-part-refund", 5000)
  env.registerRefundTransaction(order, bookingDate + 86400, 2000)
  local txs = emitOrder(order)
  local purchases = countBy(txs, function(tx)
    return tx.name == "Item 303-part-refund"
  end)
  local refunds = countBy(txs, function(tx)
    return (tx.name or ""):find("Erstattung für Bestellung", 1, true) ~= nil
  end)
  assert(purchases == 1, "partial refund must keep purchase, got " .. names(txs))
  assert(refunds == 1, "partial refund must keep credit, got " .. names(txs))
end

print("== already emitted purchase still imports later full refund ==")
do
  local order = purchaseOrder("303-later-refund", 670)
  order.emittedAccounts = { mix = true }
  env.registerRefundTransaction(order, bookingDate + 86400, 670)
  local txs = emitOrder(order)
  local purchases = countBy(txs, function(tx)
    return tx.name == "Item 303-later-refund"
  end)
  local refunds = countBy(txs, function(tx)
    return (tx.name or ""):find("Erstattung für Bestellung", 1, true) ~= nil
  end)
  assert(purchases == 0, "already emitted purchase must not re-import, got " .. names(txs))
  assert(refunds == 1, "later full refund must still import, got " .. names(txs))
end

------------------------------------------------------------------ FULL RETURN
print("== full return omits booking and storno ==")
do
  local order = purchaseOrder("303-full-return", 800)
  order.returns = {
    [bookingDate + 86400] = {
      [800] = { Item = {} },
    },
  }
  local txs = emitOrder(order)
  assert(#txs == 0, "full return must omit purchase+return, got " .. names(txs))
end

print("== keepStorno keeps booking and full return ==")
do
  setKeepStorno(true)
  local order = purchaseOrder("303-keep-return", 800)
  order.returns = {
    [bookingDate + 86400] = {
      [800] = { Item = {} },
    },
  }
  local txs = emitOrder(order)
  setKeepStorno(false)
  local returns = countBy(txs, function(tx)
    return (tx.name or ""):find("Rückgabe:", 1, true) ~= nil
  end)
  local purchases = countBy(txs, function(tx)
    return tx.name == "Item 303-keep-return"
  end)
  assert(purchases == 1, "keepStorno must emit purchase, got " .. names(txs))
  assert(returns == 1, "keepStorno must emit return, got " .. names(txs))
end

------------------------------------------------------------------ UNBILLED
print("== unbilled cancel keepStorno emits item and Storno ==")
do
  setKeepStorno(true)
  local order = purchaseOrder("303-unbilled-keep", 670)
  order.unbilledCancel = true
  order.orderTotal = 0
  local txs = emitOrder(order)
  setKeepStorno(false)
  local item = nil
  local storno = nil
  for _, tx in ipairs(txs) do
    if tx.name == "Item 303-unbilled-keep" then
      item = tx
    elseif tx.name == STORNO_NAME then
      storno = tx
    end
  end
  assert(item ~= nil, "keepStorno unbilled must emit item, got " .. names(txs))
  assert(storno ~= nil, "keepStorno unbilled must emit Storno, got " .. names(txs))
  assert(math.abs(item.amount + storno.amount) < 0.001, "item+Storno must net to 0")
end

------------------------------------------------------------------ NOTES
print("== RefreshAccount notes keepStorno ==")
do
  env.connectShop = function()
    return mm.HTML("<html><body></body></html>")
  end
  env.getOrderDetails = function(order)
    if type(order) == "table" then
      order.detailsDate = now
      order.detailsParsed = true
    end
  end
  local order = purchaseOrder("303-notes-storno", 670)
  env.registerRefundTransaction(order, bookingDate + 86400, 670)
  env.LocalStorage = {
    cacheVersion = 22,
    loginCounter = 1,
    lastLoginCounter = 1,
    lastHarvestSince = os.time(),
    OrderCache = { ["303-notes-storno"] = order },
  }
  local account = { accountNumber = "mix", owner = "test@example.com" }
  local omitted = env.RefreshAccount(account, bookingDate)
  local omittedCount = countBy(omitted.transactions, function(tx)
    return tx.endToEndReference == "303-notes-storno"
  end)
  assert(omittedCount == 0, "notes default must omit booking+storno")

  env.LocalStorage.OrderCache["303-notes-storno"] = purchaseOrder("303-notes-storno", 670)
  env.registerRefundTransaction(env.LocalStorage.OrderCache["303-notes-storno"], bookingDate + 86400, 670)
  account.attributes = { keepStorno = "true" }
  local kept = env.RefreshAccount(account, bookingDate)
  local keptCount = countBy(kept.transactions, function(tx)
    return tx.endToEndReference == "303-notes-storno"
  end)
  assert(keptCount == 2, "keepStorno note must emit booking+storno, got " .. tostring(keptCount))
end

print("test_storno_omit OK")
