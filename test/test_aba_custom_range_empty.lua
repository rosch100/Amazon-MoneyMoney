-- CUSTOM_RANGE: empty rollupTable JSON must not call scheduler (HTTP 400 aborts MM).
-- Run: test/run.sh test/test_aba_custom_range_empty.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local rollupPosts = 0
local schedGets = 0
env.connectShopRaw = function(method, urlArg, postContent)
  if method == "POST"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupPosts = rollupPosts + 1
    assert(urlArg:find("dateSpanSelection=PAST_12_MONTHS", 1, true))
    assert(urlArg:find("dateSpanSelection=CUSTOM_RANGE", 1, true) == nil)
    assert(type(postContent) == "string" and postContent:find("CUSTOM_RANGE", 1, true))
    return '{"rollupTableView":[],"rows":[]}'
  end
  if method == "GET"
      and type(urlArg) == "string"
      and urlArg:find("/b2b/aba/report/v2/scheduler", 1, true) then
    schedGets = schedGets + 1
    error("scheduler GET must not run for CUSTOM_RANGE")
  end
  if method == "GET" and type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    return landingHtml
  end
  return ""
end

local now = os.time()
local since = now - (400 * 24 * 60 * 60)
local fromParts = env.unixToAbaDateParts(since)
local toParts = env.unixToAbaDateParts(now)
assert(fromParts ~= nil and toParts ~= nil)

local content = env.tryHarvestAbaCsvFromHtmlPage(
  landingHtml, "items_report_1", "CUSTOM_RANGE", landingHtml, "test", fromParts, toParts)
assert(content ~= nil, "empty rollup JSON is a valid harvest result")
assert(content:find("rollupTableView", 1, true), content)
assert(env.isAbaRollupTableJson('{"rows":[]}') == false, "generic rows JSON must not count as rollup")
assert(env.isAbaRollupTableJson('{"rollupTableView":[]}') == true)
assert(rollupPosts == 1)
assert(schedGets == 0, "scheduler must not run for CUSTOM_RANGE")

print("test_aba_custom_range_empty OK")
