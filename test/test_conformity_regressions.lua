package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

env.LocalStorage = {
  cacheVersion = 21,
  OrderCache = {
    ["304-legacy-cache"] = {
      detailsDate = os.time() + 3600,
      orderPositions = {{amount = 100}},
    },
  },
}
assert(env.applyImportSchemaUpgrade() == true,
  "cache version 21 must be migrated for the detailsParsed contract")
assert(env.LocalStorage.cacheVersion == 22, "cache migration must persist schema version 22")
assert(next(env.LocalStorage.OrderCache) == nil,
  "cache migration must remove entries without a trustworthy detailsParsed marker")

env.LocalStorage = {
  OrderCache = {
    ["304-unversioned-cache"] = {
      detailsDate = os.time() + 3600,
      orderPositions = {{amount = 100}},
    },
  },
}
assert(env.applyImportSchemaUpgrade() == true,
  "unversioned non-empty caches must not bypass the detailsParsed migration")
assert(next(env.LocalStorage.OrderCache) == nil,
  "unversioned imported orders must be rebuilt under the current schema")

env.LocalStorage = {
  cacheVersion = "21",
  OrderCache = { ["304-string-version"] = { orderPositions = {{amount = 1}} } },
}
assert(env.applyImportSchemaUpgrade() == true,
  "non-numeric cache versions must trigger a full reimport")

local missingNetDateOk, missingNetDateError = pcall(
  env.emitPartialReturnNetLine,
  { transactions = {}, divisor = 100 },
  {},
  "304-0000000-0000000",
  100,
  true)
assert(missingNetDateOk == false, "partial-return net line must reject a missing order date")
assert(tostring(missingNetDateError):find("Bestelldatum", 1, true),
  "missing partial-return date must report the actual data error")

local missingRefundDateOk, missingRefundDateError = pcall(
  env.getRefundFromDetails,
  {
    xpath = function()
      error("refund parser must validate the order date first")
    end,
  },
  {})
assert(missingRefundDateOk == false, "refund parsing must reject a missing order date")
assert(tostring(missingRefundDateError):find("Bestelldatum", 1, true),
  "missing refund date must report the actual data error")

assert(env.orderDetailsCompleteForEmit(
  {detailsDate = os.time() + 3600, detailsParsed = false},
  os.time(),
  "mix") == false,
  "orders without parsed details must never be emit-ready")
assert(env.orderDetailsCompleteForEmit(
  {detailsDate = os.time() + 3600, detailsParsed = true, bookingDate = "invalid"},
  os.time(),
  "mix") == false,
  "orders without a valid booking date must never be emit-ready")

env.connectShopWithCheck = function()
  return mm.HTML([[
    <html><body>
      <div id="orderDetails">
        <div data-component="orderDate"></div>
      </div>
    </body></html>
  ]])
end
local orderWithoutDate = {
  orderCode = "304-0000000-0000001",
  bookingDate = os.time(),
  detailsDate = 0,
  detailsUrl = "/order-without-date",
}
assert(env.getOrderDetails(orderWithoutDate) == false,
  "order details without a valid Amazon date must remain incomplete")
assert(orderWithoutDate.detailsParsed ~= true,
  "missing order date must not be marked as successfully parsed")

local logoutClicks = 0
env.LocalStorage = {}
local logoutHtml = {
  xpath = function()
    return {
      click = function()
        logoutClicks = logoutClicks + 1
        return "logout-response"
      end,
    }
  end,
}
for index = 1, 20 do
  local name = debug.getupvalue(env.EndSession, index)
  if name == "html" then
    debug.setupvalue(env.EndSession, index, logoutHtml)
    break
  end
end
env.connectShop = function(response)
  return response
end
env.EndSession()
assert(logoutClicks == 1, "EndSession must activate the logout link exactly once")

print("test_conformity_regressions OK")
