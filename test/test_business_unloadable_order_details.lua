-- Real Amazon Business error page (2026-10-30, logged-in browser session, ID sanitized):
-- "Wir können deine Bestelldetails nicht laden". Must be classified as unloadable, not as a
-- missing order date, and must not count as a parsed order.
-- Run: ./test/run.sh test/test_business_unloadable_order_details.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local function check(condition, message)
  assert(condition, message)
end

local f = assert(io.open("test/fixtures/amazon_order_details_unloadable_business_20261030.html", "rb"))
local body = f:read("*all")
f:close()
local page = mm.HTML(body)
local root = page:xpath('//div[contains(@id,"orderDetails")]')

check(env.isUnloadableOrderDetailsPage(root), "real error banner must be unloadable")
check(not env.isCancelledOrderDetailsStub(root), "error banner is not a cancelled stub")

env.connectShopWithCheck = function()
  return mm.HTML(body)
end
local order = {
  orderCode = "303-0000000-0000000",
  bookingDate = env.invalidDate,
  detailsDate = 0,
}
check(env.getOrderDetails(order) == false, "unloadable page must stay unresolved")
check(not order.detailsParsed, "unloadable page must not count as parsed")
check(order.detailsDate ~= 0, "unloadable page must be rescheduled, not retried on every refresh")

print("test_business_unloadable_order_details OK")
