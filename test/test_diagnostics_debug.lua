-- Diagnostics for #3 (missing order date) and #5 (summary rows): debug mode must not
-- change parsing results; the helpers must show shapes and outcomes without page text.
-- Run: ./test/run.sh test/test_diagnostics_debug.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local function check(condition, message)
  assert(condition, message)
end

local function page(inner)
  return mm.HTML('<html><body><div id="orderDetails">' .. inner .. '</div></body></html>')
end

local function details(html)
  return mm.HTML(html):xpath('//div[@id="orderDetails"]')
end

-- 1) Text shape: digits become 9, other words become a, month names and separators stay, NBSP is a space.
check(env.textShape("Bestellt am 23. Oktober 2026") == "aaaaaaaa aa 99. Oktober 9999",
  "German date shape, got " .. tostring(env.textShape("Bestellt am 23. Oktober 2026")))
check(env.textShape("30.10.2026") == "99.99.9999", "numeric date shape")
check(env.textShape("Bestellt\194\160am  30.10.2026") == "aaaaaaaa aa 99.99.9999",
  "NBSP and whitespace collapsed")

-- 2) Date-like nodes: only nodes with digits, shapes only, no plain text.
do
  local shapes = env.orderDateNodeShapes(details(
    '<html><body><div id="orderDetails">'
    .. '<div data-component="orderDate">Bestellt am 30.10.2026</div>'
    .. '<div class="delivery-date">Geliefert am 1.11.2026</div>'
    .. '<div class="order-date-x">ohne Ziffern</div></div></body></html>'))
  check(#shapes == 2, "two date nodes with digits expected, got " .. #shapes)
  check(shapes[1]:find('dc=orderDate', 1, true) ~= nil and shapes[1]:find('shape=aaaaaaaa aa 99.99.9999', 1, true) ~= nil,
    "orderDate shape expected, got " .. shapes[1])
  check(shapes[2]:find('class=delivery-date', 1, true) ~= nil and shapes[2]:find('shape=aaaaaaaaa aa 9.99.9999', 1, true) ~= nil,
    "delivery date shape expected, got " .. shapes[2])
  for _, s in ipairs(shapes) do
    check(not s:find("30.10.2026", 1, true) and not s:find("1.11.2026", 1, true),
      "diagnostic must not contain the real date: " .. s)
  end
end

-- 3) Summary rows: debug mode changes logging only, never the booked extras.
local summaryHtml = [[
<div id="orderDetails">
  <div data-component="orderDate">20. Dezember 2025</div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Gutschein eingelöst:</span>
    <span class="od-line-item-row-content">-EUR 1,82</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Ersparnis:</span>
    <span class="od-line-item-row-content">EUR 0,00</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Sonderangebot:</span>
    <span class="od-line-item-row-content">EUR 2,00</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 30,15</span>
  </div>
</div>]]

local function extrasOf(html)
  return env.getSummaryExtrasFromDetails(details(html))
end

env.applyAccountAttribute("debug", "false")
local quiet = extrasOf(summaryHtml)
env.applyAccountAttribute("debug", "true")
local verbose = extrasOf(summaryHtml)
env.applyAccountAttribute("debug", "false")

check(#quiet == 2, "zero row is dropped, two extras remain, got " .. #quiet)
check(#verbose == #quiet, "debug must not change the number of extras")
for i, extra in ipairs(quiet) do
  check(verbose[i].name == extra.name and verbose[i].amount == extra.amount,
    "debug must not change extra " .. i)
end
check(quiet[1].amount == -182, "coupon is a credit of 1,82 €, got " .. tostring(quiet[1].amount))

-- 4) Missing order date in debug mode: still unresolved, no runtime error.
do
  env.applyAccountAttribute("debug", "true")
  env.connectShopWithCheck = function()
    return page('<div data-component="orderDate">Bestellt am unbekannt</div>'
      .. '<div class="delivery-date">Versand 12.3</div>')
  end
  local order = {
    orderCode = "303-9800000-3000000",
    bookingDate = env.invalidDate,
    detailsDate = 0,
  }
  check(env.getOrderDetails(order) == false, "missing date stays unresolved in debug mode")
  env.applyAccountAttribute("debug", "false")
end

-- 5) Shipping above the VAT row is booked incl. VAT, so no leftover remains
-- (pattern of real order 066_028 from the 2026-10-30 offline check: 31,19 total).
do
  env.connectShopWithCheck = function()
    return mm.HTML([[
<html><body><div id="orderDetails">
  <div data-component="orderDate">20. Dezember 2025</div>
  <div class="a-fixed-left-grid-inner">
    <div data-component="purchasedItemsRightGrid">
      <div data-component="itemTitle">Artikel C</div>
      <div data-component="unitPrice"><span class="a-offscreen">EUR 28,19</span></div>
    </div>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label">Verpackung &amp; Versand:</span>
    <span class="od-line-item-row-content">EUR 2,52</span>
  </div>
  <div class="od-line-item-row">
    <span class="od-line-item-row-label a-text-bold">Gesamtsumme:</span>
    <span class="od-line-item-row-content a-text-bold">EUR 31,19</span>
  </div>
</div></body></html>]])
  end
  local order = {
    orderCode = "066-0000000-0000000",
    orderPositions = {}, orderSum = 0, orderTotal = 0, refund = 0,
    bookingDate = env.invalidDate, detailsDate = 0,
  }
  check(env.getOrderDetails(order) == true, "pattern order must parse")
  check(order.orderTotal == 3119 and order.orderSum == 2819,
    "total 31,19 and items 28,19, got " .. tostring(order.orderTotal) .. " / " .. tostring(order.orderSum))
  local _, leftover = env.resolvedSummaryExtras(order)
  check(leftover == 0, "shipping incl. VAT must leave no leftover, got " .. tostring(leftover))
  check(env.resolvedSummaryExtras(order)[1].amount == 300,
    "shipping 2,52 net is booked as 3,00 gross, got " .. tostring(env.resolvedSummaryExtras(order)[1].amount))
end

-- 6) No guessing: the leftover is booked on shipping only at a statutory rate, to the cent.
do
  local function shippingOf(amount)
    return { { name = "Verpackung & Versand", amount = amount } }
  end
  local extras = shippingOf(252)
  check(env.grossUpShippingToTotal(extras, 48) == 0 and extras[1].amount == 300,
    "19 % of 2,52 must gross up to 3,00")
  extras = shippingOf(252)
  check(env.grossUpShippingToTotal(extras, 18) == 0 and extras[1].amount == 270,
    "7 % of 2,52 must gross up to 2,70")
  extras = shippingOf(252)
  check(env.grossUpShippingToTotal(extras, 100) == 100 and extras[1].amount == 252,
    "unexplained leftover must stay unbooked")
  local twoShipping = { { name = "Versand", amount = 252 }, { name = "Versand 2", amount = 100 } }
  check(env.grossUpShippingToTotal(twoShipping, 48) == 48 and twoShipping[1].amount == 252,
    "ambiguous shipping rows must not be grossed up")
end

-- Date-node diagnostics: digits show the format, letters (possibly a customer name) are masked.
check(env.textShape("Lieferung an Max Müller am 31.10.2026") == "aaaaaaaaa aa aaa aaaaaaa aa 99.99.9999",
  "text shape must mask names and keep the date format, got " .. env.textShape("Lieferung an Max Müller am 31.10.2026"))

print("test_diagnostics_debug OK")
