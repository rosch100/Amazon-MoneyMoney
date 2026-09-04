-- Incomplete harvest/details emit upstream-style dummy booking.
-- Run: test/run.sh test/test_incomplete_refresh_dummy.lua
---@diagnostic disable: duplicate-set-field -- Test cases intentionally replace sandbox mocks.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.getOrderDetails = function(order)
  if type(order) == 'table' then
    order.detailsDate = os.time() + 86400
    order.detailsParsed = true
    order.orderPositions = order.orderPositions or {
      { purpose = "Item", amount = 100, qty = 1 },
    }
  end
end
env.scanAllAmazonSubAccounts = function()
  return 0, nil
end

local account = { accountNumber = "test@example.com", owner = "test@example.com" }
local since = 0
local now = os.time()

local incompleteDummyName = "Es sind noch weitere Bestellungen offen…"

local function hasIncompleteDummy(transactions)
  for _, tx in ipairs(transactions) do
    if tx.name == incompleteDummyName then
      return tx
    end
  end
  return nil
end

local function doneScan(harvestSince, incomplete, totalNew)
  return {
    phase = "done",
    incomplete = incomplete,
    totalNew = totalNew,
    harvestSince = harvestSince,
    loginCounter = 1,
  }
end

local function completedInitialSyncStorage(orderCache, scan)
  return {
    cacheVersion = 23,
    loginCounter = 1,
    lastLoginCounter = 1,
    lastHarvestSince = since,
    pendingInitialSync = true,
    initialSyncHarvestDone = true,
    initialSyncRefreshedAccounts = { ["test@example.com"] = "test@example.com" },
    OrderCache = orderCache,
    subAccountScan = scan,
  }
end

-- Paused sub-account scan
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 0,
  lastHarvestSince = 0,
  pendingInitialSync = true,
  OrderCache = {
    ["303-1111111-1111111"] = {
      orderCode = "303-1111111-1111111",
      orderPositions = { { purpose = "Item", amount = 1000, qty = 1 } },
      orderSum = 1000,
      orderTotal = 1000,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      subAccountKind = "personal",
    },
  },
  subAccountScan = {
    phase = "running",
    incomplete = true,
    plan = { { kind = "personal", label = "Persönliches Konto" } },
    index = 1,
    totalNew = 50,
  },
}
local r1 = env.RefreshAccount(account, since)
local d1 = hasIncompleteDummy(r1.transactions)
assert(d1 ~= nil, "paused scan must emit incomplete dummy")
assert(d1.amount == 0 and d1.booked == false, "dummy must be zero pending booking")
assert(d1.endToEndReference == "AMAZON-INCOMPLETE-HARVEST",
  "dummy must use stable endToEndReference for MM upsert")
assert(type(d1.purpose) == "string" and d1.purpose:find("Abruf der Unterkonten", 1, true),
  "purpose must mention incomplete scan, got: "..tostring(d1.purpose))

-- Pending details beyond this run's limit — dummy only while another refresh will continue
env.getOrderDetails = function(_order)
end
env.applyAccountAttribute("limitOrders", 1, false)
env.LocalStorage = completedInitialSyncStorage({
  ["303-open-a"] = {
      orderCode = "303-open-a",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now,
      detailsDate = 0,
      subAccountKind = "personal",
    },
    ["303-open-b"] = {
      orderCode = "303-open-b",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now - 10,
      detailsDate = 0,
      subAccountKind = "personal",
    },
  }, doneScan(since, false, 0))
local r2 = env.RefreshAccount(account, since)
local d2 = hasIncompleteDummy(r2.transactions)
assert(d2 ~= nil, "truncated details batch must emit incomplete dummy")
assert(d2.purpose:find("Bestelldetails", 1, true), "purpose must mention open details")
env.applyAccountAttribute("limitOrders", 250, false)

-- Failed details remain visible even when the attempt count stays under the limit
env.getOrderDetails = function(_order)
end
env.LocalStorage = completedInitialSyncStorage({
  ["303-fail-details"] = {
      orderCode = "303-fail-details",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now,
      detailsDate = 0,
      subAccountKind = "personal",
    },
  }, doneScan(since, false, 0))
local rFail = env.RefreshAccount(account, since)
local dFail = hasIncompleteDummy(rFail.transactions)
assert(dFail ~= nil, "failed details must keep AMAZON-INCOMPLETE-HARVEST")
assert(dFail.purpose:find("Bestelldetails", 1, true),
  "failed details purpose must mention open details")

-- Due details from an older failed attempt must be retried even without a new harvest/refund watch
local detailsCalls = 0
env.getOrderDetails = function(_order)
  detailsCalls = detailsCalls + 1
  return false
