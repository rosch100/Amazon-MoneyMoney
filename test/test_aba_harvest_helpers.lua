-- ABA URL builders and CSV detection helpers.
-- Run: test/run.sh test/test_aba_harvest_helpers.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local reportsUrl = env.buildAbaReportUrl("items_report_1", "PAST_12_MONTHS", true)
assert(reportsUrl:find("/b2b/aba/reports", 1, true))
assert(reportsUrl:find("reportType=items_report_1", 1, true))
assert(reportsUrl:find("dateSpanSelection=PAST_12_MONTHS", 1, true))
assert(reportsUrl:find("ref=", 1, true) == nil, "reports URL must not include ref")

local landingUrl = env.buildAbaReportUrl("items_report_1", "PAST_12_MONTHS", false)
assert(landingUrl:find("/b2b/aba/", 1, true))
assert(landingUrl:find("items_report_1", 1, true))
assert(landingUrl:find("ref=", 1, true))

assert(env.isAbaCsvOrOrderText("Order ID,Title\n303-1234567-8901234,x,1") == true)
assert(env.isAbaCsvOrOrderText("col1,col2\n303-1234567-8901234,x") == true)
assert(env.isAbaCsvOrOrderText("<html></html>") == false)
assert(env.isAbaCsvOrOrderText("303-1234567-8901234 without header") == false)
assert(env.countPlausibleOrdersInRawText("303-1234567-8901234 and 000-0000000-8675309") == 1)
assert(env.isPlausibleAmazonOrderCode("700-5426221-4134938") == false)

assert(env.abaLanguageTag() == "de-DE")
assert(env.buildAbaAjaxUrl("/b2b/aba/ajax/v2/report/rollupTable", "items_report_1", "PAST_12_MONTHS")
  :find("language=de%-DE", 1, false))

local schedFile = assert(io.open("test/fixtures/aba_scheduler_response.json", "rb"))
local schedJson = schedFile:read("*all")
schedFile:close()
local id, ts = env.parseAbaReportStatusIds(schedJson)
assert(id == "675e43a1-9003-4435-bcb6-c5211506491f")
assert(ts == "1787721955")

local landingFile = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landingHtml = landingFile:read("*all")
landingFile:close()
assert(env.isAmazonSignInPageHtml(landingHtml) == false)
assert(env.isAbaLandingReady(landingHtml) == true)
assert(env.isAmazonSignInPageHtml("<html><body><form name=\"signIn\"><input name=\"password\"/></form></body></html>") == true)

env.LocalStorage = {}
local jobs = env.enumerateAbaReportJobs(nil, os.time())
assert(#jobs >= 1)
assert(jobs[1].reportType == "items_report_1")
assert(jobs[1].span == "PAST_12_MONTHS")
if #jobs > 1 then
  assert(jobs[2].span == "CUSTOM_RANGE")
end
local hasCustomRange = #jobs > 1
for _, job in ipairs(jobs) do
  assert(job.span ~= "LAST_3_MONTHS")
  assert(job.span ~= "PAST_3_MONTHS")
end
assert(hasCustomRange == (#jobs > 1))

local allJobs = env.enumerateAbaFullHarvestJobs(os.time())
assert(#allJobs >= 2)
assert(allJobs[1].span == "PAST_12_MONTHS")
hasCustomRange = false
for i = 2, #allJobs do
  assert(allJobs[i].span == "CUSTOM_RANGE")
  hasCustomRange = true
end
assert(hasCustomRange == true)

local now = os.time()
local since = now - (10 * 24 * 60 * 60)
env.LocalStorage = { OrderCache = { ["303-0000000-0000001"] = {} } }
assert(env.isIncrementalMoneyMoneyRefresh(since, now) == true)
assert(env.isIncrementalMoneyMoneyRefresh(0, now) == false)

local incJobs = env.enumerateAbaReportJobs(since, now)
assert(#incJobs == 1)
assert(incJobs[1].span == "CUSTOM_RANGE")
assert(incJobs[1].reportType == "items_report_1")
assert(incJobs[1].fromDate ~= nil)
assert(incJobs[1].toDate ~= nil)

local body = env.buildAbaRollupTablePostBody("items_report_1", "CUSTOM_RANGE", incJobs[1].fromDate, incJobs[1].toDate)
assert(body:find("CUSTOM_RANGE", 1, true))
assert(body:find('"ordId"', 1, true))
local fullBody = env.buildAbaRollupTablePostBody("items_report_1", "PAST_12_MONTHS")
assert(fullBody:find("PAST_12_MONTHS", 1, true))
assert(fullBody:find("CUSTOM_RANGE", 1, true) == nil)

local scanMonths = env.effectiveScanFiltersMonths(since, now)
assert(scanMonths ~= nil and scanMonths >= 1 and scanMonths <= 2)

local urls = env.extractAbaDownloadUrls(
  '<a href="/b2b/aba/reports/download/abc.csv">dl</a>')
assert(#urls == 1)
assert(urls[1]:find("download/abc.csv", 1, true))

print("test_aba_harvest_helpers OK")
