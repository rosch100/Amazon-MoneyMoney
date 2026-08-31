-- Tests recent-filter / merge helpers used to keep order lists updating when
-- Amazon's last30 view is empty but months-3 still shows cards.
-- Run: luajit test/test_order_filter_scan.lua
---@diagnostic disable: duplicate-set-field -- Test cases intentionally replace sandbox mocks.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

assert(env.isRecentOrderFilter("last30") == true, "last30 must always rescan")
-- ^last prefix (Amazon ships last30; no separate last3months value)
assert(env.isRecentOrderFilter("last") == true, "^last prefix must match")
assert(env.isRecentOrderFilter("months-3") == true, "months-3 must always rescan")
assert(env.isRecentOrderFilter("year-2026") == false, "year filters stay cacheable")
assert(env.isRecentOrderFilter("months-6") == false, "only months-3 is forced")
assert(env.isRecentOrderFilter(nil) == false, "nil is not recent")
assert(env.isRecentOrderFilter("Letzte 30.Tage") == true, "Business DE 30 days")
assert(env.isRecentOrderFilter("Letzte 3.Monate") == true, "Business DE 3 months")

assert(env.orderListPageReady(nil) == false)
assert(env.orderListPageReady(mm.HTML("<html><body><div class='order-card'></div></body></html>")) == true)
assert(env.orderListPageReady(mm.HTML([[
<html><body>
<form action="/your-orders/orders"><select name="timeFilter"><option value="last30">x</option></select></form>
</body></html>]])) == true)
assert(env.orderListPageReady(mm.HTML("<html><body><div class='skeleton orderCardHeader'></div></body></html>")) == false)

local emptyOrders = env.getOrdersFromSummary(nil)
assert(next(emptyOrders) == nil, "nil html must not crash getOrdersFromSummary")

local selectPage = mm.HTML([[
<html><body>
<form action="/your-orders/orders">
  <select name="timeFilter">
    <option value="last30">den letzten 30 Tagen</option>
    <option value="months-3" selected>den letzten 3 Monaten</option>
    <option value="year-2026">2026</option>
  </select>
</form>
</body></html>]])
assert(env.getSelectedOrderFilter(selectPage) == "months-3", "selected filter must be months-3")
assert(env.getSelectedOrderFilter(nil) == "", "nil html yields empty filter")

local page = [[
<html><body>
<div class="orders-content-container">
  <div class="order-card js-order-card"
       data-csa-c-slot-id="amzn1.yourorders.order-card.302-0322511-4650710"></div>
  <div class="order-card js-order-card"
       data-csa-c-slot-id="amzn1.yourorders.order-card.303-1046514-1028303"></div>
</div>
</body></html>]]

local cache = {}
local foundOrders, foundNewOrders, newCount = env.mergeOrdersFromPage(mm.HTML(page), cache)
assert(foundOrders == true, "expected foundOrders")
assert(foundNewOrders == true, "expected foundNewOrders")
assert(newCount == 2, "expected 2 new orders, got " .. tostring(newCount))
assert(cache["302-0322511-4650710"] ~= nil)
assert(cache["303-1046514-1028303"] ~= nil)

local foundOrders2, foundNewOrders2, newCount2 = env.mergeOrdersFromPage(mm.HTML(page), cache)
assert(foundOrders2 == true, "second pass still finds orders")
assert(foundNewOrders2 == false, "second pass must not count duplicates as new")
assert(newCount2 == 0, "second pass newCount must be 0")

local empty = mm.HTML([[<html><body><div class="orders-content-container"></div></body></html>]])
local fo, fn, nc = env.mergeOrdersFromPage(empty, cache)
assert(fo == false, "empty page must not claim foundOrders")
assert(fn == false, "empty page must not claim foundNewOrders")
assert(nc == 0, "empty page newCount must be 0")

