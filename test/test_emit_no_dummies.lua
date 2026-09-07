-- RefreshAccount: no dummies; per-account emittedAccounts; subs independent of combined.
-- Run: test/run.sh test/test_emit_no_dummies.lua
---@diagnostic disable: duplicate-set-field -- Test cases intentionally replace sandbox mocks.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
local fetched = {}
env.getOrderDetails = function(order)
  if type(order) == 'table' and type(order.orderCode) == 'string' then
    fetched[order.orderCode] = true
  end
  if type(order) == 'table' then
    order.detailsDate = os.time() + 86400
    order.detailsParsed = true
  end
end

local function baseCache()
  return {
    ["303-1111111-1111111"] = {
      orderCode = "303-1111111-1111111",
      orderPositions = {
        { purpose = "Item A", amount = 1640, qty = 1 },
      },
      orderSum = 1640,
      orderTotal = 1640,
      bookingDate = os.time({ year = 2026, month = 8, day = 25 }),
      detailsDate = os.time() + 86400,
      detailsParsed = true,
      subAccountKind = "business",
    },
    ["303-2222222-2222222"] = {
      orderCode = "303-2222222-2222222",
      orderPositions = {
        { purpose = "Item B", amount = 3101, qty = 1 },
      },
      orderSum = 3101,
      orderTotal = 3101,
      bookingDate = os.time({ year = 2026, month = 8, day = 21 }),
      detailsDate = os.time() + 86400,
      detailsParsed = true,
      emittedAccounts = { ["test@example.com"] = true },
      subAccountKind = "business",
    },
  }
end

-- Skip network harvest: login counters match + lastHarvestSince newer than since.
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = os.time(),
  OrderCache = baseCache(),
}

local account = { accountNumber = "test@example.com", owner = "test@example.com" }
local since = os.time() - (7 * 24 * 60 * 60)
local result = env.RefreshAccount(account, since)

assert(type(result) == "table")
assert(type(result.transactions) == "table")

for _, tx in ipairs(result.transactions) do
  assert(tx.name ~= "Please reload!", "must not emit Please reload! dummy")
  assert(tx.name ~= "Cache reset, please reload!", "must not emit cache-reset dummy")
  assert(not (tx.amount == 0 and tx.booked == false and type(tx.purpose) == "string"
    and tx.purpose:find("coffee", 1, true)), "must not emit coffee dummy")
  assert(tx.name ~= "Es sind noch weitere Bestellungen offen…",
    "complete incremental refresh must not emit incomplete-fetch dummy")
end

local refs = {}
for _, tx in ipairs(result.transactions) do
  if tx.endToEndReference then
    refs[tx.endToEndReference] = true
  end
end
assert(refs["303-1111111-1111111"] == true, "new order must be emitted")
assert(refs["303-2222222-2222222"] == nil, "already emitted for combined email must not re-import")
assert(env.LocalStorage.OrderCache["303-1111111-1111111"].emittedAccounts["test@example.com"] == true,
  "new order must be marked emitted for combined email")
assert(env.LocalStorage.OrderCache["303-1111111-1111111"].emittedAccounts["AO.3BUSINESSID02"] == nil,
  "combined emit must not mark business customerId")

-- Second combined refresh: no re-emit
local result2 = env.RefreshAccount(account, since)
local count2 = 0
for _, tx in ipairs(result2.transactions) do
  if tx.endToEndReference == "303-1111111-1111111" then
    count2 = count2 + 1
  end
end
assert(count2 == 0, "second combined refresh must not re-emit")

-- Business customerId account must still receive orders already emitted on combined
env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Persönliches Konto", customerName = "Persönliches Konto",
    accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
})
local subAccount = { accountNumber = "AO.3BUSINESSID02", owner = "test@example.com" }
local resultSub = env.RefreshAccount(subAccount, since)
local subRefs = {}
for _, tx in ipairs(resultSub.transactions) do
  if tx.endToEndReference then
    subRefs[tx.endToEndReference] = true
  end
