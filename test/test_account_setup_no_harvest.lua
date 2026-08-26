-- Konten einrichten: ListAccounts sets setup session; RefreshAccount skips harvest and emit.
-- Run: test/run.sh test/test_account_setup_no_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.LocalStorage = {
  loginCounter = 2,
  lastLoginCounter = 1,
  OrderCache = {},
}

local account = {
  accountNumber = "mix",
  owner = "test@example.com",
  name = "Amazon test",
}

assert(env.shouldRunAccountHarvest(0, now) == true, "normal refresh after login should harvest")

env.ListAccounts({})
assert(env.isAccountSetupSession() == true)
assert(env.isPendingInitialSync() == true, "setup must flag pending initial sync")
assert(env.shouldRunAccountHarvest(0, now) == false, "setup must not harvest")

-- Setup must work even before loginCounter is assigned (ListAccounts edge case).
env.clearAccountSetupState()
env.LocalStorage.loginCounter = nil
env.ListAccounts({})
assert(env.isAccountSetupSession() == true, "setup active without loginCounter")
local noCounter = env.RefreshAccount(account, 0)
assert(#noCounter.transactions == 0, "setup without loginCounter must not emit")
env.EndSession()

env.ListAccounts({})
assert(env.isAccountSetupSession() == true)

local harvestCalled = false
env.scanAllAmazonSubAccounts = function()
  harvestCalled = true
  return 0, nil
end

local result = env.RefreshAccount(account, 0)
assert(type(result) == "table", "setup refresh returns table, got " .. type(result))
assert(harvestCalled == false, "setup RefreshAccount must not scan orders")
assert(#result.transactions == 0, "setup must return no transactions")
assert(env.LocalStorage.lastLoginCounter == 1, "setup must not consume login counter")

-- Populated cache must not emit during setup either.
env.LocalStorage.OrderCache = {
  ["303-cached-1111111"] = {
    orderCode = "303-cached-1111111",
    orderPositions = { { purpose = "Cached", amount = 1000, qty = 1 } },
    orderSum = 1000,
    orderTotal = 1000,
    bookingDate = now,
    detailsDate = now + 86400,
    emittedAccounts = { mix = true },
  },
}
local cached = env.RefreshAccount(account, 0)
assert(#cached.transactions == 0, "setup must not emit cached orders")

env.EndSession()
assert(env.isAccountSetupSession() == false)
assert(env.isPendingInitialSync() == true, "EndSession keeps pending until first post-setup refresh")
assert(env.shouldRunAccountHarvest(0, now) == true, "after EndSession harvest allowed again")

-- Stale setup flag from another login is ignored.
env.LocalStorage.loginCounter = 2
env.beginAccountSetupSession(true)
env.LocalStorage.loginCounter = 3
assert(env.isAccountSetupSession() == false)
env.clearAccountSetupState()

print("test_account_setup_no_harvest OK")
