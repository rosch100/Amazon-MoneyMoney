-- Mid-pagination rollupTable failure must not return partial combined content.
-- Run: test/run.sh test/test_aba_rollup_pagination_incomplete.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

env.LocalStorage = { refreshSince = 0 }

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local page1 = [[
{"rollupTableView":[{"orders":[{"content":{"ordId":{"content":"303-1111111-2222222"}}}]}],
"metadata":{"nextPageMarker":16,"previousPageMarker":0}}
]]

local rollupPosts = 0
env.connectShopRaw = function(method, urlArg)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupPosts = rollupPosts + 1
    if rollupPosts == 1 then
      return page1
    end
    return nil
  end
  return landingHtml
end

local csv = env.fetchAbaRollupTable(
  "items_report_1",
  "PAST_12_MONTHS",
  "csrf-test",
  "https://www.amazon.de/b2b/aba/reports",
  "test pagination incomplete")
assert(csv == nil, "expected nil on mid-pagination failure")
assert(env.isAbaRollupHarvestIncomplete() == true, "incomplete flag expected")

print("test_aba_rollup_pagination_incomplete OK")
