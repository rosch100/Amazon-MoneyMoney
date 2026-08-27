-- Incomplete harvest/details emit upstream-style dummy booking.
-- Run: test/run.sh test/test_incomplete_refresh_dummy.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

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

local account = { accountNumber = "mix", owner = "test@example.com" }
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

-- Paused sub-account scan
env.LocalStorage = {
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

-- Pending details only (scan complete) — details fetch must not clear dummy in same run
env.getOrderDetails = function(_order)
end
env.LocalStorage = {
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = since,
  OrderCache = {
    ["303-open"] = {
      orderCode = "303-open",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now,
      detailsDate = 0,
      subAccountKind = "personal",
    },
    ["303-done"] = {
      orderCode = "303-done",
      orderPositions = { { purpose = "Done", amount = 500, qty = 1 } },
      orderSum = 500,
      orderTotal = 500,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { mix = true },
      subAccountKind = "personal",
    },
  },
  subAccountScan = {
    phase = "done",
    incomplete = false,
    totalNew = 0,
    harvestSince = since,
    loginCounter = 1,
  },
}
local r2 = env.RefreshAccount(account, since)
local d2 = hasIncompleteDummy(r2.transactions)
assert(d2 ~= nil, "open details must emit incomplete dummy")
assert(d2.purpose:find("Bestelldetails", 1, true), "purpose must mention open details")

-- Complete refresh: no dummy
env.LocalStorage = {
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
      emittedAccounts = { mix = true },
      subAccountKind = "personal",
    },
  },
  subAccountScan = {
    phase = "done",
    incomplete = false,
    totalNew = 0,
    harvestSince = since,
    loginCounter = 1,
  },
}
local r3 = env.RefreshAccount(account, since)
assert(hasIncompleteDummy(r3.transactions) == nil, "complete refresh must not emit dummy")

print("test_incomplete_refresh_dummy OK")
