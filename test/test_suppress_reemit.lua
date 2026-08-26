-- suppressReemitForDetailedOrders: avoid re-import after name/purpose layout change.
-- Run: luajit test/test_suppress_reemit.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

assert(env.suppressReemitForDetailedOrders(nil) == 0)
assert(env.suppressReemitForDetailedOrders({}) == 0)

local cache = {
  ["304-1"] = { since = 1700000000, orderPositions = { { purpose = "A", amount = 1, qty = 1 } } },
  ["304-2"] = { since = 1700000000, orderPositions = {} },
  ["304-3"] = { since = 1700000000 },
}
local n = env.suppressReemitForDetailedOrders(cache)
assert(n == 1, "only orders with positions suppressed, got " .. tostring(n))
assert(cache["304-1"].since == 0)
assert(cache["304-2"].since == 1700000000, "empty positions stay reportable")
assert(cache["304-3"].since == 1700000000, "no positions stay reportable")

print("test_suppress_reemit OK")
