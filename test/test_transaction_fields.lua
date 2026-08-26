-- Transaction field mapping + payment method extraction.
-- Run: luajit test/test_transaction_fields.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local paymentHtml = mm.HTML([[
<html><body>
<div id="orderDetails">
  <div data-component="viewPaymentPlanSummaryWidget">
    <h5>Zahlungsart</h5>
    <span data-testid="payment-instrument-name">MasterCard</span>
    <span data-testid="payment-instrument-prefix">****</span>
    <span data-testid="payment-instrument-number">2022</span>
  </div>
</div>
</body></html>]])
local details = paymentHtml:xpath('//div[contains(@id,"orderDetails")]')
local pay = env.getPaymentMethod(details)
assert(pay == "MasterCard **** 2022",
  "expected combined payment method, got: " .. tostring(pay))

local emptyPay = mm.HTML([[
<html><body>
<div id="orderDetails">
  <div data-component="viewPaymentPlanSummaryWidget">
    <h5>Zahlungsart</h5>
    <div>Im Moment können die Zahlungsdetails nicht angezeigt werden.</div>
  </div>
</div>
</body></html>]])
assert(env.getPaymentMethod(emptyPay:xpath('//div[contains(@id,"orderDetails")]')) == nil,
  "unavailable payment details must yield nil")

local addrHtml = mm.HTML([[
<html><body>
<div id="orderDetails">
  <div data-component="shippingAddress">
    <ul>
      <li>Roland</li>
      <li>Musterweg 1</li>
      <li>12345 Berlin</li>
    </ul>
  </div>
</div>
</body></html>]])
local orderAddr = {}
env.getOrderaddress(addrHtml:xpath('//div[contains(@id,"orderDetails")]'), orderAddr)
assert(orderAddr.shippingAddress == "Roland Musterweg 1 12345 Berlin",
  "address must land in shippingAddress, got: " .. tostring(orderAddr.shippingAddress))

local order = {
  accountNumber = "Persoenliches Konto",
  bookingText = "BT",
  mandateReference = "MasterCard **** 2022",
  shippingAddress = "Roland Musterweg 1 12345 Berlin",
}
local shortTitle = "WISO Steuer 2023"
local tx = env.makeAccountTransaction(
  order,
  "304-1180187-9045124",
  shortTitle,
  -22.99,
  1669593600
)
assert(tx.name == shortTitle, "short name stays unchanged")
assert(tx.purpose == shortTitle, "purpose is article only")
assert(tx.bookingText == order.shippingAddress, "bookingText (Umsatzart) must be shipping address")
assert(tx.batchReference == order.shippingAddress, "batchReference must be shipping address")
assert(tx.endToEndReference == "304-1180187-9045124", "Referenz (endToEndReference) must be order code")
assert(tx.mandateReference == "MasterCard **** 2022", "mandate must be payment method")
assert(tx.accountNumber == "Persoenliches Konto", "accountNumber must be sub-account")
assert(tx.amount == -22.99)

-- const.formEncoding was undefined; MM.toEncoding(nil,…) crashes MoneyMoney (signal 11).
local src = assert(io.open("amazon-orders.lua", "rb")):read("*all")
assert(src:find("MM%.toEncoding%(const%.fixEncoding,", 1),
  "encodeFormText must use const.fixEncoding")
assert(not src:find("const%.formEncoding", 1),
  "const.formEncoding must not appear (typo for fixEncoding)")

local longTitle = string.rep("A", 80) .. " END"
local txLong = env.makeAccountTransaction(order, "304-1180187-9045124", longTitle, -1, 1669593600)
assert(#txLong.name == 70, "name must be truncated to 70 chars, got " .. #txLong.name)
assert(txLong.name == string.rep("A", 70), "name prefix must be first 70 chars")
assert(txLong.purpose == longTitle, "purpose must keep full title")
assert(txLong.bookingText == order.shippingAddress)
assert(txLong.batchReference == order.shippingAddress)
assert(txLong.endToEndReference == "304-1180187-9045124")

-- UTF-8: 70 characters, not bytes (umlaut is 2 bytes)
local umlautTitle = string.rep("ä", 75)
local txUml = env.makeAccountTransaction(order, "304-1", umlautTitle, -1, 1)
assert(env.utf8Len(txUml.name) == 70, "name must be 70 UTF-8 chars")
assert(txUml.purpose == umlautTitle, "purpose keeps full UTF-8 title")
assert(txUml.bookingText == order.shippingAddress)
assert(txUml.batchReference == order.shippingAddress)

-- Invalid byte: counted as one char, truncation still safe
local bad = string.char(0x80) .. string.rep("B", 80)
assert(env.utf8CharLen(bad, 1) == nil, "lone continuation is invalid")
local txBad = env.makeAccountTransaction(order, "304-2", bad, -1, 1)
assert(env.utf8Len(txBad.name) == 70)
assert(txBad.purpose == bad)
assert(txBad.endToEndReference == "304-2")
assert(txBad.bookingText == order.shippingAddress)
assert(txBad.batchReference == order.shippingAddress)

local tx2 = env.makeAccountTransaction(
  order,
  "304-1180187-9045124",
  "Amazon contra 304-1180187-9045124",
  22.99,
  1669593600,
  "extra note"
)
assert(tx2.purpose == "extra note", "explicit purpose must be kept when provided")
assert(tx2.name == "Amazon contra 304-1180187-9045124")
assert(tx2.endToEndReference == "304-1180187-9045124")
assert(tx2.bookingText == order.shippingAddress)
assert(tx2.batchReference == order.shippingAddress)

local orderNoAddr = { accountNumber = "X", bookingText = "LegacyBT" }
local txNoAddr = env.makeAccountTransaction(orderNoAddr, "303-1", "Kabel", -1, 1)
assert(txNoAddr.purpose == "Kabel")
assert(txNoAddr.endToEndReference == "303-1")
assert(txNoAddr.batchReference == nil, "no address => no batchReference")
assert(txNoAddr.bookingText == "LegacyBT", "without address, legacy bookingText kept")

local orderOnlyAddr = { accountNumber = "X", shippingAddress = "Weg 1" }
local txOnlyAddr = env.makeAccountTransaction(orderOnlyAddr, "303-2", "Kabel", -1, 1)
assert(txOnlyAddr.bookingText == "Weg 1")
assert(txOnlyAddr.batchReference == "Weg 1")

-- Legacy migration: endToEndReference address -> shippingAddress
local legacyCache = {
  ["304-9"] = { orderCode = "304-9", endToEndReference = "Altstrasse 1" },
  ["304-8"] = { orderCode = "304-8", endToEndReference = "304-8" },
}
assert(env.migrateShippingAddressFromLegacy(legacyCache) == 1)
assert(legacyCache["304-9"].shippingAddress == "Altstrasse 1")
assert(legacyCache["304-9"].endToEndReference == nil)
assert(legacyCache["304-8"].shippingAddress == nil)

print("test_transaction_fields OK")
