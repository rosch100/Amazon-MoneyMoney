-- Mix: no per-order Amazon contra; one pending floating Ausgleich over the emitted ledger.
-- Run: test/run.sh test/test_floating_ausgleich.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.getOrderDetails = function(order)
  if type(order) == 'table' then
    order.detailsDate = os.time() + 86400
    order.detailsParsed = true
  end
end

local function skipHarvest()
  env.LocalStorage.loginCounter = 1
  env.LocalStorage.lastLoginCounter = 1
  env.LocalStorage.lastHarvestSince = os.time()
end

local function baseOrder(code, cents, emitted)
  local order = {
    orderCode = code,
    orderPositions = {
      { purpose = "Item " .. code, amount = cents, qty = 1 },
    },
    orderSum = cents,
    orderTotal = cents,
    bookingDate = os.time({ year = 2026, month = 8, day = 20 }),
    detailsDate = os.time() + 86400,
    detailsParsed = true,
    subAccountKind = "business",
  }
  if emitted then
    order.emittedAccounts = { ["test@example.com"] = true }
  end
  return order
end

local FLOATING_REF = "AMAZON-AUSGLEICH"
local FLOATING_NAME = "Amazon Ausgleich"

local function isOrderContra(tx)
  local name = tx.name or ""
  return name:find("Amazon contra ", 1, true) ~= nil
end

local function findFloating(txs)
  local found
  local n = 0
  for _, tx in ipairs(txs) do
    if tx.endToEndReference == FLOATING_REF then
      n = n + 1
      found = tx
    end
  end
  return found, n
end

env.LocalStorage = { cacheVersion = 23, OrderCache = {} }
skipHarvest()
env.LocalStorage.OrderCache = {
  ["303-1111111-1111111"] = baseOrder("303-1111111-1111111", 1640),
  ["303-2222222-2222222"] = baseOrder("303-2222222-2222222", 3101, true),
}

local account = { accountNumber = "test@example.com", owner = "test@example.com" }
local since = os.time() - (7 * 24 * 60 * 60)
local now = os.time()
local result = env.RefreshAccount(account, since)

assert(result.balance == 0, "combined must report balance 0 for net worth, got " .. tostring(result.balance))

local realSum = 0
local orderContra = 0
for _, tx in ipairs(result.transactions) do
  assert(not isOrderContra(tx), "must not emit per-order contra, got " .. tostring(tx.name))
  if tx.endToEndReference ~= FLOATING_REF then
    realSum = realSum + tx.amount
  end
  if tx.endToEndReference == "303-1111111-1111111" then
    orderContra = orderContra + 1
  end
end
assert(orderContra == 1, "new order emits the purchase line only, got " .. tostring(orderContra))
assert(math.abs(realSum - (-16.40)) < 0.001, "this refresh only emits the new purchase")

local floating, floatCount = findFloating(result.transactions)
assert(floatCount == 1, "exactly one floating Ausgleich, got " .. tostring(floatCount))
assert(floating.booked == false, "floating Ausgleich must stay pending so MoneyMoney can update it")
assert(floating.name == FLOATING_NAME)
-- Clean reimport: Ausgleich offsets all emitted orders (new 16.40 + already emitted 31.01).
assert(math.abs(floating.amount - 47.41) < 0.001, "floating offsets full emitted ledger, got " .. tostring(floating.amount))
assert(floating.bookingDate >= since, "Ausgleich bookingDate must be in the since window")
local expectedDate = env.mixFloatingBookingDate(since, now, "test@example.com")
assert(floating.bookingDate == expectedDate, "Ausgleich anchors before earliest emitted booking")

-- Second refresh: no purchase re-emit; same pending slot (name+date), accumulated amount.
local result2 = env.RefreshAccount(account, since)
local purchase2 = 0
for _, tx in ipairs(result2.transactions) do
  assert(not isOrderContra(tx), "second refresh must not emit per-order contra")
  if tx.endToEndReference == "303-1111111-1111111"
      or tx.endToEndReference == "303-2222222-2222222" then
    purchase2 = purchase2 + 1
  end
end
assert(purchase2 == 0, "already emitted purchases must not re-import")
local floating2, floatCount2 = findFloating(result2.transactions)
assert(floatCount2 == 1, "floating Ausgleich must be re-emitted every refresh")
assert(floating2.booked == false)
assert(floating2.name == floating.name, "pending slot name must stay stable")
assert(floating2.bookingDate == floating.bookingDate, "pending slot date must stay stable")
assert(math.abs(floating2.amount - 47.41) < 0.001)
assert(result2.balance == 0)

-- Refunds: real credit only, no contra pair; ledger accumulates.
env.LocalStorage.OrderCache["303-3333333-3333333"] = baseOrder("303-3333333-3333333", 5000)
env.registerRefundTransaction(env.LocalStorage.OrderCache["303-3333333-3333333"], 1700000000, 2000)
local resultRefund = env.RefreshAccount(account, since)
local refundLines, refundContra = 0, 0
for _, tx in ipairs(resultRefund.transactions) do
  local name = tx.name or ""
  if name:find("Erstattung für Bestellung", 1, true) then
    refundLines = refundLines + 1
    assert(tx.amount > 0, "refund must be a credit")
  end
  if name:find("Amazon contra refund", 1, true) then
    refundContra = refundContra + 1
  end
