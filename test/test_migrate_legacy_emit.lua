-- migrateLegacyEmitFlags: order.emitted and refund leaf flags → emittedAccounts.
-- Run: test/run.sh test/test_migrate_legacy_emit.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local order = {
  orderCode = "303-legacy-1111111",
  emitted = true,
  refundTransactions = {
    [123] = {
      [500] = { emitted = true, since = 0 },
    },
  },
}
local cache = { [order.orderCode] = order }
local n = env.migrateLegacyEmitFlags(cache)
assert(n == 1)
assert(order.emitted == nil)
assert(order.emittedAccounts.mix == true)
assert(order.refundTransactions[123][500].emitted == nil)
assert(order.refundTransactions[123][500].emittedAccounts.mix == true)

-- Legacy order.emitted must not mark discovered sub:* accounts (subs stay independent).
env.LocalStorage = {
  discoveredSubAccounts = {
    { kind = "business", label = "Example GmbH", accountNumber = "sub:business" },
  },
}
local subOrder = { orderCode = "303-sub", emitted = true }
env.migrateLegacyEmitFlags({ ["303-sub"] = subOrder })
assert(subOrder.emittedAccounts.mix == true)
assert(subOrder.emittedAccounts["sub:business"] == nil)

-- Legacy order.since migrates like order.emitted (legacy account types only).
local sinceOrder = { orderCode = "303-since", since = 1700000000 }
env.migrateLegacyEmitFlags({ ["303-since"] = sinceOrder })
assert(sinceOrder.since == nil)
assert(sinceOrder.emittedAccounts.mix == true)

-- Return leaf legacy markers migrate without order.emitted.
local returnOrder = {
  orderCode = "303-return",
  refundTransactions = {},
  returns = {
    [123] = {
      [500] = {
        ["Item"] = { since = 0 },
      },
    },
  },
}
env.migrateLegacyEmitFlags({ ["303-return"] = returnOrder })
local returnLeaf = returnOrder.returns[123][500]["Item"]
assert(returnLeaf.since == nil)
assert(returnLeaf.emittedAccounts.mix == true)

print("test_migrate_legacy_emit OK")
