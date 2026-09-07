-- Validates the shim mechanics by running the real plugin function
-- getOrdersFromSummary() against a synthetic 2024+ order-list page.
-- Run: luajit test/selftest.lua   (with luarocks 5.1 paths exported)
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local page = [[
<html><body>
<div class="orders-content-container">
  <div class="order-card js-order-card"
       data-csa-c-slot-id="amzn1.yourorders.order-card.302-1234567-1234567">
    <div class="csd-encrypted-sensitive">encrypted</div>
  </div>
</div>
</body></html>]]

local html = mm.HTML(page)
local orders = env.getOrdersFromSummary(html)

local count = 0
for code, order in pairs(orders) do
  count = count + 1
  print(string.format("order=%s detailsDate=%s detailsUrl=%s",
    code, tostring(order.detailsDate), order.detailsUrl))
  assert(code == "302-1234567-1234567", "unexpected order code: " .. tostring(code))
  assert(order.detailsDate == 0, "expected detailsDate=0 to force detail fetch")
  assert(order.detailsUrl == "/your-orders/order-details?orderID=302-1234567-1234567",
    "unexpected detailsUrl: " .. tostring(order.detailsUrl))
end
assert(count == 1, "expected exactly 1 order, got " .. count)
print("SELFTEST OK")
