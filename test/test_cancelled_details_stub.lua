-- Cancelled / unloadable order-details stubs must not loop forever.
-- Run: test/run.sh test/test_cancelled_details_stub.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local now = os.time()

local cancelledHtml = [[
<html><body>
  <div id="orderDetails" class="a-section dynamic-width">
    <div data-component="cancelled">
      <div data-component="cancelledOrderBanner">
        <div class="a-box a-alert a-alert-info">
          <h4 class="a-alert-heading">Diese Bestellung wurde storniert.</h4>
        </div>
      </div>
    </div>
  </div>
</body></html>
]]

env.connectShopWithCheck = function()
  return mm.HTML(cancelledHtml)
end

local cancelled = {
  orderCode = "305-8156868-3042735",
  detailsDate = 0,
  bookingDate = env.invalidDate or 1e99,
  detailsUrl = "/your-orders/order-details?orderID=305-8156868-3042735",
}

assert(env.getOrderDetails(cancelled) == true,
  "cancelled stub without orderDate must complete details fetch")
assert(cancelled.detailsParsed == true, "cancelled stub must be marked parsed")
assert(cancelled.unbilledCancel ~= true,
  "banner-only stub without unbilled wording must not force unbilledCancel")
assert(cancelled.bookingDate == (env.invalidDate or 1e99),
  "cancelled stub without orderDate must keep invalidDate (no cutoff skew)")
assert(type(cancelled.detailsDate) == "number" and cancelled.detailsDate > now,
  "cancelled stub must schedule detailsDate into the future")
assert(env.orderNeedsDetailsForAccount(cancelled, now, "test@example.com") == false,
  "cancelled stub must not stay due for another details fetch this refresh")

local cancelledUnbilledHtml = [[
<html><body>
  <div id="orderDetails" class="a-section dynamic-width">
    <div data-component="cancelledOrderBanner">
      <h4>Diese Bestellung wurde storniert. Diese Bestellung wurde dir nicht in Rechnung gestellt.</h4>
    </div>
  </div>
</body></html>
]]
env.connectShopWithCheck = function()
  return mm.HTML(cancelledUnbilledHtml)
end
local cancelledUnbilled = {
  orderCode = "303-8179986-7068357",
  detailsDate = 0,
  bookingDate = env.invalidDate or 1e99,
  detailsUrl = "/your-orders/order-details?orderID=303-8179986-7068357",
}
assert(env.getOrderDetails(cancelledUnbilled) == true)
assert(cancelledUnbilled.unbilledCancel == true,
  "cancelled stub with unbilled wording must set unbilledCancel")

local errorHtml = [[
<html><body>
  <div id="orderDetails">
    <div data-component="errorbanner">
      <h4>Wir können deine Bestelldetails nicht laden</h4>
    </div>
  </div>
</body></html>
]]

env.connectShopWithCheck = function()
  return mm.HTML(errorHtml)
end

local unloadable = {
  orderCode = "028-4085736-7464504",
  detailsDate = 0,
  bookingDate = now - 86400,
  detailsUrl = "/your-orders/order-details?orderID=028-4085736-7464504",
}

assert(env.getOrderDetails(unloadable) == false,
  "unloadable details page must not count as successfully parsed")
assert(unloadable.detailsParsed ~= true, "unloadable page must not set detailsParsed")
assert(type(unloadable.detailsDate) == "number" and unloadable.detailsDate > now,
  "unloadable page must schedule a retry delay instead of staying immediately due")

print("test_cancelled_details_stub OK")
