-- Business GET year filters that never become ready must not leave harvest sticky-incomplete.
-- Run: test/run.sh test/test_business_get_unready_horizon.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua", {
  OrderCache = {},
  orderFilterCacheByAccount = {},
  orderListHarvestIncompleteByAccount = {},
})
env.secUsername = "test@example.com"

local spaShell = mm.HTML([[
<html><body>
  <div id="yourOrders">SPA shell without order cards</div>
</body></html>
]])

env.loadYourOrdersFilterPage = function()
  return spaShell
end
env.orderListPageReady = function()
  return false
end
env.enumerateYourOrdersGetFiltersForAbaGap = function()
  return {
    { val = "year-2024", label = "2024" },
    { val = "year-2023", label = "2023" },
    { val = "year-2022", label = "2022" },
  }
end
env.MM.printStatus = function() end

local label = "Altanis GmbH"
local newCount = env.collectOrdersViaYourOrdersGet(label, "business", 0, {
  fullHarvest = true,
  abaGapOnly = true,
})
assert(newCount == 0, "unready SPA years must harvest zero orders")
assert(env.isOrderListHarvestIncomplete(label) ~= true,
  "after unready horizon, business must not stay sticky-incomplete")
assert(env.hasMoreBusinessOrdersToHarvest(label, 0, os.time()) ~= true,
  "abandoned unready year filters must not report more business harvest work")

-- Mixed path: at least one ready year, then unready horizon — remaining years abandoned.
env.LocalStorage = {
  OrderCache = {},
  orderFilterCacheByAccount = {},
  orderListHarvestIncompleteByAccount = {},
}
local readyShell = mm.HTML([[
<html><body>
  <div class="order-card" data-csa-c-slot-id="amzn1.yourorders.order-card.303-0000000-0000001"></div>
</body></html>
]])
local loads = 0
env.loadYourOrdersFilterPage = function()
  loads = loads + 1
  if loads == 1 then
    return readyShell
  end
  return spaShell
end
env.orderListPageReady = function(page)
  return page == readyShell
end
env.scanOrderFilterPages = function(orderFilterVal, orderCache, orderFilterCache)
  orderFilterCache[orderFilterVal] = true
  return 1, 1, 1, true
end
env.enumerateYourOrdersGetFiltersForAbaGap = function()
  return {
    { val = "year-2024", label = "2024" },
    { val = "year-2023", label = "2023" },
    { val = "year-2022", label = "2022" },
  }
end

local mixedLabel = "Example GmbH"
local mixedCount = env.collectOrdersViaYourOrdersGet(mixedLabel, "business", 0, {
  fullHarvest = true,
  abaGapOnly = true,
})
assert(mixedCount == 1, "mixed path must keep the ready-year harvest count")
assert(env.isOrderListHarvestIncomplete(mixedLabel) ~= true,
  "fullHarvest must not sticky-mark incomplete for abandoned unready years")
local mixedCache = env.filterCacheForSubAccount(mixedLabel)
assert(mixedCache["year-2024"] == true, "ready year must stay marked complete")
assert(mixedCache["year-2023"] == true, "unready year after horizon must be abandoned")
assert(mixedCache["year-2022"] == true, "remaining year filters must be abandoned")

print("test_business_get_unready_horizon OK")
