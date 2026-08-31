-- Parser regression tests using deterministic, anonymized HTML fixtures.
-- Run: test/run.sh test/test_parse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local fails = 0
local function check(condition, message)
  if condition then
    print("  ok  " .. message)
    return
  end
  print("  FAIL " .. message)
  fails = fails + 1
end

local function summaryRow(label, amount, bold)
  local boldClass = bold and " a-text-bold" or ""
  return '<div class="od-line-item-row">'
    .. '<span class="od-line-item-row-label' .. boldClass .. '">' .. label .. '</span>'
    .. '<span class="od-line-item-row-content' .. boldClass .. '">EUR ' .. amount .. '</span>'
    .. '</div>'
end

local function itemHtml(item)
  local quantity = item.quantity
    and '<div class="od-item-view-qty">Menge: ' .. tostring(item.quantity) .. '</div>'
    or ""
  return '<div class="a-fixed-left-grid-inner">'
    .. quantity
    .. '<div data-component="purchasedItemsRightGrid">'
    .. '<div data-component="itemTitle">' .. item.title .. '</div>'
    .. '<div data-component="unitPrice"><span class="a-offscreen">EUR ' .. item.amount .. '</span></div>'
    .. '</div></div>'
end

local function detailHtml(spec)
  local parts = {
    '<div id="orderDetails">',
    '<div data-component="orderDate">' .. spec.date .. '</div>',
  }
  for _, item in ipairs(spec.items) do
    parts[#parts + 1] = itemHtml(item)
  end
  for _, row in ipairs(spec.rows or {}) do
    parts[#parts + 1] = summaryRow(row.label, row.amount, row.bold)
  end
  parts[#parts + 1] = summaryRow("Gesamtsumme:", spec.total, true)
  if spec.address then
    parts[#parts + 1] = '<div data-component="shippingAddress"><ul>'
      .. '<li>Alex Beispiel</li><li>Musterweg 1</li><li>12345 Musterstadt</li>'
      .. '</ul></div>'
  end
  parts[#parts + 1] = '</div>'
  return table.concat(parts)
end

local function parseDetail(spec, orderCode)
  env.connectShopWithCheck = function()
    return mm.HTML(detailHtml(spec))
  end
  local order = {
    orderCode = orderCode,
    orderPositions = {},
    orderSum = 0,
    orderTotal = 0,
    refund = 0,
    bookingDate = 0,
    detailsDate = 0,
  }
  check(env.getOrderDetails(order) == true, orderCode .. " details parsed")
  return order
end

print("== list: enumerate order codes ==")
do
  local cards = {}
  for index = 1, 10 do
    cards[#cards + 1] = '<div class="order-card" '
      .. 'data-csa-c-slot-id="amzn1.yourorders.order-card.304-0000000-'
      .. string.format("%07d", index) .. '"></div>'
  end
  local orders = env.getOrdersFromSummary(mm.HTML("<html><body>" .. table.concat(cards) .. "</body></html>"))
  local count = 0
  for _, order in pairs(orders) do
    count = count + 1
    check(order.detailsDate == 0, "order forces detail fetch")
    check(type(order.detailsUrl) == "string" and order.detailsUrl ~= "", "order has detailsUrl")
  end
  check(count == 10, "expected 10 orders from list page")
end

print("== single item and address ==")
do
  local order = parseDetail({
    date = "20. Dezember 2025",
    items = {{ title = "Monitor", amount = "169,98" }},
    total = "169,98",
    address = true,
  }, "304-0000001-0000001")
  check(os.date("%Y-%m-%d", order.bookingDate) == "2025-12-20", "order date 2025-12-20")
  check(order.orderTotal == 16998, "orderTotal 169,98")
  check(#order.orderPositions == 1, "1 position")
  check(order.orderPositions[1] and order.orderPositions[1].amount == 16998, "position amount 169,98")
  check(order.orderSum == 16998, "orderSum 169,98")
  check(type(order.shippingAddress) == "string" and order.shippingAddress ~= "", "address captured")
end

print("== multiple items and coupon difference ==")
do
  local order = parseDetail({
    date = "20. Dezember 2025",
    items = {
      { title = "Artikel A", amount = "10,99" },
      { title = "Artikel B", amount = "7,99" },
      { title = "Artikel C", amount = "14,99" },
    },
    total = "32,15",
  }, "304-0000002-0000002")
  check(#order.orderPositions == 3, "3 positions")
  check(order.orderSum == 3397, "orderSum 33,97")
  check(order.orderTotal == 3215, "orderTotal 32,15")
  check(order.orderSum - order.orderTotal == 182, "difference 1,82")
end

print("== refund row ==")
do
  local order = parseDetail({
    date = "21. Dezember 2025",
    items = {
      { title = "Artikel A", amount = "10,00" },
      { title = "Artikel B", amount = "11,00" },
      { title = "Artikel C", amount = "12,00" },
      { title = "Artikel D", amount = "19,50" },
    },
    rows = {{ label = "Summe der Erstattung", amount = "6,73" }},
    total = "52,50",
  }, "304-0000003-0000003")
  check(#order.orderPositions == 4, "4 positions")
  check(order.orderTotal == 5250, "orderTotal excludes refund row")
  local refundTotal = 0
  for _, amounts in pairs(order.refundTransactions or {}) do
    for amount in pairs(amounts) do
      refundTotal = refundTotal + amount
    end
  end
  check(refundTotal == 673, "refund amount 6,73")
end

print("== digital and gift-card items ==")
do
  local digital = parseDetail({
    date = "22. Dezember 2025",
    items = {{ title = "Digitaler Inhalt", amount = "9,95" }},
    total = "9,95",
  }, "304-0000004-0000004")
  check(#digital.orderPositions == 1 and digital.orderSum == 995, "digital item 9,95")

  local giftCard = parseDetail({
    date = "23. Dezember 2025",
    items = {{ title = "Geschenkgutschein", amount = "15,00" }},
    total = "15,00",
  }, "304-0000005-0000005")
  check(#giftCard.orderPositions == 1 and giftCard.orderTotal == 1500, "gift card 15,00")
end

print("== quantity greater than one ==")
do
  local order = parseDetail({
    date = "24. Dezember 2025",
    items = {{ title = "Doppelpack", amount = "11,59", quantity = 2 }},
    total = "20,86",
  }, "304-0000006-0000006")
  check(#order.orderPositions == 1, "1 position")
  check(order.orderPositions[1] and order.orderPositions[1].qty == 2, "quantity 2")
  check(order.orderPositions[1] and order.orderPositions[1].amount == 1159, "unit price 11,59")
  check(order.orderSum == 2318, "orderSum 23,18")
  check(order.orderTotal == 2086, "orderTotal 20,86")
end

if fails > 0 then
  error(tostring(fails) .. " parser check(s) failed")
end
print("test_parse OK")
