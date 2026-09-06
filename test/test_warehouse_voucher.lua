-- Amazon-Warehouse ("Retourenkauf") orders apply an extra ~20% discount at
-- checkout, shown as a "Gutschein eingelöst" summary row. The order-details page
-- also carries the standard "Rückgabe oder Widerruf" CTA (/spr/returns/cart),
-- which must NOT be mistaken for an active return -- otherwise the discount row
-- is skipped and the item is booked ~20% too high.
-- Run: test/run.sh test/test_warehouse_voucher.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"

local ORDER_CODE = "028-0000000-0000009"

local fails = 0
local function check(cond, msg)
  if cond then
    print("  ok  " .. msg)
  else
    print("  FAIL " .. msg)
    fails = fails + 1
  end
end

-- Anonymised copy of the /your-orders/order-details layout for a Warehouse order:
-- item unitPrice = "Summe" (incl. VAT), a -41,61 € "Gutschein eingelöst" row, and
-- a shipmentConnections return CTA that lives OUTSIDE the item's left grid.
local FIXTURE = ([[
<div id="orderDetails">
  <div data-component="orderDate">1. September 2026</div>
  <div data-component="orderId"><span>__ORDER__</span></div>
  <div data-component="chargeSummary">
    <ul class="a-unordered-list a-nostyle a-vertical">
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Zwischensumme:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">174,83 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Verpackung &amp; Versand:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">0,00 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Summe ohne MwSt.:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">174,83 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Anzurechnende MwSt.:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">33,22 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Summe:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">208,05 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span>Gutschein eingelöst:</span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-color-base">-41,61 €</span></div>
      </div></span></li>
      <li><span class="a-list-item"><div class="a-row od-line-item-row">
        <div class="a-column a-span7 od-line-item-row-label"><span class="a-text-bold"><span>Gesamtsumme:&#160;</span></span></div>
        <div class="a-column a-span5 od-line-item-row-content a-span-last"><span class="a-text-bold">166,44 €</span></div>
      </div></span></li>
    </ul>
  </div>
  <div data-component="shipments">
    <div class="a-fixed-right-grid-inner">
      <div data-component="shipmentsLeftGrid"><div class="a-fixed-right-grid-col a-col-left">
        <div data-component="shipmentStatus"><h4 class="od-status-message"><span class="a-text-bold">Zugestellt: </span><span class="a-text-bold">5. September</span></h4></div>
        <div data-component="purchasedItems">
          <div class="a-fixed-left-grid"><div class="a-fixed-left-grid-inner" style="padding-left:100px">
            <div data-component="purchasedItemsLeftGrid"><div class="a-fixed-left-grid-col a-col-left"><a href="/dp/B00TEST0000"><img alt="Monitor"/></a></div></div>
            <div data-component="purchasedItemsRightGrid"><div class="a-fixed-left-grid-col a-col-right">
              <div data-component="itemTitle"><a href="/dp/B00TEST0000">Beispiel 27-Zoll-Monitor (Retourenkauf)</a></div>
              <div data-component="orderedMerchant"><span>Verkauf durch: <a href="?node=">Amazon Retourenkauf</a></span></div>
              <div data-component="itemCondition"><span>Zustand: </span><span>Gebraucht &ndash; Sehr gut</span></div>
              <div data-component="itemReturnEligibility"><div class="a-row"><span>Rückgabe oder Widerruf: Berechtigt bis zum 19. September 2026</span></div></div>
              <div data-component="quantity"></div>
              <div data-component="unitPrice"><span class="a-price a-text-price"><span class="a-offscreen">208,05€</span><span aria-hidden="true">208,05€</span></span></div>
              <div data-component="itemConnections"><div class="a-row">
                <span class="a-button"><span class="a-button-inner"><a href="/gp/buyagain?ats=xyz" class="a-button-text">Nochmals kaufen</a></span></span>
                <span class="a-button"><span class="a-button-inner"><a href="/your-orders/pop?orderId=__ORDER__&amp;asin=B00TEST0000" class="a-button-text">Deinen Artikel anzeigen</a></span></span>
              </div></div>
            </div></div>
          </div></div>
        </div>
      </div></div>
      <div data-component="shipmentsRightGrid"><div class="a-fixed-right-grid-col a-col-right">
        <div data-component="shipmentConnections"><div class="a-button-stack">
          <span class="a-button"><span class="a-button-inner"><a href="/ps/product-support/order?orderId=__ORDER__" class="a-button-text">Produktsupport erhalten</a></span></span>
          <span class="a-button"><span class="a-button-inner"><a href="/gp/your-account/ship-track?orderId=__ORDER__" class="a-button-text">Lieferung verfolgen</a></span></span>
          <span class="a-button"><span class="a-button-inner"><a href="/spr/returns/cart?orderId=__ORDER__" class="a-button-text">Rückgabe oder Widerruf</a></span></span>
        </div></div>
      </div></div>
    </div>
  </div>
</div>
]]):gsub("__ORDER__", ORDER_CODE)

-- Route through parseAmazonHtml so the UTF-8 "€" in the amounts is decoded the
-- same way MoneyMoney decodes the live page.
env.connectShopWithCheck = function() return env.parseAmazonHtml(FIXTURE) end

local order = {
  orderCode = ORDER_CODE,
  orderPositions = {},
  orderSum = 0,
  orderTotal = 0,
  refund = 0,
  bookingDate = 0,
  detailsDate = 0,
}
check(env.getOrderDetails(order) == true, "details parsed")

print("== return-eligibility CTA is not return activity ==")
check(not order.returnActivity, "returnActivity stays false for /spr/returns/cart CTA")
check(#order.orderPositions == 1, "item kept as a purchase position, got " .. #order.orderPositions)
check(#(order.returnedPositions or {}) == 0, "no returned positions")

print("== warehouse 20% voucher is booked ==")
check(order.orderTotal == 16644, "orderTotal 166,44, got " .. tostring(order.orderTotal))
check(order.orderSum == 20805, "orderSum = unit price 208,05, got " .. tostring(order.orderSum))
local voucher
for _, extra in ipairs(order.summaryExtras or {}) do
  if (extra.name or ""):find("Gutschein") then voucher = extra end
end
check(voucher ~= nil, "Gutschein eingelöst captured as a summary extra")
check(voucher and voucher.amount == -4161, "voucher is a -41,61 credit, got " .. tostring(voucher and voucher.amount))

print("== emitted mix lines reconcile to the charged total ==")
local ctx = { mixed = true, divisor = -100, transactions = {}, accountNumber = "test@example.com" }
env.emitPurchaseLines(ctx, order, order.orderCode)
local net = 0
for _, tx in ipairs(ctx.transactions) do net = net + tx.amount end
check(math.abs(net - (-166.44)) < 0.001, "item + voucher net to -166,44, got " .. string.format("%.2f", net))
check(math.abs(env.orderRealAmount(order, -100) - (-166.44)) < 0.001,
  "orderRealAmount = -166,44, got " .. string.format("%.2f", env.orderRealAmount(order, -100)))

if fails > 0 then
  error(tostring(fails) .. " check(s) failed")
end
print("test_warehouse_voucher OK")
