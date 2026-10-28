-- Regression tests for order-date variants reported in issue #3.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
local invalidDate = env.invalidDate or 1e99

local function check(condition, message)
  assert(condition, message)
end

local nbsp = string.char(194, 160)

check(
  env.getDate("Bestellt am 23." .. nbsp .. "Oktober" .. nbsp .. "2026")
    ~= invalidDate,
  "UTF-8 non-breaking spaces must not invalidate an order date"
)

local function page(inner)
  return mm.HTML('<html><body><div id="orderDetails">' .. inner .. '</div></body></html>')
end

do
  local details = page('<div data-component="orderDate">Bestellt am unbekannt</div>')
  local date, source, diagnostics = env.getOrderDateFromDetails(
    details:xpath('//div[@id="orderDetails"]'))
  check(date == invalidDate, "unparseable order date remains invalid")
  check(source == nil, "unparseable order date has no source")
  check(
    diagnostics[1]:match("^data%-component=orderDate=1/%d+$") ~= nil,
    "missing-date diagnostics identify the primary selector without page content"
  )
end

local variants = {
  {
    name = "later matching order-date node",
    html = '<div data-component="orderDate"></div>'
      .. '<div data-component="orderDate">Bestellt am 8. Mai 2026</div>',
    expected = "2026-05-08",
  },
  {
    name = "legacy order-date class",
    html = '<div class="order-date-invoice-item">Bestellt am 12. M&auml;rz 2014</div>',
    expected = "2014-03-12",
  },
  {
    name = "semantic order-date test id",
    html = '<div data-testid="order-date">Order placed 7. April 2025</div>',
    expected = "2025-04-07",
  },
}

for _, variant in ipairs(variants) do
  env.connectShopWithCheck = function()
    return page(variant.html)
  end

  local order = {
    orderCode = "303-9800000-3000000",
    bookingDate = invalidDate,
    detailsDate = 0,
  }
  check(env.getOrderDetails(order) == true, variant.name .. ": details parsed")
  check(
    os.date("%Y-%m-%d", order.bookingDate) == variant.expected,
    variant.name .. ": expected " .. variant.expected
  )
end

print("order date parsing OK")
