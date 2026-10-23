-- Issue #3: Bestelldetails ohne parsebares orderDate dürfen nicht bei jedem Abruf erneut geladen werden.
-- Run: test/run.sh test/test_missing_order_date_backoff.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local INVALID = env.invalidDate or 1e99
local now = os.time()

local function page(inner)
  return mm.HTML('<html><body><div id="orderDetails" class="a-section">' .. inner .. '</div></body></html>')
end

-- Seitenvarianten mit Root-Text, aber ohne parsebares orderDate (Harness issue3).
local variants = {
  missing_component = '<div data-component="orderId">303-9800000-3000000</div><div data-component="purchasedItems">Artikel</div>',
  empty_component   = '<div data-component="orderDate"></div><div data-component="orderId">303-9800000-3000000</div>',
  nbsp_component    = '<div data-component="orderDate"><span>Bestellt am</span> <span>23.&nbsp;Oktober&nbsp;2026</span></div>',
  legacy_layout     = '<div class="order-date-invoice-item">Bestellt am 12. M&auml;rz 2014</div><div class="od-shipping-address-container"><div class="a-row">Name</div></div>',
}

for name, inner in pairs(variants) do
  env.connectShopWithCheck = function() return page(inner) end
  local order = {
    orderCode = "303-9800000-3000000",
    detailsDate = 0,
    bookingDate = INVALID,
    detailsUrl = "/your-orders/order-details?orderID=303-9800000-3000000",
  }
  assert(env.getOrderDetails(order) == false,
    name .. ": missing order date must still count as an incomplete details fetch")
  assert(order.detailsParsed ~= true,
    name .. ": missing order date must not be marked as successfully parsed")
  assert(order.bookingDate == INVALID,
    name .. ": missing order date must keep invalidDate as bookingDate")
  assert(type(order.detailsDate) == "number" and order.detailsDate > now,
    name .. ": missing order date must schedule detailsDate into the future, got " .. tostring(order.detailsDate))
  assert(env.orderNeedsDetailsForAccount(order, now + 3600, "test@example.com") == false,
    name .. ": order without date must not be due again on the next refresh")
end

print("missing order date backoff OK")
