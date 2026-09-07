-- subAccountScan must re-run when MoneyMoney passes a new refreshSince in the same login session.
-- Run: test/run.sh test/test_sub_account_scan_refresh.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = {
  loginCounter = 1,
  refreshSince = 1000,
  subAccountScan = {
    phase = "done",
    loginCounter = 1,
    harvestSince = 1000,
    totalNew = 3,
    incomplete = false,
  },
}

assert(env.subAccountScanMatchesRefresh(env.LocalStorage.subAccountScan) == true)

env.LocalStorage.refreshSince = 2000
assert(env.subAccountScanMatchesRefresh(env.LocalStorage.subAccountScan) == false)

env.LocalStorage.subAccountScan = {
  phase = "done",
  loginCounter = 1,
  harvestSince = 2000,
  totalNew = 7,
  incomplete = false,
}
env.LocalStorage.refreshSince = 2000
assert(env.resolveSubAccountScanCache() == 7)

env.LocalStorage.refreshSince = 3000
assert(env.resolveSubAccountScanCache() == nil)

-- Legacy scan state without harvestSince is treated as stale.
env.LocalStorage.subAccountScan = {
  phase = "done",
  loginCounter = 1,
  totalNew = 3,
  incomplete = false,
}
env.LocalStorage.refreshSince = 1000
assert(env.subAccountScanMatchesRefresh(env.LocalStorage.subAccountScan) == false)

local now = os.time()
local gapFilters = env.enumerateYourOrdersGetFiltersForAbaGap(now)
assert(#gapFilters >= 1, "expected year filters outside ABA window")
for _, item in ipairs(gapFilters) do
  assert(item.val:match("^year%-"), "gap filter must be year-*: " .. tostring(item.val))
  assert(item.val ~= "last30" and item.val ~= "months-3")
end

local fullFilters = env.enumerateYourOrdersGetFilters(nil, now)
assert(#fullFilters > #gapFilters, "full harvest includes recent windows beyond ABA gap years")

print("test_sub_account_scan_refresh OK")
