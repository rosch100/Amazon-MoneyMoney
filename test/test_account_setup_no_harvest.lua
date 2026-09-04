-- Konten einrichten: ListAccounts + RefreshAccount only discover accounts.
-- Erstimport runs on the first RefreshAccount after EndSession (Kontenrundruf).
-- "Nach neuen Konten suchen" still skips harvest.
-- Run: test/run.sh test/test_account_setup_no_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.getOrderDetails = function()
end

env.LocalStorage = {

  cacheVersion = 22,
  loginCounter = 2,
  lastLoginCounter = 1,
  OrderCache = {},
}

local mix = {
  accountNumber = "mix",
  owner = "test@example.com",
  name = "Amazon test",
}

assert(env.shouldRunAccountHarvest(0, now) == true, "normal refresh after login should harvest")

env.ListAccounts({})
assert(env.isAccountSetupSession() == true)
assert(env.isPendingInitialSync() == true, "setup must flag pending initial sync")
assert(env.shouldRunAccountHarvest(0, now) == false, "finder must not harvest")

local harvestCalled = false
env.scanAllAmazonSubAccounts = function()
  harvestCalled = true
  env.LocalStorage.subAccountScan = {
    phase = "done",
    incomplete = false,
    totalNew = 0,
  }
  return 0, nil
end

env.LocalStorage.OrderCache = {
  ["303-new-1111111"] = {
    orderCode = "303-new-1111111",
    orderPositions = { { purpose = "New item", amount = 1000, qty = 1 } },
    orderSum = 1000,
    orderTotal = 1000,
    bookingDate = now,
    detailsDate = now + 86400,
    detailsParsed = true,
    subAccountKind = "business",
  },
}

local result = env.RefreshAccount(mix, now - (7 * 24 * 60 * 60))
assert(type(result) == "table", "finder refresh must succeed")
assert(#result.transactions == 0, "finder must not emit bookings")
assert(harvestCalled == false, "finder must not scan orders")
assert(env.LocalStorage.lastLoginCounter == 1, "finder must not consume login counter")
assert(env.isPendingInitialSync() == true, "pending survives finder")

env.clearAccountSetupState()
assert(env.isAccountSetupSession() == false)
assert(env.isPendingInitialSync() == true, "pending survives EndSession")
assert(env.shouldRunAccountHarvest(0, now) == true, "Erstimport after create must harvest")

local imported = env.RefreshAccount(mix, now - (7 * 24 * 60 * 60))
assert(harvestCalled == true, "post-create RefreshAccount must scan orders")
assert(#imported.transactions > 0, "post-create RefreshAccount must emit bookings")
assert(env.LocalStorage.lastHarvestSince == 0, "Erstimport records since=0")

-- Nach neuen Konten suchen: already harvested → no full scrape.
env.LocalStorage.lastHarvestSince = 0
env.clearPendingInitialSync()
env.clearAccountSetupState()
harvestCalled = false
env.ListAccounts({ "test@example.com" })
assert(env.isAccountSetupSession() == true)
assert(env.isPendingInitialSync() == false, "account search must not start Erstimport")
assert(env.shouldRunAccountHarvest(now - 86400, now) == false, "account search must not harvest")
local search = env.RefreshAccount(mix, now - 86400)
assert(harvestCalled == false, "account search RefreshAccount must not scan orders")
assert(#search.transactions == 0, "account search must not emit")

env.clearAccountSetupState()
env.LocalStorage.loginCounter = 2
env.beginAccountSetupSession(true)
env.LocalStorage.loginCounter = 3
assert(env.isAccountSetupSession() == false)
env.clearAccountSetupState()

print("test_account_setup_no_harvest OK")
