-- Full harvest must restart ABA batch at PAST_12_MONTHS when batch index is stale and cache is empty.
-- Run: test/run.sh test/test_aba_batch_reset_empty_cache.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
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

-- Changing the configured scan window restarts any partially consumed batch.
env.LocalStorage.abaFullHarvestJobIndex = 2
env.LocalStorage.abaFullHarvestHasMore = true
env.LocalStorage.abaFullHarvestScanMonths = 0
env.applyAccountAttribute("scanFiltersMonths", "6", true)
env.ensureAbaFullHarvestBatch(0, now)
assert(env.LocalStorage.abaFullHarvestJobIndex == 1,
  "changed scan window must restart the ABA batch")
assert(env.LocalStorage.abaFullHarvestScanMonths == 6)
assert(#env.LocalStorage.abaFullHarvestJobs == 1)
assert(env.LocalStorage.abaFullHarvestJobs[1].span == "CUSTOM_RANGE")

-- Business orders in cache (even without emit-ready details) must not trigger restart.
env.LocalStorage.OrderCache = {
  ["303-business-1"] = {
    orderCode = "303-business-1",
    subAccountKind = "business",
    detailsDate = 0,
  },
}
env.LocalStorage.abaFullHarvestJobIndex = 5
env.LocalStorage.abaFullHarvestJobs = {
  { reportType = "items_report_1", span = "PAST_12_MONTHS" },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 1, toUnix = 2 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 3, toUnix = 4 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 5, toUnix = 6 },
  { reportType = "items_report_1", span = "CUSTOM_RANGE", fromUnix = 7, toUnix = 8 },
}
assert(env.countBusinessOrdersInCache() == 1)
assert(env.shouldRestartAbaFullHarvestBatch(0, now) == false)

-- Emit-ready business orders also allow batch progress.
env.LocalStorage.OrderCache = {
  ["303-business-1"] = {
    orderCode = "303-business-1",
    subAccountKind = "business",
    detailsDate = now + 3600,
    bookingDate = now,
    detailsParsed = true,
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

-- A completed batch belongs to its scan window; changing the window must start a new batch.
env.applyAccountAttribute("scanFiltersMonths", "6", true)
env.LocalStorage = {
  refreshSince = 0,
  abaRollupPaginationVersion = 3,
  abaRollupHarvestIncomplete = nil,
  OrderCache = {
    ["303-business-1"] = {
      orderCode = "303-business-1",
      subAccountKind = "business",
      detailsDate = 0,
    },
  },
}
env.beginAbaFullHarvestBatch(0, now)
env.LocalStorage.abaFullHarvestJobs = nil
env.LocalStorage.abaFullHarvestJobIndex = nil
env.LocalStorage.abaFullHarvestHasMore = false
env.markAbaFullHarvestCompleteForRefresh(0)
assert(env.isAbaFullHarvestCompleteForRefresh(0) == true)
env.applyAccountAttribute("scanFiltersMonths", "24", true)
env.ensureAbaFullHarvestBatch(0, now)
assert(env.isAbaFullHarvestCompleteForRefresh(0) == false,
  "a completed batch for a different scan window must be stale")
assert(env.LocalStorage.abaFullHarvestScanMonths == 24)
assert(type(env.LocalStorage.abaFullHarvestJobs) == "table",
  "changing a completed scan window must start a new batch")

-- Incremental refreshes must also restart a completed batch when its scan window changes.
local incrementalSince=now-7*86400
env.applyAccountAttribute("scanFiltersMonths", "6", true)
env.LocalStorage = {
  refreshSince = incrementalSince,
  abaRollupPaginationVersion = 3,
  OrderCache = {
    ["303-business-2"] = {
      orderCode = "303-business-2",
      subAccountKind = "business",
      detailsDate = 0,
    },
  },
}
env.beginAbaFullHarvestBatch(incrementalSince, now)
env.LocalStorage.abaFullHarvestJobs = nil
env.LocalStorage.abaFullHarvestJobIndex = nil
env.LocalStorage.abaFullHarvestHasMore = false
env.markAbaFullHarvestCompleteForRefresh(incrementalSince)
env.applyAccountAttribute("scanFiltersMonths", "24", true)
env.ensureAbaFullHarvestBatch(incrementalSince, now)
assert(env.LocalStorage.abaFullHarvestScanMonths == 24,
  "incremental refresh must update the stored scan window")
assert(type(env.LocalStorage.abaFullHarvestJobs) == "table",
  "incremental refresh must restart a completed batch for a changed window")

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
