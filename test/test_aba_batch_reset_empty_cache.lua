-- Full harvest must restart ABA batch at PAST_12_MONTHS when batch index is stale and cache is empty.
-- Run: test/run.sh test/test_aba_batch_reset_empty_cache.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.LocalStorage = {
  refreshSince = 0,
  OrderCache = {},
  abaFullHarvestHarvestSince = 0,
  abaFullHarvestJobIndex = 5,
  abaFullHarvestHasMore = true,
  abaFullHarvestJobs = {
    { reportType = "items_report_1", span = "PAST_12_MONTHS" },
    { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 1, toUnix = 2 },
  },
}

assert(env.shouldRestartAbaFullHarvestBatch(0, now) == true)
env.ensureAbaFullHarvestBatch(0, now)
assert(env.LocalStorage.abaFullHarvestJobIndex == 1, "batch must restart at PAST_12_MONTHS")
assert(type(env.LocalStorage.abaFullHarvestJobs) == "table")
assert(env.LocalStorage.abaFullHarvestJobs[1].span == "PAST_12_MONTHS")

-- Business orders in cache (even without emit-ready details) must not trigger restart.
env.LocalStorage.OrderCache = {
  ["303-business-1"] = {
    orderCode = "303-business-1",
    subAccountKind = "business",
    detailsDate = 0,
  },
}
env.LocalStorage.abaFullHarvestJobIndex = 5
assert(env.countBusinessOrdersInCache() == 1)
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == false)

-- Emit-ready business orders also allow batch progress.
env.LocalStorage.OrderCache = {
  ["303-business-1"] = {
    orderCode = "303-business-1",
    subAccountKind = "business",
    detailsDate = now + 3600,
    orderPositions = { { amount = 100 } },
  },
}
assert(env.countEmitReadyBusinessOrdersInCache(now) == 1)
env.LocalStorage.abaFullHarvestJobIndex = 5
env.LocalStorage.abaFullHarvestJobs = {
  { reportType = "items_report_1", span = "PAST_12_MONTHS" },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 1, toUnix = 2 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 3, toUnix = 4 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 5, toUnix = 6 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 7, toUnix = 8 },
}
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == false)

-- Normal progression at CUSTOM_RANGE job 2 must not look corrupt.
env.LocalStorage.abaFullHarvestJobIndex = 2
env.LocalStorage.abaFullHarvestJobs = {
  { reportType = "items_report_1", span = "PAST_12_MONTHS" },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 1, toUnix = 2 },
}
assert(env.abaFullHarvestBatchCorrupt() == false)
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == false)

-- Corrupt job list without PAST_12_MONTHS must restart.
env.LocalStorage.OrderCache = {}
env.LocalStorage.abaFullHarvestJobIndex = 1
env.LocalStorage.abaFullHarvestJobs = {
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 1, toUnix = 2 },
}
assert(env.abaFullHarvestBatchCorrupt() == true)
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == true)

-- Completed harvest for this refreshSince must not restart.
env.LocalStorage.abaFullHarvestJobs = {
  { reportType = "items_report_1", span = "PAST_12_MONTHS" },
}
env.LocalStorage.abaFullHarvestJobIndex = 2
env.markAbaFullHarvestCompleteForRefresh(0)
assert(env.isAbaFullHarvestCompleteForRefresh(0) == true)
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == false)

-- Pagination upgrade forces a full replay marker.
env.LocalStorage = {
  refreshSince = 0,
  OrderCache = {},
  abaRollupPaginationVersion = 2,
}
env.ensureAbaFullHarvestBatch(0, now)
assert(env.LocalStorage.abaRollupPaginationVersion == 3)
assert(env.LocalStorage.abaFullHarvestReplayRequired == true)

print("test_aba_batch_reset_empty_cache OK")
