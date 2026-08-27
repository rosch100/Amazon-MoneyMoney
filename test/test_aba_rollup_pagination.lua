-- ABA rollupTable must paginate via nextPageMarker (Amazon pageSize=16).
-- Run: test/run.sh test/test_aba_rollup_pagination.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local page1 = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-1111111-2222222"}}}]}],
"metadata":{"nextPageMarker":16,"previousPageMarker":0}}
]]
local page2 = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-3333333-4444444"}}}]}],
"metadata":{"nextPageMarker":0,"previousPageMarker":16}}
]]

local rollupPosts = 0
env.connectShopRaw = function(method, urlArg, postContent)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupPosts = rollupPosts + 1
    assert(type(postContent) == "string")
    local marker = postContent:match('"pageMarker":(%d+)')
    if marker == "0" then
      return page1
    end
    if marker == "16" then
      return page2
    end
    error("unexpected pageMarker " .. tostring(marker))
  end
  return landingHtml
end

local csv = env.fetchAbaRollupTable(
  "items_report_1",
  "PAST_12_MONTHS",
  "csrf-test",
  "https://www.amazon.de/b2b/aba/reports",
  "test pagination")
assert(csv ~= nil, "expected paginated rollup content")
assert(csv:find("303-1111111-2222222", 1, true), csv)
assert(csv:find("303-3333333-4444444", 1, true), csv)
assert(rollupPosts == 2, "expected two rollupTable POSTs, got " .. rollupPosts)

assert(env.parseAbaRollupTableNextPageMarker(page1) == 16)
assert(env.parseAbaRollupTableNextPageMarker(page2) == 0)

local body0 = env.buildAbaRollupTablePostBody("items_report_1", "PAST_12_MONTHS", nil, nil, 0)
local body16 = env.buildAbaRollupTablePostBody("items_report_1", "PAST_12_MONTHS", nil, nil, 16)
assert(body0:find('"pageMarker":0', 1, true))
assert(body16:find('"pageMarker":16', 1, true))

print("test_aba_rollup_pagination OK")
