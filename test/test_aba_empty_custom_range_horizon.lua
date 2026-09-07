-- Consecutive empty CUSTOM_RANGE windows mean Amazon ABA has no older data.
-- Remaining jobs back to 2000 must not keep the harvest paused.
-- Run: test/run.sh test/test_aba_empty_custom_range_horizon.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local past12 = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-1111111-2222222"}}}]}],
"metadata":{"nextPageMarker":0}}
]]
local customWithOrders = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-3333333-4444444"}}}]}],
"metadata":{"nextPageMarker":0}}
]]
local customEmpty = [[{"rollupTableView":[],"metadata":{"nextPageMarker":0}}]]

env.LocalStorage = {
  OrderCache = {},
  refreshSince = 0,
}

local posts = {}
env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.connectShopRaw = function(method, urlArg, postContent)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    posts[#posts + 1] = postContent or ""
    local body = postContent or ""
    if body:find("PAST_12_MONTHS", 1, true) then
      return past12
    end
    if body:find('"fromDate":{"year":2024', 1, true) then
      return customWithOrders
    end
    return customEmpty
  end
  if type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    return landingHtml
  end
  return ""
end

local n, err = env.collectOrdersFromAbaReports("Altanis GmbH", "business", 0)
assert(err == nil, tostring(err))
assert(n >= 2, "expected orders from PAST_12_MONTHS and first CUSTOM_RANGE, got " .. tostring(n))
assert(env.LocalStorage.OrderCache["303-1111111-2222222"] ~= nil)
assert(env.LocalStorage.OrderCache["303-3333333-4444444"] ~= nil)

assert(env.abaFullHarvestBatchHasMore() == false,
  "empty CUSTOM_RANGE streak must finish the ABA batch instead of pausing for years back to 2000")

local emptyPosts = 0
for _, body in ipairs(posts) do
  if body:find("CUSTOM_RANGE", 1, true) and not body:find('"fromDate":{"year":2024', 1, true) then
    emptyPosts = emptyPosts + 1
  end
end
assert(emptyPosts <= 2,
  "must stop after consecutive empty CUSTOM_RANGE windows, extra empty posts=" .. tostring(emptyPosts))

local postsAfterHorizon = #posts
local n2, err2 = env.collectOrdersFromAbaReports("Altanis GmbH", "business", 0)
assert(err2 == nil, tostring(err2))
assert(n2 == 0, "completed ABA horizon must not restart PAST_12_MONTHS, got new=" .. tostring(n2))
assert(#posts == postsAfterHorizon,
  "completed ABA horizon must not POST more rollupTable jobs")

print("test_aba_empty_custom_range_horizon OK")