end
assert(subRefs["303-1111111-1111111"] == true, "sub must emit order already sent to combined")
assert(subRefs["303-2222222-2222222"] == true, "sub must emit order already marked for combined")
assert(env.LocalStorage.OrderCache["303-1111111-1111111"].emittedAccounts["AO.3BUSINESSID02"] == true)
assert(env.LocalStorage.OrderCache["303-2222222-2222222"].emittedAccounts["AO.3BUSINESSID02"] == true)

-- Incomplete details must not mark emitted
env.LocalStorage.OrderCache["303-incomplete"] = {
  orderCode = "303-incomplete",
  orderPositions = {},
  orderSum = 0,
  orderTotal = 0,
  bookingDate = os.time(),
  detailsDate = 0,
  subAccountKind = "business",
}
local resultInc = env.RefreshAccount(subAccount, since)
assert(env.LocalStorage.OrderCache["303-incomplete"].emittedAccounts == nil,
  "stub without details must not be marked emitted")
local incCount = 0
for _, tx in ipairs(resultInc.transactions) do
  if tx.endToEndReference == "303-incomplete" then
    incCount = incCount + 1
  end
end
assert(incCount == 0, "incomplete stub must not emit")

-- detailsDate set without successful parse must not mark emitted
env.LocalStorage.OrderCache["303-noparse"] = {
  orderCode = "303-noparse",
  orderPositions = {},
  orderSum = 0,
  orderTotal = 0,
  bookingDate = os.time(),
  detailsDate = os.time() + 86400,
  subAccountKind = "business",
}
env.RefreshAccount(subAccount, since)
assert(env.LocalStorage.OrderCache["303-noparse"].emittedAccounts == nil,
  "complete detailsDate without detailsParsed/didEmit must not mark emitted")

-- successful empty parse must NOT mark emitted (positions may appear later)
env.LocalStorage.OrderCache["303-emptyok"] = {
  orderCode = "303-emptyok",
  orderPositions = {},
  orderSum = 0,
  orderTotal = 0,
  bookingDate = os.time(),
  detailsDate = os.time() + 86400,
  detailsParsed = true,
  subAccountKind = "business",
}
env.RefreshAccount(subAccount, since)
assert(env.LocalStorage.OrderCache["303-emptyok"].emittedAccounts == nil,
  "empty detailsParsed must not mark emitted")

-- positions appearing after empty emit flags must clear and allow emit
env.LocalStorage.OrderCache["303-laterpos"] = {
  orderCode = "303-laterpos",
  orderPositions = {},
  orderSum = 0,
  orderTotal = 0,
  bookingDate = os.time({ year = 2026, month = 8, day = 20 }),
  detailsDate = os.time() + 86400,
  detailsParsed = true,
  emittedAccounts = { ["A3BUSINESSID02"] = true },
  subAccountKind = "business",
}
assert(env.orderHasPositions(env.LocalStorage.OrderCache["303-laterpos"]) == false)
-- Simulate getOrderDetails discovering positions
local later = env.LocalStorage.OrderCache["303-laterpos"]
local had = env.orderHasPositions(later)
later.orderPositions = { { purpose = "Later Item", amount = 999, qty = 1 } }
later.orderSum = 999
later.orderTotal = 999
if not had and env.orderHasPositions(later) then
  env.clearOrderEmittedFlags(later, true)
end
assert(later.emittedAccounts == nil, "new positions must clear prior empty emit flags")
local resultLater = env.RefreshAccount(subAccount, since)
local laterCount = 0
for _, tx in ipairs(resultLater.transactions) do
  if tx.endToEndReference == "303-laterpos" then
    laterCount = laterCount + 1
  end
end
assert(laterCount > 0, "order must emit after positions appear")
assert(env.LocalStorage.OrderCache["303-laterpos"].emittedAccounts["AO.3BUSINESSID02"] == true)

