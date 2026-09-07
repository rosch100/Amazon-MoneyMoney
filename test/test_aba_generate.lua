-- ABA HTML report UI: rollupTable primary path + download link harvest fallback.
-- Run: test/run.sh test/test_aba_generate.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local uiFile = assert(io.open("test/fixtures/aba_report_ui.html", "rb"))
local reportUiHtml = uiFile:read("*all")
uiFile:close()

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()

local abaCsv = [[
Order ID,Title
303-5555555-6666666,Item
]]

env.connectShopRaw = function(method, urlArg, postContent, contentType, headers)
  if method == "POST" and type(urlArg) == "string" then
    if urlArg:find("/b2b/aba/ajax/v2/report/rollupTable", 1, true) then
      return '{"rows":[]}'
    end
  end
  if method == "GET" and type(urlArg) == "string" then
    if urlArg:find("download/generated-items.csv", 1, true) then
      return abaCsv
    end
    if urlArg:find("/b2b/aba/reports", 1, true) and urlArg:find("items_report_1", 1, true) then
      return reportUiHtml
    end
    if urlArg:find("/b2b/aba/", 1, true) then
      return landingHtml
    end
  end
  return ""
end

local csv = env.tryHarvestAbaCsvFromHtmlPage(
  reportUiHtml, "items_report_1", "PAST_12_MONTHS", reportUiHtml, "test")
assert(csv ~= nil, "expected CSV from download link in report HTML")
assert(csv:find("303-5555555-6666666", 1, true), csv)

print("test_aba_generate OK")
