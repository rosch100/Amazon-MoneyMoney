-- New refund leaves stay emit-able until marked via emittedAccounts.
-- Run: test/run.sh test/test_refund_reimport.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local orderCode = "305-1111111-1111111"
local bookingDate = os.time({ year = 2025, month = 5, day = 15 })
local amount = 679 -- 6,79 EUR in cents

local order = {
  orderCode = orderCode,
  orderTotal = amount,
  bookingDate = bookingDate,
  emittedAccounts = { ["test@example.com"] = true },
  orderPositions = { { purpose = "Item C", amount = amount, qty = 1 } },
}

env.registerRefundTransaction(order, bookingDate, amount)
assert(order.refundTransactions[bookingDate][amount] ~= nil)
assert(order.refundTransactions[bookingDate][amount].emittedAccounts == nil)
assert(env.isOrderEmittedForAccount(order.refundTransactions[bookingDate][amount], "test@example.com") == false)

env.markOrderEmittedForAccount(order.refundTransactions[bookingDate][amount], "test@example.com")
assert(env.isOrderEmittedForAccount(order.refundTransactions[bookingDate][amount], "test@example.com") == true)
assert(env.isOrderEmittedForAccount(order.refundTransactions[bookingDate][amount], "A3BUSINESSID02") == false)

print("test_refund_reimport OK")
