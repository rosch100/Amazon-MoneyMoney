-- Erstimport completes for accounts MoneyMoney actually refreshes (not all ListAccounts entries).
-- Run: test/run.sh test/test_initial_sync_multi_account.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"
env.shouldPersistAmazonLoginSession = function()
  return true
end
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.scanAllAmazonSubAccounts = function()
  env.LocalStorage.subAccountScan = {
    phase = "done",
    incomplete = false,
    totalNew = 0,
  }
  return 0, nil
end

env.LocalStorage = {
  loginCounter = 1,
  lastLoginCounter = 0,
  OrderCache = {},
}

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Persönliches Konto", customerName = "Persönliches Konto",
    accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
})

env.ListAccounts({})
env.clearAccountSetupState()

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

local combined = { accountNumber = "test@example.com", owner = "test@example.com" }
combined.attributes = { reallyLogout = "false" }
env.RefreshAccount(combined, 0)
assert(env.isPendingInitialSync() == false,
  "combined-only setup must complete without refreshing undiscovered sub accounts")
env.EndSession()

env.LocalStorage.pendingInitialSync = true
env.LocalStorage.initialSyncHarvestDone = true
env.LocalStorage.initialSyncRefreshedAccounts = nil
env.LocalStorage.OrderCache = {
  ["303-business-complete"] = {
    orderCode = "303-business-complete",
    accountNumber = "A3BUSINESSID02",
    subAccountKind = "business",
    bookingDate = now,
    detailsDate = now + 86400,
    detailsParsed = true,
    orderTotal = 100,
    orderPositions = { { purpose = "Business item", amount = 100, qty = 1 } },
  },
  ["303-personal-open"] = {
    orderCode = "303-personal-open",
    accountNumber = "A3PERSONALID01",
    subAccountKind = "personal",
    bookingDate = now,
    detailsDate = now - 1,
  },
}

local business = { accountNumber = "AO.3BUSINESSID02", owner = "test@example.com" }
business.attributes = { reallyLogout = "false" }
env.RefreshAccount(business, 0)
assert(env.isPendingInitialSync() == true,
  "single sub-account must defer completion until the selected set is known")
env.EndSession()
assert(env.isPendingInitialSync() == false,
  "single selected sub-account must complete once its initial sync is done")
assert(env.LocalStorage.OrderCache["303-personal-open"].detailsDate == now - 1,
  "unselected sub-account details must not block this account's initial sync")
assert(env.effectiveRefreshSince(now - 86400) == now - 86400,
  "completed selected account must return to regular incremental refresh")

env.LocalStorage.pendingInitialSync = true
env.LocalStorage.initialSyncHarvestDone = true
env.LocalStorage.initialSyncRefreshedAccounts = nil
env.LocalStorage.OrderCache["303-personal-open"].detailsDate = now + 86400
env.LocalStorage.OrderCache["303-personal-open"].detailsParsed = true
local personal = { accountNumber = "AO.3PERSONALID01", owner = "test@example.com" }
personal.attributes = { reallyLogout = "false" }
business.attributes = { reallyLogout = "false" }
env.recordInitialSyncAccountRefresh(personal.accountNumber)
env.EndSession()
assert(env.isPendingInitialSync() == false,
  "the other selected sub-account can complete its own initial refresh")

print("test_initial_sync_multi_account OK")
