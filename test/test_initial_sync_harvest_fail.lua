-- Initial sync must not clear pending when harvest fails.
-- Run: test/run.sh test/test_initial_sync_harvest_fail.lua
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

local account = { accountNumber = "mix", owner = "test@example.com" }

env.ListAccounts({})
env.EndSession()

env.scanAllAmazonSubAccounts = function()
  return nil, "network error"
end
env.RefreshAccount(account, now - 86400)
assert(env.isPendingInitialSync() == true, "pending must survive harvest error")
assert(env.isInitialSyncHarvestDone() ~= true, "failed harvest must not mark done")
assert(env.LocalStorage.lastHarvestSince == nil, "failed harvest must not update lastHarvestSince")

print("test_initial_sync_harvest_fail OK")