local nilCacheOk, nilCacheErr = pcall(function()
  env.mergeOrdersFromPage(empty, nil)
end)
assert(nilCacheOk == false, "nil orderCache must error")
assert(type(nilCacheErr) == "string" and nilCacheErr:find("orderCache", 1, true),
  "error must mention orderCache, got: " .. tostring(nilCacheErr))

-- Empty year filters must be marked complete; otherwise every refresh re-scrapes
-- year-1995.. and MoneyMoney can OOM (signal 11). See Unhandled Exception log.
local filterCache = {}
assert(env.markOrderFilterCacheIfComplete(filterCache, "year-1995", false) == true)
assert(filterCache["year-1995"] == true, "empty year filter must be cached as done")
assert(env.markOrderFilterCacheIfComplete(filterCache, "year-1996", true) == false)
assert(filterCache["year-1996"] == nil, "years with new orders stay uncached for rescan")
assert(env.markOrderFilterCacheIfComplete(nil, "year-1997", false) == false)
assert(env.markOrderFilterCacheIfComplete({}, "", false) == false)

-- Recent filters are deliberately scanned on every independent refresh, but
-- they are not unfinished batch work after the current refresh scanned them.
env.LocalStorage = { orderFilterCacheByAccount = {} }
env.enumerateYourOrdersGetFilters = function()
  return {
    { val = "last30", label = "den letzten 30 Tagen" },
    { val = "months-3", label = "den letzten 3 Monaten" },
  }
end
assert(env.hasMoreOrderListFiltersToHarvest("Persönliches Konto", 0, os.time()) == false,
  "recent filters alone must not keep the sub-account scan incomplete")

env.setOrderListHarvestIncomplete("Persönliches Konto", false)
env.runOrderFilterHarvest(
  "last30", "den letzten 30 Tagen", {}, "Persönliches Konto", "personal", {
    loadPage = function()
      return nil
    end,
  })
assert(env.hasMoreOrderListFiltersToHarvest("Persönliches Konto", 0, os.time()) == true,
  "failed recent-filter page load must keep the sub-account scan incomplete")

-- A recent filter is only complete when its pagination reached the natural end.
env.setOrderListHarvestIncomplete("Persönliches Konto", false)
env.html = mm.HTML([[
<html><body>
<div class="order-card" data-csa-c-slot-id="amzn1.yourorders.order-card.303-0000000-0000001"></div>
<li class="a-last"><a href="/your-orders/orders?pageNumber=2">Weiter</a></li>
</body></html>]])
env.connectShop = function()
  return nil
end
local _, _, _, paginationComplete = env.scanOrderFilterPages(
  "last30", {}, {}, "Persönliches Konto", "personal")
assert(paginationComplete == false, "failed recent-filter pagination must be incomplete")
assert(env.hasMoreOrderListFiltersToHarvest("Persönliches Konto", 0, os.time()) == true,
  "failed recent-filter pagination must keep the sub-account scan incomplete")

env.setOrderListHarvestIncomplete("Geschäftliches Konto", true)
env.enumerateYourOrdersGetFiltersForAbaGap = function()
  return {}
end
assert(env.subAccountHarvestHasMore(
    "Geschäftliches Konto", "business", os.time() - 86400, os.time()) == true,
  "failed business order-list harvest must keep the sub-account scan incomplete")

env.LocalStorage = { orderFilterCacheByAccount = {} }
env.enumerateYourOrdersGetFilters = function()
  return {
    { val = "year-2024", label = "2024" },
    { val = "year-2023", label = "2023" },
    { val = "year-2022", label = "2022" },
  }
end
env.loadYourOrdersFilterPage = function()
  return mm.HTML("<html><body><div>temporarily unavailable</div></body></html>")
end
env.collectOrdersViaYourOrdersGet("Geschäftliches Konto", "business", 0, {})
local failedFilterCache = env.filterCacheForSubAccount("Geschäftliches Konto")
assert(next(failedFilterCache) == nil,
  "unready filters and skipped horizon filters must remain retryable")

print("test_order_filter_scan OK")
