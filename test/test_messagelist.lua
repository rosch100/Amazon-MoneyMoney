-- Incremental harvest re-queues details for known orders (message-center replacement).
-- Run: test/run.sh test/test_messagelist.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

assert(env.getMessageList == nil, "dead message-center API must be removed")
assert(env.connectShopJson == nil, "connectShopJson was only used by message center")

local now = os.time()
local recentSince = now - (3 * 24 * 60 * 60)

-- Incremental: known order in harvest text re-queues details for refund/change pickup.
env.LocalStorage = {
  OrderCache = {
    ["303-1111111-1111111"] = {
      orderCode = "303-1111111-1111111",
      detailsDate = now + 86400,
      orderPositions = { { purpose = "A", amount = 1, qty = 1 } },
      orderTotal = 1,
    },
  },
  refreshSince = recentSince,
}

local cache = env.LocalStorage.OrderCache
local raw = "Bestellnummer\n303-1111111-1111111\n303-1111111-2222222\n"
local found, foundNew, n = env.mergeOrdersFromRawText(raw, cache, "Example GmbH", "business")
assert(found == true)
assert(foundNew == true)
assert(n == 1, "one new order expected")
assert(cache["303-1111111-1111111"].detailsDate == 1,
  "known order must re-queue details on incremental reappear")
assert(cache["303-1111111-2222222"] ~= nil)
assert(cache["303-1111111-2222222"].detailsDate == 0, "new order still queues details")

-- Full harvest must not blanket re-queue known orders.
env.LocalStorage.refreshSince = 0
cache["303-1111111-1111111"].detailsDate = now + 86400
env.mergeOrdersFromRawText(raw, cache, "Example GmbH", "business")
assert(cache["303-1111111-1111111"].detailsDate == now + 86400,
  "full harvest must not force details refresh on reappear")

-- harvestAbaReportJob: found but not new → foundOrders true, newCount 0
env.LocalStorage = {
  OrderCache = {
    ["303-5555555-6666666"] = {
      orderCode = "303-5555555-6666666",
      detailsDate = now + 86400,
      orderTotal = 1,
      orderPositions = { { purpose = "W", amount = 1, qty = 1 } },
    },
  },
  refreshSince = recentSince,
}

local lf = assert(io.open("test/fixtures/aba_landing_nav.html", "rb"))
local landing = lf:read("*all")
lf:close()
local rollup = '{"rows":[{"orderId":"303-5555555-6666666","title":"Widget"}],"status":"SUCCESS"}'

env.connectShopRaw = function(method, urlArg)
  if type(urlArg) == "string" and urlArg:find("rollupTable", 1, true) then
    return rollup
  end
  if type(urlArg) == "string" and urlArg:find("/b2b/aba/", 1, true) then
    return landing
  end
  return ""
end

local job = {
  reportType = "items_report_1",
  span = "CUSTOM_RANGE",
  fromDate = { year = 2026, month = 6, day = 26 },
  toDate = { year = 2026, month = 7, day = 26 },
  fromUnix = recentSince,
  toUnix = now,
}
local newCount, foundOrders = env.harvestAbaReportJob(
  job, landing, env.LocalStorage.OrderCache, "Example GmbH", "business")
assert(newCount == 0, "expected 0 new, got " .. tostring(newCount))
assert(foundOrders == true, "rollup orders must count as found")
assert(env.LocalStorage.OrderCache["303-5555555-6666666"].detailsDate == 1,
  "ABA incremental reappear must re-queue details")

-- Incremental refund watch: re-queue only when details rescan is due (detailsDate < now).
env.LocalStorage = {
  OrderCache = {
    ["303-due-1111111"] = {
      orderCode = "303-due-1111111",
      bookingDate = recentSince + 3600,
      detailsDate = now - 3600,
      emittedAccounts = { mix = true },
      orderPositions = { { purpose = "W", amount = 1, qty = 1 } },
      orderTotal = 1,
    },
    ["303-future-2222222"] = {
      orderCode = "303-future-2222222",
      bookingDate = recentSince - (30 * 24 * 60 * 60),
      detailsDate = now + 86400,
      emittedAccounts = { mix = true },
      orderTotal = 1,
    },
    ["303-old-3333333"] = {
      orderCode = "303-old-3333333",
      bookingDate = now - (400 * 24 * 60 * 60),
      detailsDate = now - 3600,
      emittedAccounts = { mix = true },
      orderTotal = 1,
    },
  },
  refreshSince = recentSince,
}
local watched = env.scheduleIncrementalRefundWatch("mix", recentSince, now)
assert(watched == 1, "expected 1 re-queued (due only), got " .. tostring(watched))
assert(env.LocalStorage.OrderCache["303-due-1111111"].detailsDate == 1)
assert(env.LocalStorage.OrderCache["303-future-2222222"].detailsDate == now + 86400,
  "future detailsDate must not be disturbed")
assert(env.LocalStorage.OrderCache["303-old-3333333"].detailsDate == now - 3600,
  "orders outside 366d max-age must not be re-queued")

print("TEST_MESSAGELIST OK")
