-- scanFiltersMonths excludes transactions older than the exact calendar-month window.
-- Run: test/run.sh test/test_scan_filters_months_emit.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

env.secUsername = "test@example.com"
env.applyAccountAttribute("scanFiltersMonths", "6", true)

local now = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
local function makeOrder(day)
  return {
    orderCode = "303-1111111-" .. string.format("%07d", day),
    orderPositions = { { purpose = "Testbestellung", amount = 1000, qty = 1 } },
    orderSum = 1000,
    orderTotal = 1000,
    bookingDate = os.time({ year = 2026, month = 5, day = day }),
    detailsDate = now + 3600,
    detailsParsed = true,
  }
end

local function emit(order)
  local ctx = {
    transactions = {},
    accountNumber = "test@example.com",
    now = now,
    divisor = -100,
  }
  env.appendOrderToRefresh(ctx, order, order.orderCode)
  return ctx.transactions
end

assert(#emit(makeOrder(9)) == 0,
  "an order dated before the six-month cutoff must not be emitted")
assert(#emit(makeOrder(10)) == 1,
  "an order on the six-month cutoff date must be emitted")

local oldOrder = makeOrder(9)
oldOrder.detailsDate = 0
assert(env.orderNeedsDetailsForAccount(oldOrder, now, "test@example.com") == false,
  "an old order with known date must not be queued for another detail fetch")

now = os.time({ year = 2026, month = 11, day = 10, hour = 13 })
local earlyCutoffOrder = makeOrder(10)
earlyCutoffOrder.bookingDate = os.time({
  year = 2026,
  month = 5,
  day = 10,
  hour = 8,
})
assert(#emit(earlyCutoffOrder) == 1,
  "an order earlier on the cutoff date must be emitted when refresh starts after noon")

env.LocalStorage = {
  cacheVersion = 23,
  OrderCache = {
    ["303-old-known-date"] = oldOrder,
  },
}
assert(env.pendingDetailsCountForRefresh("test@example.com", now) == 0,
  "old known-date orders must not consume the detail-fetch limit")
local notice = env.incompleteRefreshNoticePurpose(
  "test@example.com",
  now,
  false,
  { pendingAtStart = 0, counter = 0, failed = 0 })
assert(notice == nil, "excluded old orders must not trigger the open-details notice")

print("test_scan_filters_months_emit OK")