end
assert(refundLines == 1, "full refund must import as one credit")
assert(refundContra == 0, "must not emit refund contra")
local floating3 = findFloating(resultRefund.transactions)
-- 16.40 + 31.01 + 50 - 20 refund = 77.41
assert(math.abs(floating3.amount - 77.41) < 0.001, "ledger includes refunds, got " .. tostring(floating3.amount))
assert(floating3.bookingDate == floating.bookingDate)

-- Older order in cache later must not move the persisted Ausgleich anchor.
local oldBooking = os.time({ year = 2018, month = 3, day = 10 })
env.LocalStorage.OrderCache["303-5555555-5555555"] = baseOrder("303-5555555-5555555", 999, true)
env.LocalStorage.OrderCache["303-5555555-5555555"].bookingDate = oldBooking
local resultOld = env.RefreshAccount(account, since)
local floatingOld = findFloating(resultOld.transactions)
assert(floatingOld.bookingDate == floating.bookingDate, "persisted anchor must stay stable")

-- During Erstimport the anchor is provisional and not persisted yet.
env.LocalStorage.pendingInitialSync = true
env.LocalStorage.initialSyncHarvestDone = true
env.LocalStorage.initialSyncExpectedAccounts = nil
env.LocalStorage.initialSyncRefreshedAccounts = { ["test@example.com"] = "test@example.com" }
env.LocalStorage.floatingBalanceAnchorByAccount = nil
local resultPending = env.RefreshAccount(account, since)
local floatingPending = findFloating(resultPending.transactions)
assert(floatingPending.bookingDate == env.mixFloatingBookingDate(since, now, "test@example.com"))
env.LocalStorage.OrderCache["303-6666666-6666666"] = baseOrder("303-6666666-6666666", 500, true)
env.LocalStorage.OrderCache["303-6666666-6666666"].bookingDate = os.time({ year = 2015, month = 1, day = 1 })
local resultPending2 = env.RefreshAccount(account, since)
local floatingPending2 = findFloating(resultPending2.transactions)
assert(floatingPending2.bookingDate ~= floating.bookingDate, "provisional anchor may move during Erstimport")
env.LocalStorage.pendingInitialSync = nil
env.LocalStorage.initialSyncHarvestDone = nil
env.LocalStorage.floatingBalanceAnchorByAccount = nil
local resultLock = env.RefreshAccount(account, since)
local floatingLock = findFloating(resultLock.transactions)
local resultLock2 = env.RefreshAccount(account, since)
local floatingLock2 = findFloating(resultLock2.transactions)
assert(floatingLock2.bookingDate == floatingLock.bookingDate, "anchor locks after Erstimport")

-- Full return: omit booking+storno unless keepStorno.
env.LocalStorage.OrderCache["303-4444444-4444444"] = baseOrder("303-4444444-4444444", 800)
env.LocalStorage.OrderCache["303-4444444-4444444"].returns = {
  [1700000100] = {
    [800] = {
      Item = {},
    },
  },
}
local resultRet = env.RefreshAccount(account, since)
local returnLines, returnPurchase, returnContra = 0, 0, 0
for _, tx in ipairs(resultRet.transactions) do
  local name = tx.name or ""
  if tx.endToEndReference == "303-4444444-4444444" then
    if name:find("Rückgabe:", 1, true) then
      returnLines = returnLines + 1
    else
      returnPurchase = returnPurchase + 1
    end
  end
  if name:find("Amazon contra returned", 1, true) then
    returnContra = returnContra + 1
  end
end
assert(returnLines == 0, "full return must omit storno by default")
assert(returnPurchase == 0, "full return must omit purchase by default")
assert(returnContra == 0, "must not emit return contra")

account.attributes = { keepStorno = "true" }
env.LocalStorage.OrderCache["303-4444444-4444445"] = baseOrder("303-4444444-4444445", 800)
env.LocalStorage.OrderCache["303-4444444-4444445"].returns = {
  [1700000100] = {
    [800] = {
      Item = {},
    },
  },
}
local resultKeep = env.RefreshAccount(account, since)
account.attributes = nil
local keepReturn, keepPurchase = 0, 0
for _, tx in ipairs(resultKeep.transactions) do
  if tx.endToEndReference == "303-4444444-4444445" then
    if (tx.name or ""):find("Rückgabe:", 1, true) then
      keepReturn = keepReturn + 1
    else
      keepPurchase = keepPurchase + 1
    end
  end
end
assert(keepPurchase == 1, "keepStorno must emit purchase")
assert(keepReturn == 1, "keepStorno must emit return")

-- since after month-end: clamp bookingDate up to since
local lateSince = os.time({ year = 2099, month = 1, day = 15 })
assert(env.mixFloatingBookingDate(lateSince, now) == lateSince,
  "bookingDate must not precede MoneyMoney since")

print("test_floating_ausgleich OK")
