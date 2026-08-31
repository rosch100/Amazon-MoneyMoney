-- Erstimport: empty emit on sub:business when cache holds only personal orders.
-- Run: test/run.sh test/test_empty_emit_misaligned.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()
local statusMessages = {}

env.MM.printStatus = function(...)
  local parts = { ... }
  statusMessages[#statusMessages + 1] = table.concat(parts, " ")
end

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.scanAllAmazonSubAccounts = function()
  return 0, nil
end
env.getOrderDetails = function(order)
  if type(order) == 'table' then
    order.detailsDate = now + 86400
    order.detailsParsed = true
    order.orderPositions = order.orderPositions or {
      { purpose = "Item", amount = 1000, qty = 1 },
    }
  end
end

local personalOnlyCache = {
  ["303-personal-1111111-1111111"] = {
    orderCode = "303-personal-1111111-1111111",
    orderPositions = { { purpose = "Private Item", amount = 1999, qty = 1 } },
    orderSum = 1999,
    orderTotal = 1999,
    bookingDate = now,
    detailsDate = now + 86400,
    detailsParsed = true,
    subAccountKind = "personal",
  },
}

local function lastStatus()
  return statusMessages[#statusMessages]
end

local function refreshBusiness(pendingInitialSync)
  statusMessages = {}
  env.LocalStorage = {
    cacheVersion = 22,
    loginCounter = 1,
    lastLoginCounter = 0,
    lastHarvestSince = 0,
    pendingInitialSync = pendingInitialSync,
    OrderCache = personalOnlyCache,
  }
  local result = env.RefreshAccount(
    { accountNumber = "sub:business", owner = "test@example.com" },
    0)
  return result, lastStatus()
end

-- Direct unit: reportEmptyEmitIfMisaligned during Erstimport
env.LocalStorage = {
  cacheVersion = 22,
  pendingInitialSync = true,
  OrderCache = personalOnlyCache,
}
statusMessages = {}
env.reportEmptyEmitIfMisaligned("sub:business", {}, now)
assert(lastStatus():find("Geschäftlich", 1, true),
  "Erstimport must warn when only personal orders in cache")
assert(lastStatus():find("noch nicht abgerufen", 1, true),
  "must mention unharvested sub-account")

env.LocalStorage.pendingInitialSync = false
statusMessages = {}
env.reportEmptyEmitIfMisaligned("sub:business", {}, now)
assert(#statusMessages == 0, "incremental refresh must not warn on empty emit")

local function hasMisalignedWarning()
  for _, msg in ipairs(statusMessages) do
    if type(msg) == "string" and msg:find("noch nicht abgerufen", 1, true) then
      return true
    end
  end
  return false
end

-- Integration: RefreshAccount sub:business during Erstimport
local result, _ = refreshBusiness(true)
local personalOnBusiness = 0
for _, tx in ipairs(result.transactions) do
  if tx.endToEndReference == "303-personal-1111111-1111111" then
    personalOnBusiness = personalOnBusiness + 1
  end
end
assert(personalOnBusiness == 0, "must not emit personal orders on sub:business")
assert(hasMisalignedWarning(),
  "RefreshAccount must surface misaligned emit status during Erstimport")

local result2, _ = refreshBusiness(false)
personalOnBusiness = 0
for _, tx in ipairs(result2.transactions) do
  if tx.endToEndReference == "303-personal-1111111-1111111" then
    personalOnBusiness = personalOnBusiness + 1
  end
end
assert(personalOnBusiness == 0)
assert(not hasMisalignedWarning(),
  "normal refresh must not show Erstimport misaligned warning")

-- Business orders ready: no misaligned warning
statusMessages = {}
env.LocalStorage = {
  cacheVersion = 22,
  pendingInitialSync = true,
  OrderCache = {
    ["303-biz-1111111-1111111"] = {
      orderCode = "303-biz-1111111-1111111",
      orderPositions = { { purpose = "Biz Item", amount = 5000, qty = 1 } },
      orderSum = 5000,
      orderTotal = 5000,
      bookingDate = now,
      detailsDate = now + 86400,
      detailsParsed = true,
      subAccountKind = "business",
    },
  },
}
env.reportEmptyEmitIfMisaligned("sub:business", {}, now)
assert(#statusMessages == 0, "emit-ready business orders must not trigger misaligned warning")

print("test_empty_emit_misaligned OK")
