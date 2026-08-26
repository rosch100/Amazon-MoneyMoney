-- Amazon Business SPA detection (no orderHistory POST – fatal in MoneyMoney).
-- Run: test/run.sh test/test_ab_order_history.lua
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
assert(env.isLoggedInOrderLanding(spa) == true, "Business SPA must count as logged-in landing")
assert(env.isLoggedInOrderLanding(mm.HTML("<html><body><form name='signIn'></form></body></html>")) == false)

assert(env.parseAbYourOrdersContext == nil, "SPA orderHistory context parser must not exist")
assert(env.mergeOrdersFromAbHistoryResponse == nil)
assert(env.collectOrdersFromAbYourOrders == nil)
assert(env.buildAbOrderHistoryPost == nil)
assert(env.fetchAbOrderHistoryHtml == nil)

local histFile = assert(io.open("test/fixtures/ab_order_history_response.html", "rb"))
local histHtml = histFile:read("*all")
histFile:close()
local hist = mm.HTML(histHtml)

local cache = {}
local found, foundNew, n = env.mergeOrdersFromPage(hist, cache, "Example GmbH", "business")
if n == 0 then
  found, foundNew, n = env.mergeOrdersFromRawText(histHtml, cache, "Example GmbH", "business")
end
assert(found == true)
assert(n == 2, "expected 2 new orders, got " .. tostring(n))
assert(cache["303-1111111-2222222"].subAccountKind == "business")
assert(cache["303-3333333-4444444"].accountNumber == "Example GmbH")

print("test_ab_order_history OK")
