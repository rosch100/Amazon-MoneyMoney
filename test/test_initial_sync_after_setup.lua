-- Picker RefreshAccount must not import. After EndSession the next RefreshAccount
-- full-harvests (since=0).
-- Run: test/run.sh test/test_initial_sync_after_setup.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.getOrderDetails = function()
end

env.LocalStorage = {

  cacheVersion = 22,
  loginCounter = 1,
  lastLoginCounter = 0,
  OrderCache = {
    ["303-setup-1"] = {
      orderCode = "303-setup-1",
      orderPositions = { { purpose = "Setup item", amount = 1000, qty = 1 } },
      orderSum = 1000,
      orderTotal = 1000,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      subAccountKind = "business",
    },
  },
}

local account = {
  accountNumber = "mix",
  owner = "test@example.com",
}

env.ListAccounts({})
assert(env.isAccountSetupSession() == true)
assert(env.isPendingInitialSync() == true)

local harvestSince = nil
env.scanAllAmazonSubAccounts = function()
  harvestSince = env.LocalStorage.refreshSince
  env.LocalStorage.subAccountScan = {
    phase = "done",
    incomplete = false,
    totalNew = 0,
  }
  return 0, nil
end

local probe = env.RefreshAccount(account, 0)
assert(harvestSince == nil, "picker RefreshAccount must not harvest")
assert(type(probe) == "table", "picker RefreshAccount must succeed")
assert(#probe.transactions == 0, "picker RefreshAccount must not emit bookings")

env.clearAccountSetupState()
assert(env.isPendingInitialSync() == true, "pending survives EndSession")

local harvestMarkedDone = false
local origMark = env.markInitialSyncHarvestDone
env.markInitialSyncHarvestDone = function()
  harvestMarkedDone = true
  return origMark()
end

env.LocalStorage.loginCounter = 2
local recentSince = now - (30 * 24 * 60 * 60)
local result = env.RefreshAccount(account, recentSince)
assert(type(result) == "table")
assert(harvestSince == 0, "post-create RefreshAccount must force since=0, got " .. tostring(harvestSince))
assert(#result.transactions > 0, "post-create RefreshAccount must emit bookings")
assert(harvestMarkedDone == true, "harvest success must mark initial sync harvest done")
assert(env.LocalStorage.lastHarvestSince == 0, "lastHarvestSince records full import")
assert(env.isPendingInitialSync() == false, "pending cleared when no details remain")

-- Pending details block clearing initial sync until resolved.
env.LocalStorage.pendingInitialSync = true
env.LocalStorage.initialSyncHarvestDone = true
env.LocalStorage.initialSyncRefreshedAccounts = { mix = "mix" }
env.LocalStorage.OrderCache["303-open-details"] = {
  orderCode = "303-open-details",
  orderPositions = { { purpose = "Open", amount = 100, qty = 1 } },
  orderSum = 100,
  orderTotal = 100,
  bookingDate = now,
  detailsDate = now - 1,
  subAccountKind = "business",
}
env.RefreshAccount(account, recentSince)
assert(env.isPendingInitialSync() == true, "pending stays while details are open")
env.LocalStorage.OrderCache["303-open-details"].detailsDate = now + 86400
env.LocalStorage.OrderCache["303-open-details"].detailsParsed = true
env.RefreshAccount(account, recentSince)
assert(env.isPendingInitialSync() == false, "pending clears after details are done")

print("test_initial_sync_after_setup OK")
