-- Business SPA harvest must use ABA GET only; orderHistory POST aborts MoneyMoney on 403.
-- Run: test/run.sh test/test_business_spa_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1 }

local spaFile = assert(io.open("test/fixtures/ab_your_orders_spa.html", "rb"))
local spaHtml = spaFile:read("*all")
spaFile:close()
env.html = mm.HTML(spaHtml)

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local abaLandingHtml = landingFile:read("*all")
landingFile:close()

local gets = {}
local posts = {}
local abaGets = {}
local abaCsv = [[
Order ID,Title,Amount
303-1111111-2222222,Widget,12.34
303-3333333-4444444,Gadget,9.99
]]

env.connectShop = function(method, urlArg)
  if type(method) == "string" and method == "GET" then
    table.insert(gets, urlArg)
    return env.html
  end
  return env.html
end

env.connectShopRaw = function(method, urlArg, postContent, contentType, headers)
  if method == "POST" then
    if type(urlArg) == "string" and urlArg:find("/ab/your-orders/orderHistory", 1, true) then
      table.insert(posts, { method = method, url = urlArg })
      error("orderHistory POST must not be used for Business SPA harvest")
    end
    if type(urlArg) == "string" and urlArg:find("/b2b/aba/reports", 1, true) then
      table.insert(abaGets, urlArg)
      return abaCsv
    end
  end
  if type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    table.insert(abaGets, urlArg)
    if urlArg:find("items_report", 1, true) then
      return abaCsv
    end
    return abaLandingHtml
  end
  return ""
end

env.HTML = mm.HTML
env.isAkamaiInterstitial = function() return false end

assert(env.isAmazonSignInPageHtml(abaLandingHtml) == false,
  "nav sign-in link must not count as login page")
assert(env.isAbaLandingReady(abaLandingHtml) == true)

local n = env.collectBusinessSpaOrders("Example GmbH", "business")
assert(type(n) == "number", "expected count, got " .. tostring(n))
assert(n == 2, "expected ABA harvest new=2, got " .. tostring(n))
assert(#posts == 0, "must not POST orderHistory, posts=" .. tostring(#posts))
assert(env.LocalStorage.OrderCache["303-1111111-2222222"] ~= nil)

local sawAba = #abaGets >= 1
assert(sawAba, "expected ABA GET requests, got " .. tostring(#abaGets))

print("test_business_spa_harvest OK")
