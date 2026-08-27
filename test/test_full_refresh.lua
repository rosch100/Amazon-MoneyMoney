-- First fetch / full MoneyMoney refresh must not use incremental CUSTOM_RANGE.
-- Run: test/run.sh test/test_full_refresh.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = { OrderCache = {}, loginCounter = 1, lastLoginCounter = 1 }

local now = os.time()
local recentSince = now - (3 * 24 * 60 * 60)

-- Empty cache: even a recent since must trigger full harvest mode.
assert(env.orderCacheHasOrders() == false)
assert(env.isIncrementalMoneyMoneyRefresh(recentSince, now) == false)
assert(env.shouldRunAccountHarvest(recentSince, now) == true)
assert(env.validMoneyMoneyRefreshAge(recentSince, now) ~= nil)
assert(env.requiresFullMoneyMoneyHarvest(recentSince, now) == true)

local fullJobs = env.enumerateAbaReportJobs(recentSince, now)
assert(#fullJobs >= 1)
assert(fullJobs[1].span == "PAST_12_MONTHS")
assert(fullJobs[1].reportType == "items_report_1")
assert(fullJobs[1].span ~= "CUSTOM_RANGE")

-- scanFiltersMonths: full refresh keeps configured limit (0 = no limit).
assert(env.effectiveScanFiltersMonths(recentSince, now) == 0)

-- Populated cache + recent since => incremental.
env.LocalStorage.OrderCache = { ["303-1111111-2222222"] = { orderTotal = 1 } }
assert(env.orderCacheHasOrders() == true)
assert(env.isIncrementalMoneyMoneyRefresh(recentSince, now) == true)

local incJobs = env.enumerateAbaReportJobs(recentSince, now)
assert(#incJobs == 1)
assert(incJobs[1].span == "CUSTOM_RANGE")

-- Full MoneyMoney option since=0: always harvest, never incremental.
assert(env.isIncrementalMoneyMoneyRefresh(0, now) == false)
assert(env.shouldRunAccountHarvest(0, now) == true)

print("test_full_refresh OK")
