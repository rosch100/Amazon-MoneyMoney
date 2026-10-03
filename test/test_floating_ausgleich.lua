-- Mixed account imports must not create synthetic Amazon Ausgleich bookings.
-- Run: test/run.sh test/test_floating_ausgleich.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"
env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.getOrderDetails = function(order)
  if type(order) == "table" then
    order.detailsDate = os.time() + 86400
    order.detailsParsed = true
  end
end

env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = os.time(),
  OrderCache = {
    ["303-1111111-1111111"] = {
      orderCode = "303-1111111-1111111",
      orderPositions = { { purpose = "Item", amount = 1640, qty = 1 } },
      orderSum = 1640,
      orderTotal = 1640,
      bookingDate = os.time({ year = 2026, month = 8, day = 20 }),
      detailsDate = os.time() + 86400,
      detailsParsed = true,
      subAccountKind = "business",
    },
  },
}

local account = { accountNumber = "test@example.com", owner = "test@example.com" }
local since = os.time() - (7 * 24 * 60 * 60)
local result = env.RefreshAccount(account, since)

assert(result.balance == 0, "combined account balance remains zero")
local itemCount = 0
for _, transaction in ipairs(result.transactions) do
  assert(transaction.endToEndReference ~= "AMAZON-AUSGLEICH",
    "refresh must not emit a synthetic Amazon Ausgleich")
  if transaction.endToEndReference == "303-1111111-1111111" then
    itemCount = itemCount + 1
    assert(transaction.name == "Item")
    assert(math.abs(transaction.amount - (-16.40)) < 0.001)
  end
end
assert(itemCount == 1, "new order purchase line is still emitted")

local repeated = env.RefreshAccount(account, since)
for _, transaction in ipairs(repeated.transactions) do
  assert(transaction.endToEndReference ~= "AMAZON-AUSGLEICH",
    "later refreshes must not emit a synthetic Amazon Ausgleich")
  assert(transaction.endToEndReference ~= "303-1111111-1111111",
    "already emitted purchase must not be imported twice")
end

print("test_floating_ausgleich OK")
