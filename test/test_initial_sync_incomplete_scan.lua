-- Incomplete sub-account scan must not mark initial harvest done.
-- Run: test/run.sh test/test_initial_sync_incomplete_scan.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end

env.LocalStorage = {
  loginCounter = 1,
  lastLoginCounter = 0,
  OrderCache = {},
}

local account = { accountNumber = "test@example.com", owner = "test@example.com" }

env.ListAccounts({})
env.EndSession()

env.scanAllAmazonSubAccounts = function()
  env.LocalStorage.subAccountScan = {
    phase = "done",
    incomplete = true,
    totalNew = 0,
  }
  return 0, nil
end

env.RefreshAccount(account, now - 86400)
assert(env.isPendingInitialSync() == true, "pending must stay while scan incomplete")
assert(env.isInitialSyncHarvestDone() ~= true, "incomplete scan must not mark harvest done")
assert(env.LocalStorage.lastHarvestSince == nil, "incomplete scan must not update lastHarvestSince")

print("test_initial_sync_incomplete_scan OK")
