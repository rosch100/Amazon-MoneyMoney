-- Business last30 is SPA-only; older orders still live on year GET filters.
-- A last30 SPA probe must not skip year-YYYY harvest.
-- Run: test/run.sh test/test_business_get_gap_years_despite_spa.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1 }

local spaFile = assert(io.open("test/fixtures/ab_your_orders_spa.html", "rb"))
local spaHtml = spaFile:read("*all")
spaFile:close()

local yearHtml = [[
<html><body>
<form action="/your-orders/orders"><select name="timeFilter">
<option value="year-2023" selected>2023</option>
</select></form>
<div class="order-card js-order-card"
     data-csa-c-slot-id="amzn1.yourorders.order-card.302-2023000-1111111"></div>
</body></html>
]]

local gets = {}
env.connectShop = function(method, urlArg)
  if type(method) == "string" and method == "GET" and type(urlArg) == "string" then
    gets[#gets + 1] = urlArg
    if urlArg:find("year-2023", 1, true) then
      return mm.HTML(yearHtml)
    end
    return mm.HTML(spaHtml)
  end
  return mm.HTML(spaHtml)
end
env.connectShopRaw = function()
  error("orderHistory POST must not be used for Business SPA harvest")
end
env.HTML = mm.HTML
env.isAkamaiInterstitial = function() return false end

assert(env.businessGetHarvestBlockedBySpaShell() == true,
  "last30 probe is SPA for this fixture")

local n = env.collectOrdersViaYourOrdersGet("Altanis GmbH", "business", 0, {
  fullHarvest = true,
  abaGapOnly = true,
})
assert(n >= 1, "year GET harvest must run despite last30 SPA, got " .. tostring(n))
assert(env.LocalStorage.OrderCache["302-2023000-1111111"] ~= nil)

local sawYear = false
for _, url in ipairs(gets) do
  if url:find("year%-2023") then
    sawYear = true
  end
end
assert(sawYear, "expected a year-2023 GET, urls=" .. table.concat(gets, " | "))

print("test_business_get_gap_years_despite_spa OK")
