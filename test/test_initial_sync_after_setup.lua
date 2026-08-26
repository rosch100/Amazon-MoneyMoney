-- After Konten einrichten the first RefreshAccount must full-harvest from the beginning.
-- Run: test/run.sh test/test_initial_sync_after_setup.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end

env.LocalStorage = {
  loginCounter = 1,
  lastLoginCounter = 0,
  OrderCache = {},
}

local account = {
  accountNumber = "mix",
  owner = "test@example.com",
}

env.ListAccounts({})
assert(env.isAccountSetupSession() == true)
assert(env.isPendingInitialSync() == true)

local setupHarvest = false
env.scanAllAmazonSubAccounts = function()
  setupHarvest = true
  return 0, nil
end
env.RefreshAccount(account, 0)
assert(setupHarvest == false, "setup RefreshAccount must not harvest")

env.EndSession()
assert(env.isPendingInitialSync() == true, "pending survives EndSession")

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

local harvestMarkedDone = false
local origMark = env.markInitialSyncHarvestDone
env.markInitialSyncHarvestDone = function()
  harvestMarkedDone = true
  return origMark()
end

local recentSince = now - (30 * 24 * 60 * 60)
local result = env.RefreshAccount(account, recentSince)
assert(type(result) == "table")
assert(harvestSince == 0, "initial sync must force since=0, got " .. tostring(harvestSince))
assert(harvestMarkedDone == true, "harvest success must mark initial sync harvest done")
assert(env.isPendingInitialSync() == false, "pending cleared when no details remain")
assert(env.LocalStorage.lastHarvestSince == 0, "lastHarvestSince records full import")

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
env.RefreshAccount(account, recentSince)
assert(env.isPendingInitialSync() == false, "pending clears after details are done")

print("test_initial_sync_after_setup OK")
