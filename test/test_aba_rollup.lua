-- ABA v2 ajax: rollupTable, scheduler/status polling, HTML order harvest.
-- Run: test/run.sh test/test_aba_rollup.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local rollupFile = assert(io.open("test/fixtures/aba_rollup_table.json", "rb"))
local rollupJson = rollupFile:read("*all")
rollupFile:close()

local schedFile = assert(io.open("test/fixtures/aba_scheduler_response.json", "rb"))
local schedJson = schedFile:read("*all")
schedFile:close()

local htmlFile = assert(io.open("test/fixtures/aba_report_html_orders.html", "rb"))
local htmlOrders = htmlFile:read("*all")
htmlFile:close()

local pendingFile = assert(io.open("test/fixtures/aba_report_pending.html", "rb"))
local pendingHtml = pendingFile:read("*all")
pendingFile:close()

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local abaCsv = [[
Order ID,Title
303-9999999-8888888,Item
]]

local rollupGets = 0
local schedGets = 0

env.connectShopRaw = function(method, urlArg, postContent, contentType, headers)
  if method ~= "GET" or type(urlArg) ~= "string" then
    return ""
  end
  if urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupGets = rollupGets + 1
    assert(headers and headers["anti-csrftoken-a2z"] == "aba-csrf-token-test")
    return rollupJson
  end
  if urlArg:find("/b2b/aba/report/v2/scheduler", 1, true) then
    schedGets = schedGets + 1
    return schedJson
  end
  if urlArg:find("/b2b/aba/report/status/", 1, true) then
    return '{"status":"COMPLETE","downloadUrl":"/b2b/aba/reports/download/generated-items.csv"}'
  end
  if urlArg:find("download/generated-items.csv", 1, true) then
    return abaCsv
  end
  if urlArg:find("/b2b/aba/reports", 1, true) and urlArg:find("items_report_1", 1, true) then
    return pendingHtml
  end
  if urlArg:find("/b2b/aba/", 1, true) then
    return landingHtml
  end
  return ""
end

env.MM.sleep = function() end

local csv = env.harvestAbaReportContent("items_report_1", "PAST_12_MONTHS", landingHtml)
assert(csv ~= nil, "expected rollupTable JSON harvest")
assert(csv:find("303-5555555-6666666", 1, true), csv)
assert(rollupGets >= 1, "expected rollupTable GET")
assert(schedGets == 0, "scheduler should not run when rollupTable succeeds")

local id, ts = env.parseAbaReportStatusIds(schedJson)
assert(id == "675e43a1-9003-4435-bcb6-c5211506491f", id)
assert(ts == "1787721955", ts)

assert(env.isAbaHtmlDocument(htmlOrders))
assert(env.rawTextHasHarvestableOrders(htmlOrders))
assert(env.countPlausibleOrdersInRawText(htmlOrders) >= 2)
assert(htmlOrders:find("303-1111111-2222222", 1, true))
assert(htmlOrders:find("303-3333333-4444444", 1, true))
assert(env.harvestAbaOrdersFromHtml == nil, "HTML order scrape helper removed from harvest path")

rollupGets = 0
schedGets = 0
env.connectShopRaw = function(method, urlArg)
  if method == "GET" and urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
    rollupGets = rollupGets + 1
    return '{"rows":[]}'
  end
  if method == "GET" and urlArg:find("/b2b/aba/report/v2/scheduler", 1, true) then
    schedGets = schedGets + 1
    return schedJson
  end
  if method == "GET" and urlArg:find("/b2b/aba/report/status/", 1, true) then
    return '{"status":"COMPLETE","downloadUrl":"/b2b/aba/reports/download/generated-items.csv"}'
  end
  if method == "GET" and urlArg:find("download/generated-items.csv", 1, true) then
    return abaCsv
  end
  if method == "GET" and urlArg:find("/b2b/aba/reports", 1, true) then
    return pendingHtml
  end
  return landingHtml
end

local csv2 = env.harvestAbaReportContent("items_report_1", "PAST_12_MONTHS", landingHtml)
assert(csv2 ~= nil, "expected scheduler/download fallback")
assert(csv2:find("303-9999999-8888888", 1, true), csv2)
assert(rollupGets >= 1)
assert(schedGets >= 1)

print("test_aba_rollup OK")
