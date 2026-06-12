-- Validates the shim mechanics by running the real plugin function
-- getOrdersFromSummary() against a synthetic OLD-layout order-list page.
-- Run: luajit test/selftest.lua   (with luarocks 5.1 paths exported)
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local page = [[
<html><body>
<div id="ordersContainer">
  <div class="a-box-group order">
    <div class="a-box a-spacing-base order-info">
      <div class="a-row">
        <span class="a-color-secondary value">12. Juni 2026</span>
        <span class="a-color-secondary value">EUR 19,99</span>
        <span class="a-color-secondary value">302-1234567-1234567</span>
      </div>
      <a class="a-link-normal" href="/gp/your-account/order-details/?orderID=302-1234567-1234567">Details</a>
    </div>
  </div>
</div>
</body></html>]]

local html = mm.HTML(page)
local orders = env.getOrdersFromSummary(html)

local count = 0
for code, order in pairs(orders) do
  count = count + 1
  print(string.format("order=%s date=%s total=%s detailsUrl=%s",
    code, os.date("%Y-%m-%d", order.bookingDate), tostring(order.orderTotal), order.detailsUrl))
  assert(code == "302-1234567-1234567", "unexpected order code: " .. tostring(code))
  assert(order.orderTotal == 1999, "unexpected total: " .. tostring(order.orderTotal))
end
assert(count == 1, "expected exactly 1 order, got " .. count)
print("SELFTEST OK")
