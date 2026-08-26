-- ABA CUSTOM_RANGE: rollupTable POST with fromDate/toDate (MoneyMoney incremental refresh).
-- Run: test/run.sh test/test_aba_custom_range.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local rollupResponse = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-8888888-7777777"}}}]}]}
]]

local rollupPosts = 0
env.connectShopRaw = function(method, urlArg, postContent, contentType, headers)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupPosts = rollupPosts + 1
    assert(type(postContent) == "string")
    assert(postContent:find("CUSTOM_RANGE", 1, true))
    assert(postContent:find('"ordId"', 1, true))
    assert(headers and headers["anti-csrftoken-a2z"] == "aba-csrf-token-test")
    return rollupResponse
  end
  if method == "GET" and type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    return landingHtml
  end
  return ""
end

local now = os.time()
local since = now - (5 * 24 * 60 * 60)
local fromParts = env.unixToAbaDateParts(since)
local toParts = env.unixToAbaDateParts(now)
assert(fromParts ~= nil and toParts ~= nil)

local csv = env.tryHarvestAbaCsvFromHtmlPage(
  landingHtml, "items_report_1", "CUSTOM_RANGE", landingHtml, "test", fromParts, toParts)
assert(csv ~= nil, "expected CUSTOM_RANGE rollup harvest")
assert(csv:find("303-8888888-7777777", 1, true), csv)
assert(rollupPosts == 1, "expected one rollupTable POST, got " .. tostring(rollupPosts))

print("test_aba_custom_range OK")
