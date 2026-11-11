-- Faster incremental refresh: skip warm discovery switches, months-3 when
-- scanMonths<3, details-only when list scan is fresh, business ABA without SPA probes.
-- Run: test/run.sh test/test_incremental_session_optimizations.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local now = os.time()
local day = 24 * 60 * 60
-- Production stores MoneyMoney "since" in lastHarvestSince (often days ago),
-- and wall-clock of the last list scan in lastListHarvestAt.
local moneyMoneySince = now - 16 * day

local env = mm.loadPlugin("amazon-bestellungen.lua", {
  cacheVersion = 23,
  OrderCache = {
    ["303-1111111-2222222"] = {
      orderCode = "303-1111111-2222222",
      bookingDate = now - day,
      orderTotal = 1,
    },
  },
  lastHarvestSince = moneyMoneySince,
  lastHarvestScanMonths = 0,
  lastListHarvestAt = now - 60,
  loginCounter = 2,
  lastLoginCounter = 2,
  discoveredSubAccounts = {
    {
      kind = "personal",
      label = "Persönliches Konto",
      accountNumber = "A1PERSONALID0001",
      customerName = "Max Mustermann",
    },
    {
      kind = "business",
      label = "Biz",
      accountNumber = "A1BUSINESSID0001",
      businessName = "Altanis GmbH",
    },
  },
})
env.secUsername = "test@example.com"

assert(env.canReuseDiscoveredSubAccountsWithoutSwitcher() == true,
  "complete accountNumber cache must reuse without switcher")

-- Point 3: months-3 not recent when scanMonths=1
assert(env.isRecentOrderFilter("last30", 1) == true)
assert(env.isRecentOrderFilter("months-3", 1) ~= true)
assert(env.isRecentOrderFilter("months-3", 3) == true)
assert(env.isRecentOrderFilter("months-3", nil) == true)

local filters = env.recentYourOrdersGetFilters(1)
assert(#filters == 1 and filters[1].val == "last30")
filters = env.recentYourOrdersGetFilters(3)
assert(#filters == 2)

-- Point 1: details-only uses lastListHarvestAt (wall clock), not lastHarvestSince watermark
env.LocalStorage.lastHarvestSince = moneyMoneySince
env.LocalStorage.lastListHarvestAt = now - 60
env.LocalStorage.loginCounter = 2
env.LocalStorage.lastLoginCounter = 2
env.LocalStorage.orderListHarvestIncompleteByAccount = {}
assert(env.orderCacheHasOrders() == true)
assert(env.isIncrementalMoneyMoneyRefresh(moneyMoneySince, now) == true)
assert(env.listHarvestDueForPeriodicRescan(moneyMoneySince, now) == true,
  "MoneyMoney since watermark must not be treated as wall-clock scan time")
assert(env.incrementalListHarvestNeeded(moneyMoneySince, now) ~= true)
assert(env.shouldRunAccountHarvest(moneyMoneySince, now) ~= true)

-- Same details-only skip after a new login (loginCounter bump must not force list harvest)
env.LocalStorage.loginCounter = 3
env.LocalStorage.lastLoginCounter = 2
assert(env.shouldRunAccountHarvest(moneyMoneySince, now) ~= true,
  "warm list scan must stay details-only across re-login")

-- Stale wall-clock list scan forces harvest even when since watermark is unchanged
env.LocalStorage.lastListHarvestAt = now - (5 * 60 * 60)
assert(env.incrementalListHarvestNeeded(moneyMoneySince, now) == true)
assert(env.shouldRunAccountHarvest(moneyMoneySince, now) == true,
  "stale list scan after login must harvest")

-- Point 2: discovery without switcher when cache complete
local opened = false
env.openAccountSwitcherEmbed = function()
  opened = true
  error("switcher must not open when discovery is reused")
end
local options, err = env.discoverAmazonSubAccounts("x", { reuseCustomerIds = true })
assert(err == nil, tostring(err))
assert(#options == 2)
assert(opened == false)

-- Point 5: ensureAmazonSubAccountSession no-ops when HTML already matches kind
local switched = false
env.bindActiveHtml(mm.HTML([[
<html><body><span class="abnav-accountfor">Altanis</span></body></html>
]]))
env.openAccountSwitcherEmbed = function()
  switched = true
  error("must not open switcher when already business")
end
assert(env.ensureAmazonSubAccountSession("business") == nil)
assert(switched == false)

-- Point 4: incremental business skips enterOrderList
local entered = false
env.enterOrderList = function()
  entered = true
end
env.collectBusinessSpaOrders = function(label, kind, refreshSince)
  assert(kind == "business")
  return 0, nil
end
env.LocalStorage.refreshSince = moneyMoneySince
local n, e = env.collectOrdersFromOrderList("Biz", "business", moneyMoneySince)
assert(e == nil)
assert(n == 0)
assert(entered == false)

-- Expanding a completed scan window must bypass the details-only/incremental paths.
env.applyAccountAttribute("scanFiltersMonths", "0", true)
env.LocalStorage.lastHarvestScanMonths = 0
env.LocalStorage.lastListHarvestAt = now - 60
assert(env.isIncrementalMoneyMoneyRefresh(moneyMoneySince, now) == true,
  "unchanged scan window should retain details-only optimization")
env.LocalStorage.lastHarvestScanMonths = 6
env.applyAccountAttribute("scanFiltersMonths", "24", true)
assert(env.isIncrementalMoneyMoneyRefresh(moneyMoneySince, now) == false,
  "expanding the saved scan window must force full-harvest routing")
assert(env.shouldRunAccountHarvest(moneyMoneySince, now) == true,
  "expanding the saved scan window must bypass details-only optimization")

env.LocalStorage.lastHarvestScanMonths = nil
env.LocalStorage.abaFullHarvestScanMonths = 24
env.LocalStorage.abaFullHarvestHasMore = true
env.LocalStorage.abaFullHarvestJobs = { { span = "PAST_12_MONTHS" } }
env.LocalStorage.abaFullHarvestJobIndex = 1
env.LocalStorage.abaFullHarvestHarvestSince = moneyMoneySince
assert(env.isIncrementalMoneyMoneyRefresh(moneyMoneySince, now) == false,
  "an active ABA batch must not count as a completed scan window")

env.LocalStorage.subAccountScan = {
  phase = "done",
  totalNew = 1,
  incomplete = false,
  loginCounter = env.LocalStorage.loginCounter,
  harvestSince = moneyMoneySince,
  harvestScanMonths = 6,
}
env.LocalStorage.refreshSince = moneyMoneySince
assert(env.resolveSubAccountScanCache() == nil,
  "completed sub-account scan with a narrower window must not be reused")
assert(env.LocalStorage.subAccountScan == nil,
  "stale sub-account scan state must be discarded when the window expands")

print("test_incremental_session_optimizations OK")
