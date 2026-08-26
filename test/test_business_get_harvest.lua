-- Business SPA must harvest via GET timeFilter, never POST orderHistory (403 aborts MM).
-- Run: test/run.sh test/test_business_get_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1 }

local spaFile = assert(io.open("test/fixtures/ab_your_orders_spa.html", "rb"))
local spaHtml = spaFile:read("*all")
spaFile:close()
local spa = mm.HTML(spaHtml)

assert(env.isAmazonBusinessOrdersSpa(spa) == true)
assert(env.orderListPageReady(spa) == false)

local cssUrl = env.buildCssOrderHistoryUrl("year-2025")
assert(cssUrl:find("/gp/css/order-history", 1, true))
assert(cssUrl:find("ref_=nav_orders_first", 1, true))
assert(cssUrl:find("timeFilter=year-2025", 1, true))

local url = env.buildYourOrdersTimeFilterUrl("year-2025")
assert(url:find("timeFilter=year-2025", 1, true))
assert(url:find("ref_=ppx_yo2ov_dt_b_filter_all", 1, true))

local classic = env.buildClassicOrderFilterUrl("months-3")
assert(classic:find("orderFilter=months-3", 1, true))

local filters = env.enumerateYourOrdersGetFilters()
assert(#filters >= 3)
assert(filters[1].val == "last30")
assert(filters[2].val == "months-3")

local gets = {}
local posts = {}
env.connectShop = function(method, urlArg)
  if type(method) == "string" and method == "GET" then
    table.insert(gets, urlArg)
    return mm.HTML([[
<html><body>
<form action="/your-orders/orders"><select name="timeFilter">
<option value="year-2025" selected>2025</option>
</select></form>
<div class="order-card js-order-card"
     data-csa-c-slot-id="amzn1.yourorders.order-card.302-9999999-8888888"></div>
</body></html>]])
  end
  return spa
end
env.connectShopRaw = function(method, urlArg, postContent, contentType, headers)
  table.insert(posts, { method = method, url = urlArg })
  error("orderHistory POST must not be used for Business SPA harvest")
end
env.HTML = mm.HTML
env.isAkamaiInterstitial = function() return false end

local n = env.collectOrdersViaYourOrdersGet("Altanis GmbH", "business")
assert(n >= 1, "expected GET harvest new orders, got " .. tostring(n))
assert(#posts == 0, "must not POST orderHistory, posts=" .. tostring(#posts))
assert(#gets >= 1, "expected at least one GET timeFilter")
local sawCss = false
for _, u in ipairs(gets) do
  if type(u) == "string" and u:find("/gp/css/order-history", 1, true) then
    sawCss = true
  end
end
assert(sawCss, "expected css order-history GET URL")

print("test_business_get_harvest OK")
