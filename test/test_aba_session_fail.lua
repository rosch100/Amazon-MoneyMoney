-- ABA session failure must abort Business harvest (no Gap-GET pretending ≤12 months were covered).
-- Run: test/run.sh test/test_aba_session_fail.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1 }

local spaFile = assert(io.open("test/fixtures/ab_your_orders_spa.html", "rb"))
local spaHtml = spaFile:read("*all")
spaFile:close()

env.connectShop = function()
  return mm.HTML(spaHtml)
end
env.connectShopRaw = function()
  return nil, "empty response"
end
env.HTML = mm.HTML
env.isAkamaiInterstitial = function() return false end

local n, err = env.collectBusinessSpaOrders("Example GmbH", "business", 0)
assert(n == nil, "expected nil count on ABA session fail")
assert(type(err) == "string" and err ~= "", "expected error string, got " .. tostring(err))

print("test_aba_session_fail OK")
