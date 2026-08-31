-- Erstimport sub:business: nur Business-Bestelldetails im Business-Kontext laden.
-- Run: test/run.sh test/test_initial_sync_cross_account_details.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end

env.ensureAmazonSubAccountSession = function(kind)
  env.lastDetailsSessionKind = kind
end

local detailsFetched = {}
env.getOrderDetails = function(order)
  detailsFetched[#detailsFetched + 1] = order.orderCode
  order.detailsDate = now + 86400
  order.detailsParsed = true
  order.orderPositions = { { purpose = "Item", amount = 1000, qty = 1 } }
  order.orderSum = 1000
  order.orderTotal = 1000
end

env.LocalStorage = {

  cacheVersion = 22,
  loginCounter = 2,
  pendingInitialSync = true,
  initialSyncHarvestDone = true,
  subAccountScan = { phase = "done", incomplete = false, totalNew = 0 },
  OrderCache = {
    ["303-personal-1"] = {
      orderCode = "303-personal-1",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now,
      detailsDate = 0,
      subAccountKind = "personal",
    },
    ["303-business-1"] = {
      orderCode = "303-business-1",
      orderPositions = {},
      orderSum = 0,
      orderTotal = 0,
      bookingDate = now,
      detailsDate = 0,
      subAccountKind = "business",
    },
  },
}

env.scanAllAmazonSubAccounts = function()
  env.LocalStorage.subAccountScan = { phase = "done", incomplete = false, totalNew = 0 }
  return 0, nil
end

local businessAccount = { accountNumber = "sub:business", owner = "test@example.com" }
local result = env.RefreshAccount(businessAccount, now - (30 * 24 * 60 * 60))
assert(type(result) == "table")
assert(env.lastDetailsSessionKind == "business", "details fetch must switch to business session")
assert(#detailsFetched == 1, "sub:business refresh must fetch only business order details, got " .. #detailsFetched)
assert(detailsFetched[1] == "303-business-1", "expected business order, got " .. tostring(detailsFetched[1]))
assert(#result.transactions == 2, "business mixed account emits purchase + Ausgleich, got " .. #result.transactions)

detailsFetched = {}
env.lastDetailsSessionKind = nil
local personalAccount = { accountNumber = "sub:personal", owner = "test@example.com" }
local personalResult = env.RefreshAccount(personalAccount, now - (30 * 24 * 60 * 60))
assert(env.lastDetailsSessionKind == "personal", "details fetch must switch to personal session")
assert(#detailsFetched == 1, "sub:personal refresh must fetch only personal order details, got " .. #detailsFetched)
assert(detailsFetched[1] == "303-personal-1", "expected personal order, got " .. tostring(detailsFetched[1]))
assert(#personalResult.transactions == 2, "personal mixed account emits purchase + Ausgleich")

print("test_initial_sync_cross_account_details OK")
