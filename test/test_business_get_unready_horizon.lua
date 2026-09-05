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

print("test_business_get_unready_horizon OK")