end
local recentSince = now - 7 * 86400
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = recentSince,
  OrderCache = {
    ["303-old-open-details"] = {
      orderCode = "303-old-open-details",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now - 400 * 86400,
      detailsDate = 0,
      subAccountKind = "personal",
    },
  },
  subAccountScan = doneScan(recentSince, false, 0),
}
local rOldDetails = env.RefreshAccount(account, recentSince)
assert(detailsCalls == 1, "due details must be retried without a new harvest")
assert(hasIncompleteDummy(rOldDetails.transactions) ~= nil,
  "failed due-details retry must keep AMAZON-INCOMPLETE-HARVEST")

-- Erstimport harvest already done, scan state gone after login: no dummy
env.getOrderDetails = function(order)
  if type(order) == "table" then
    order.detailsDate = now + 86400
    order.detailsParsed = true
  end
  return true
end
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 2,
  lastLoginCounter = 2,
  lastHarvestSince = since,
  pendingInitialSync = true,
  initialSyncHarvestDone = true,
  initialSyncRefreshedAccounts = { ["test@example.com"] = "test@example.com" },
  OrderCache = {
    ["303-done-login"] = {
      orderCode = "303-done-login",
      orderPositions = { { purpose = "Done", amount = 500, qty = 1 } },
      orderSum = 500,
      orderTotal = 500,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { ["test@example.com"] = true },
      subAccountKind = "personal",
    },
  },
}
assert(env.LocalStorage.subAccountScan == nil)
local rLogin = env.RefreshAccount(account, since)
assert(hasIncompleteDummy(rLogin.transactions) == nil,
  "harvest-done Erstimport without scan state must not emit dummy")

-- phase=done + incomplete=true (e.g. no-switcher hasMore pause) must still dummy
env.LocalStorage = completedInitialSyncStorage({
  ["303-done-pause"] = {
      orderCode = "303-done-pause",
      orderPositions = { { purpose = "Done", amount = 500, qty = 1 } },
      orderSum = 500,
      orderTotal = 500,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { ["test@example.com"] = true },
      subAccountKind = "personal",
    },
  }, doneScan(since, true, 10))
local rDoneIncomplete = env.RefreshAccount(account, since)
local dDoneIncomplete = hasIncompleteDummy(rDoneIncomplete.transactions)
assert(dDoneIncomplete ~= nil, "phase=done incomplete scan must emit dummy")
assert(dDoneIncomplete.purpose:find("Abruf der Unterkonten", 1, true),
  "purpose must mention incomplete scan, got: "..tostring(dDoneIncomplete.purpose))

-- ABA pagination incomplete: harvest must continue and dummy must stay until the batch succeeds
local incSince = now - 7 * 86400
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = incSince,
  refreshSince = incSince,
  abaRollupHarvestIncomplete = "pagination",
  abaFullHarvestHasMore = false,
  OrderCache = {
    ["303-aba"] = {
      orderCode = "303-aba",
      orderPositions = { { purpose = "Done", amount = 500, qty = 1 } },
      orderSum = 500,
      orderTotal = 500,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { ["test@example.com"] = true },
      subAccountKind = "business",
    },
  },
  subAccountScan = doneScan(incSince, false, 0),
}
assert(env.resolveSubAccountScanCache() == nil,
  "ABA pagination incomplete must invalidate a cached completed sub-account scan")
assert(env.LocalStorage.subAccountScan == nil,
  "ABA pagination retry must restart the sub-account scan")
assert(env.isFullAccountHarvestComplete() == false,
  "ABA pagination incomplete must not count as full harvest complete")
assert(env.shouldRunAccountHarvest(incSince, now) == true,
  "ABA pagination incomplete must keep harvesting")
local rAba = env.RefreshAccount(account, incSince)
local dAba = hasIncompleteDummy(rAba.transactions)
assert(dAba ~= nil, "ABA incomplete must emit dummy while harvest retries")
assert(dAba.purpose:find("Pagination", 1, true),
  "purpose must mention ABA pagination, got: "..tostring(dAba.purpose))

env.LocalStorage.abaRollupHarvestIncomplete = "pagination"
env.clearAbaFullHarvestBatch()
assert(env.isAbaRollupHarvestIncomplete() == false,
  "clearing the ABA batch must also clear the sticky incomplete flag")

-- Complete refresh: no dummy
env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = since,
  OrderCache = {
    ["303-done"] = {
      orderCode = "303-done",
      orderPositions = { { purpose = "Done", amount = 500, qty = 1 } },
      orderSum = 500,
      orderTotal = 500,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { ["test@example.com"] = true },
      subAccountKind = "personal",
    },
  },
  subAccountScan = doneScan(since, false, 0),
}
local r3 = env.RefreshAccount(account, since)
assert(hasIncompleteDummy(r3.transactions) == nil, "complete refresh must not emit dummy")

print("test_incomplete_refresh_dummy OK")
