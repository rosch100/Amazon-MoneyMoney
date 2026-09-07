-- Business full harvest: one ABA span, no duplicate report types; GET still runs for older orders.
-- Run: test/run.sh test/test_business_full_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1 }

local spaFile = assert(io.open("test/fixtures/ab_your_orders_spa.html", "rb"))
local spaHtml = spaFile:read("*all")
spaFile:close()

local orderListFile = assert(io.open("test/fixtures/cvf_account_switcher.html", "rb"))
local orderListHtml = orderListFile:read("*all")
orderListFile:close()

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local abaLandingHtml = landingFile:read("*all")
landingFile:close()

local abaCsv = [[
Order ID,Title
303-1111111-2222222,Widget
303-3333333-4444444,Gadget
]]

local rollupCalls = 0
local getOrderListCalls = 0

env.connectShop = function(method, urlArg)
  if method == "GET" and type(urlArg) == "string" and urlArg:find("order-history", 1, true) then
    getOrderListCalls = getOrderListCalls + 1
    return mm.HTML(orderListHtml)
  end
  return mm.HTML(spaHtml)
end

env.connectShopRaw = function(method, urlArg)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupCalls = rollupCalls + 1
    return abaCsv
  end
  if type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    return abaLandingHtml
  end
  return ""
end

env.HTML = mm.HTML
env.isAkamaiInterstitial = function() return false end
env.orderListPageReady = function(htmlNode)
  return htmlNode ~= nil and htmlNode:xpath('//div[contains(@class,"order-card")]'):length() > 0
end

local jobs = env.enumerateAbaReportJobs(0, os.time())
assert(#jobs >= 2, "full harvest must use PAST_12_MONTHS plus gap CUSTOM_RANGE jobs, got " .. tostring(#jobs))
assert(jobs[1].span == "PAST_12_MONTHS")
assert(jobs[2].span == "CUSTOM_RANGE")

local n, err = env.collectBusinessSpaOrders("Example GmbH", "business", 0)
assert(err == nil, tostring(err))
assert(n >= 2, "expected new orders from ABA and/or GET, got " .. tostring(n))
assert(rollupCalls >= 2, "expected multiple rollupTable calls for ABA windows, got " .. tostring(rollupCalls))
assert(getOrderListCalls >= 1, "full harvest must still run GET order-list for gaps, got " .. tostring(getOrderListCalls))

print("test_business_full_harvest OK")
