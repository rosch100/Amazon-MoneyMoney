-- Incremental harvest cutoff C + selective 90d refund watch.
-- Run: test/run.sh test/test_incremental_harvest_cutoff.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua", {
  OrderCache = {},
})
env.secUsername = "test@example.com"

local day = 24 * 60 * 60
local now = 1700000000

env.LocalStorage.OrderCache = {
  a = { orderCode = "303-1", bookingDate = now - 10 * day },
  b = { orderCode = "303-2", bookingDate = now - 2 * day },
  c = { orderCode = "303-3", bookingDate = env.invalidDate },
}
assert(env.newestOrderBookingDate() == now - 2 * day)

-- Cutoff C: max(since, newest) - 14d
local since = now - 5 * day
local cutoff = env.incrementalHarvestCutoff(since, now)
assert(cutoff == (now - 2 * day) - 14 * day,
  "cutoff must use newer cache booking minus 14d")

local olderSince = now - 1 * day
cutoff = env.incrementalHarvestCutoff(olderSince, now)
assert(cutoff == olderSince - 14 * day,
  "cutoff must use MoneyMoney since when newer than cache")

-- Settled refund candidate exclusion
local settled = {
  orderCode = "303-settled",
  bookingDate = now - 20 * day,
  returnActivity = true,
  returnedPositions = { { name = "x", amount = 1000, qty = 1 } },
  refundTransactions = { [now - 15 * day] = { [1000] = {} } },
}
assert(env.orderRefundFullySettled(settled) == true)
assert(env.orderMayNeedIncrementalRefundWatch(settled, now) ~= true)

local openReturn = {
  orderCode = "303-open",
  bookingDate = now - 20 * day,
  returnActivity = true,
  returnedPositions = { { name = "x", amount = 1000, qty = 1 } },
}
assert(env.orderMayNeedIncrementalRefundWatch(openReturn, now) == true)

local unbilled = {
  orderCode = "303-cancel",
  bookingDate = now - 5 * day,
  unbilledCancel = true,
}
assert(env.orderMayNeedIncrementalRefundWatch(unbilled, now) ~= true)

local tooOld = {
  orderCode = "303-old",
  bookingDate = now - 100 * day,
}
assert(env.orderMayNeedIncrementalRefundWatch(tooOld, now) ~= true)

local fresh = {
  orderCode = "303-fresh",
  bookingDate = now - 3 * day,
}
assert(env.orderMayNeedIncrementalRefundWatch(fresh, now) == true)

-- scheduleIncrementalRefundWatch: selective queue
env.LocalStorage.refreshSince = now - 3 * day
env.LocalStorage.OrderCache = {
  watch = {
    orderCode = "303-watch",
    bookingDate = now - 10 * day,
    detailsDate = now - 1, -- due
    emittedAccounts = { ["test@example.com"] = true },
  },
  settledWatch = {
    orderCode = "303-settled-w",
    bookingDate = now - 10 * day,
    detailsDate = now - 1,
    emittedAccounts = { ["test@example.com"] = true },
    returnActivity = true,
    returnedPositions = { { name = "x", amount = 500, qty = 1 } },
    refundTransactions = { [now - 8 * day] = { [500] = {} } },
  },
  future = {
    orderCode = "303-future",
    bookingDate = now - 10 * day,
    detailsDate = now + 7 * day, -- not due
    emittedAccounts = { ["test@example.com"] = true },
  },
}
local n = env.scheduleIncrementalRefundWatch("test@example.com", now - 3 * day, now)
assert(n == 1, "only due unsettled candidate must be queued, got " .. tostring(n))
assert(env.LocalStorage.OrderCache.watch.detailsDate == 1)
assert(env.LocalStorage.OrderCache.settledWatch.detailsDate == now - 1)
assert(env.LocalStorage.OrderCache.future.detailsDate == now + 7 * day)

-- effectiveScanFiltersMonths uses cutoff (newer booking shrinks months vs raw since alone)
env.LocalStorage.OrderCache = {
  recent = { orderCode = "303-r", bookingDate = now - day },
}
-- config.scanFiltersMonths defaults to 0 → return computed months from cutoff
local months = env.effectiveScanFiltersMonths(now - 200 * day, now)
assert(months == 1, "incremental months must follow cutoff, got " .. tostring(months))

print("test_incremental_harvest_cutoff OK")
