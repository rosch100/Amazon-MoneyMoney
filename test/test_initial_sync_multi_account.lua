-- Erstimport completes for accounts MoneyMoney actually refreshes (not all ListAccounts entries).
-- Run: test/run.sh test/test_initial_sync_multi_account.lua
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

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Persönliches Konto" },
  { kind = "business", label = "Example GmbH" },
})

env.ListAccounts({})
env.EndSession()

assert(env.LocalStorage.initialSyncExpectedAccounts == nil,
  "must not pre-seed expected accounts from ListAccounts")

local function mockCompleteScan()
  env.scanAllAmazonSubAccounts = function()
    env.LocalStorage.subAccountScan = {
      phase = "done",
      incomplete = false,
      totalNew = 0,
    }
    return 0, nil
  end
end

mockCompleteScan()

local mix = { accountNumber = "mix", owner = "test@example.com" }
env.RefreshAccount(mix, 0)
assert(env.isPendingInitialSync() == false,
  "mix-only setup must complete without refreshing undiscovered sub accounts")

env.LocalStorage.pendingInitialSync = true
env.LocalStorage.initialSyncHarvestDone = true
env.LocalStorage.initialSyncRefreshedAccounts = nil

local business = { accountNumber = "sub:business", owner = "test@example.com" }
env.RefreshAccount(business, 0)
assert(env.isPendingInitialSync() == true,
  "business-only refresh must keep Erstimport pending while personal is missing")

local personal = { accountNumber = "sub:personal", owner = "test@example.com" }
env.RefreshAccount(personal, 0)
assert(env.isPendingInitialSync() == false,
  "refreshing both enabled sub-accounts completes Erstimport")

print("test_initial_sync_multi_account OK")
