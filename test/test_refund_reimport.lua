-- Full-refund reimport must not duplicate already booked purchase+contra.
-- Run: test/run.sh test/test_refund_reimport.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local orderCode = "305-0111814-9565146"
local bookingDate = os.time({ year = 2025, month = 5, day = 15 })
local amount = 679 -- 6,79 EUR in cents

-- Already reported in a prior sync (mixed: purchase + Amazon contra).
local order = {
  orderCode = orderCode,
  orderTotal = amount,
  bookingDate = bookingDate,
  since = 1000,
  orderPositions = { { purpose = "OcioDual Edge", amount = amount, qty = 1 } },
}

-- New full Erstattung leaf from a later details parse.
env.registerRefundTransaction(order, bookingDate, amount)
assert(order.refundTransactions[bookingDate][amount].since == 0,
  "full refund on already-reported order must stamp since=0")

assert(env.shouldSuppressFullRefundReimport(order, amount, 2000, true) == true)
assert(env.shouldSuppressFullRefundReimport(order, amount, 2000, false) == false,
  "non-mixed still needs refund for balance")
assert(env.shouldSuppressFullRefundReimport(order, amount / 2, 2000, true) == false,
  "partial refund must still import")

-- First-time order (not yet reported): refund must remain emit-able.
local fresh = {
  orderCode = orderCode,
  orderTotal = amount,
  bookingDate = bookingDate,
}
env.registerRefundTransaction(fresh, bookingDate, amount)
assert(fresh.refundTransactions[bookingDate][amount].since == nil,
  "new order refund must not be suppressed before first report")
assert(env.shouldSuppressFullRefundReimport(fresh, amount, 2000, true) == false)

-- suppressReemit also clears refund since
local cache = {
  [orderCode] = {
    since = 1700000000,
    orderTotal = amount,
    orderPositions = { { purpose = "A", amount = amount, qty = 1 } },
    refundTransactions = {
      [bookingDate] = { [amount] = { since = 1700000001 } },
    },
  },
}
assert(env.suppressReemitForDetailedOrders(cache) == 1)
assert(cache[orderCode].since == 0)
assert(cache[orderCode].refundTransactions[bookingDate][amount].since == 0)

print("test_refund_reemit OK")