-- email emit markers on order+return must not re-emit on combined refresh
env.LocalStorage.OrderCache["303-ret"] = {
  orderCode = "303-ret",
  orderPositions = { { purpose = "Item", amount = 5000, qty = 1 } },
  orderSum = 5000,
  orderTotal = 5000,
  bookingDate = os.time({ year = 2026, month = 7, day = 1 }),
  detailsDate = os.time() + 86400,
  detailsParsed = true,
  emittedAccounts = { ["test@example.com"] = true },
  subAccountKind = "business",
  returns = {
    [os.time({ year = 2026, month = 7, day = 10 })] = {
      [5000] = {
        ["Item"] = { emittedAccounts = { ["test@example.com"] = true } },
      },
    },
  },
}
local retBooking
for k,_ in pairs(env.LocalStorage.OrderCache["303-ret"].returns) do
  retBooking = k
end
local retLeaf = env.LocalStorage.OrderCache["303-ret"].returns[retBooking][5000]["Item"]
assert(retLeaf.emittedAccounts["test@example.com"] == true)
assert(env.isOrderEmittedForAccount(retLeaf, "test@example.com") == true)
local mixAfterRet = env.RefreshAccount(account, since)
local retTx = 0
for _, tx in ipairs(mixAfterRet.transactions) do
  if tx.endToEndReference == "303-ret" then
    retTx = retTx + 1
  end
end
assert(retTx == 0, "already-emitted order+return must not produce combined txs")

-- Obsolete period account numbers are rejected (no monthly/yearly Refresh).
local monthlyOk, monthlyErr = pcall(env.RefreshAccount,
  { accountNumber = "monthly", owner = "test@example.com" }, since)
assert(monthlyOk == false, "RefreshAccount must reject obsolete monthly")
assert(tostring(monthlyErr):find("neu anlegen", 1, true)
    or tostring(monthlyErr):find("Amazon Bestellungen", 1, true),
  "rejection must name recreate / Amazon Bestellungen")

-- Emit-only refresh (harvest skipped) still runs incremental refund watch.
local emitOnlySince = os.time() - (3 * 24 * 60 * 60)
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = os.time(),
  OrderCache = {
    ["303-emitonly"] = {
      orderCode = "303-emitonly",
      bookingDate = emitOnlySince + 3600,
      detailsDate = os.time() - 3600,
      emittedAccounts = { ["test@example.com"] = true },
      orderPositions = { { purpose = "X", amount = 100, qty = 1 } },
      orderSum = 100,
      orderTotal = 100,
    },
  },
}
local scanCalls = 0
env.scanAllAmazonSubAccounts = function()
  scanCalls = scanCalls + 1
  return 0, nil
end
env.RefreshAccount(account, emitOnlySince)
assert(scanCalls == 0, "emit-only refresh must not scan sub-accounts")
assert(fetched["303-emitonly"] == true,
  "emit-only refresh must fetch due refund-watch order details")

-- Scan error must not block refund watch + details fetch for due orders.
local scanErrSince = os.time() - (3 * 24 * 60 * 60)
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 2,
  lastLoginCounter = 2,
  lastHarvestSince = 0,
  OrderCache = {
    ["303-scanerr"] = {
      orderCode = "303-scanerr",
      bookingDate = scanErrSince + 3600,
      detailsDate = os.time() - 3600,
      emittedAccounts = { ["test@example.com"] = true },
      orderPositions = { { purpose = "Y", amount = 200, qty = 1 } },
      orderSum = 200,
      orderTotal = 200,
      detailsParsed = true,
    },
  },
}
fetched = {}
env.scanAllAmazonSubAccounts = function()
  return nil, "scan failed"
end
env.RefreshAccount(account, scanErrSince)
assert(fetched["303-scanerr"] == true,
  "scan error must not block refund-watch details fetch")

print("test_emit_no_dummies OK")
