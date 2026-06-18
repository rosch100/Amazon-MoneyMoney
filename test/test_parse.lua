-- Parsing tests against saved real pages in test/pages/.
-- Run: test/run.sh test/test_parse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local function readfile(p)
  local f = assert(io.open(p, "rb")); local s = f:read("*all"); f:close(); return s
end

local fails = 0
local function check(cond, msg)
  if cond then
    print("  ok  " .. msg)
  else
    print("  FAIL " .. msg)
    fails = fails + 1
  end
end

-- Parse a detail page by stubbing the network fetch with saved HTML.
local function parseDetail(file, orderCode)
  local pageHtml = readfile("test/pages/" .. file)
  env.connectShopWithCheck = function() return mm.HTML(pageHtml) end
  local order = {
    orderCode = orderCode, orderPositions = {}, orderSum = 0,
    orderTotal = 0, refund = 0, bookingDate = 0, detailsDate = 0,
  }
  env.getOrderDetails(order)
  return order
end

local function eur(cents) return string.format("%.2f", cents / 100) end
local function dump(order)
  print(string.format("  -> code=%s date=%s total=%s sum=%s positions=%d",
    order.orderCode, os.date("%Y-%m-%d", order.bookingDate),
    eur(order.orderTotal), eur(order.orderSum), #order.orderPositions))
  for i, p in ipairs(order.orderPositions) do
    print(string.format("     [%d] qty=%s amount=%s  %s", i, tostring(p.qty), eur(p.amount), (p.purpose or ""):sub(1, 60)))
  end
  if order.endToEndReference then print("     addr: " .. order.endToEndReference) end
end

------------------------------------------------------------------ LIST
print("== list.html: enumerate order codes ==")
do
  local html = mm.HTML(readfile("test/pages/list.html"))
  local orders = env.getOrdersFromSummary(html)
  local n = 0
  for code, o in pairs(orders) do
    n = n + 1
    check(o.detailsDate == 0, "order " .. code .. " forces detail fetch")
    check(o.detailsUrl ~= nil and o.detailsUrl ~= "", "order " .. code .. " has detailsUrl")
  end
  print("  enumerated " .. n .. " orders")
  check(n == 10, "expected 10 orders from list page")
end

------------------------------------------------------------------ SINGLE
print("== details-single.html ==")
do
  local o = parseDetail("details-single.html", "304-1959277-6233165")
  dump(o)
  check(os.date("%Y-%m-%d", o.bookingDate) == "2025-12-20", "order date 2025-12-20")
  check(o.orderTotal == 16998, "orderTotal 169,98")
  check(#o.orderPositions == 1, "1 position")
  check(o.orderPositions[1] and o.orderPositions[1].amount == 16998, "position amount 169,98")
  check(o.orderPositions[1] and o.orderPositions[1].qty == 1, "position qty 1")
  check(o.orderSum == 16998, "orderSum 169,98")
  check(o.endToEndReference and o.endToEndReference:find("Chattenweg") ~= nil, "address captured")
end

------------------------------------------------------------------ MULTI
print("== details-multi.html ==")
do
  local o = parseDetail("details-multi.html", "304-6060868-3893966")
  dump(o)
  check(#o.orderPositions == 3, "3 positions")
  check(o.orderSum == 3397, "orderSum 33,97 (10,99+7,99+14,99)")
  check(o.orderTotal == 3215, "orderTotal 32,15 (Gesamtsumme, after coupon)")
  check(o.orderSum - o.orderTotal == 182, "difference 1,82 (coupon)")
end

------------------------------------------------------------------ REFUND
print("== details-multi-with-refund.html ==")
do
  local o = parseDetail("details-multi-with-refund.html", "?")
  dump(o)
  check(#o.orderPositions == 4, "4 positions")
  check(o.orderTotal == 5250, "orderTotal 52,50 (not the refund row)")
  check(o.refundTransactions ~= nil, "refund captured")
  if o.refundTransactions then
    local total = 0
    for d, amounts in pairs(o.refundTransactions) do
      for amount, _ in pairs(amounts) do total = total + amount end
    end
    check(total == 673, "refund amount 6,73")
  end
end

------------------------------------------------------------------ DIGITAL
print("== details-digital.html ==")
do
  local o = parseDetail("details-digital.html", "?")
  dump(o)
  check(#o.orderPositions == 1, "1 position")
  check(o.orderTotal == 995, "orderTotal 9,95")
  check(o.orderSum == 995, "orderSum 9,95")
end

------------------------------------------------------------------ GIFT CARD
print("== details-giftcard.html ==")
do
  local o = parseDetail("details-giftcard.html", "?")
  dump(o)
  check(#o.orderPositions == 1, "1 position")
  check(o.orderTotal == 1500, "orderTotal 15,00")
end

------------------------------------------------------------------ QTY > 1
print("== details-quantity-other-than-1.html ==")
do
  local o = parseDetail("details-quantity-other-than-1.html", "304-2173771-7757910")
  dump(o)
  check(#o.orderPositions == 1, "1 position")
  check(o.orderPositions[1] and o.orderPositions[1].qty == 2, "quantity 2 (from badge)")
  check(o.orderPositions[1] and o.orderPositions[1].amount == 1159, "unit price 11,59")
  check(o.orderSum == 2318, "orderSum 23,18 (2 x 11,59)")
  check(o.orderTotal == 2086, "orderTotal 20,86 (Gesamtsumme after coupon)")
  check(o.orderSum - o.orderTotal == 232, "difference 2,32 (coupon)")
end

print(string.rep("-", 50))
if fails == 0 then print("ALL TESTS PASSED") else print(fails .. " CHECK(S) FAILED"); os.exit(1) end
