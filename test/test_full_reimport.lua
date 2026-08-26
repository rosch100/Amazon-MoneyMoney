-- Version bump requires a full MoneyMoney delete + resetCache reimport.
-- Run: test/run.sh test/test_full_reimport.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local function skipHarvest()
  env.LocalStorage.loginCounter = 1
  env.LocalStorage.lastLoginCounter = 1
  env.LocalStorage.lastHarvestSince = os.time()
end

local account = { accountNumber = "mix", owner = "test@example.com" }
local since = os.time() - (7 * 24 * 60 * 60)

-- Fresh storage (no prior version): keep cache, do not block emit.
env.LocalStorage = {
  OrderCache = {
    ["303-1111111-1111111"] = {
      orderCode = "303-1111111-1111111",
      orderPositions = { { purpose = "Item", amount = 1640, qty = 1 } },
      orderSum = 1640,
      orderTotal = 1640,
      bookingDate = os.time({ year = 2026, month = 8, day = 20 }),
      detailsDate = os.time() + 86400,
      subAccountKind = "business",
    },
  },
}
skipHarvest()
assert(env.applyImportSchemaUpgrade() == false)
assert(env.LocalStorage.requireFullReimport == nil)
assert(env.LocalStorage.cacheVersion == 20)
assert(env.LocalStorage.OrderCache["303-1111111-1111111"] ~= nil)

-- Legacy cache without schema version but with old emit markers: full reimport.
env.LocalStorage = {
  OrderCache = {
    ["303-legacy"] = {
      orderCode = "303-legacy",
      emitted = true,
      orderTotal = 1,
    },
  },
}
assert(env.applyImportSchemaUpgrade() == true)
assert(env.LocalStorage.requireFullReimport == true)
assert(env.LocalStorage.OrderCache["303-legacy"] == nil)

-- Empty getOrders table must not force reimport.
env.LocalStorage = {
  OrderCache = {
    ["303-fresh"] = { orderCode = "303-fresh", orderTotal = 1 },
  },
  getOrders = {},
}
assert(env.applyImportSchemaUpgrade() == false)
assert(env.LocalStorage.requireFullReimport == nil)
assert(env.LocalStorage.OrderCache["303-fresh"] ~= nil)

-- Return-only legacy marker (with empty refundTransactions) still requires reimport.
env.LocalStorage = {
  OrderCache = {
    ["303-retlegacy"] = {
      orderCode = "303-retlegacy",
      refundTransactions = {},
      returns = {
        [1] = {
          [100] = {
            ["Item"] = { since = 0 },
          },
        },
      },
    },
  },
}
assert(env.applyImportSchemaUpgrade() == true)
assert(env.LocalStorage.requireFullReimport == true)

-- Upgrade from an older numbered schema: wipe plugin cache and block emit.
env.LocalStorage = {
  cacheVersion = 19,
  OrderCache = {
    ["303-old"] = { orderCode = "303-old", orderTotal = 1 },
  },
  balancesByPeriod = { mix = { ["2026-08"] = { 1 } } },
  lastHarvestSince = 1,
  cookies = "keep-me",
}
assert(env.applyImportSchemaUpgrade() == true)
assert(env.LocalStorage.requireFullReimport == true)
assert(env.LocalStorage.OrderCache["303-old"] == nil)
assert(env.LocalStorage.balancesByPeriod == nil)
assert(env.LocalStorage.lastHarvestSince == nil)
assert(env.LocalStorage.cookies == "keep-me", "login session must survive schema wipe")
assert(env.LocalStorage.cacheVersion == 20)

skipHarvest()
local blocked = env.RefreshAccount(account, since)
assert(blocked.balance == 0)
assert(blocked.transactions == nil or #blocked.transactions == 0,
  "must not emit while full reimport is required")

-- resetCache (same helper RefreshAccount uses) acknowledges the wipe.
env.resetImportState(false)
assert(env.LocalStorage.requireFullReimport == nil)

-- Clean harvest result, then emit.
env.LocalStorage.OrderCache = {
  ["303-1111111-1111111"] = {
    orderCode = "303-1111111-1111111",
    orderPositions = { { purpose = "Item", amount = 1640, qty = 1 } },
    orderSum = 1640,
    orderTotal = 1640,
    bookingDate = os.time({ year = 2026, month = 8, day = 20 }),
    detailsDate = os.time() + 86400,
    subAccountKind = "business",
  },
}
skipHarvest()
local released = env.RefreshAccount(account, since)
local n = 0
for _, tx in ipairs(released.transactions) do
  if tx.endToEndReference == "303-1111111-1111111" then
    n = n + 1
  end
end
assert(n == 1, "after resetCache the clean cache must emit")

print("test_full_reimport OK")
