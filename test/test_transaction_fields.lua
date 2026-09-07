-- Transaction field mapping + payment method extraction.
-- Run: luajit test/test_transaction_fields.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.MM.toEncoding = function()
  error("transaction strings must stay UTF-8")
end

local paymentHtml = mm.HTML([[
<html><body>
<div id="orderDetails">
  <div data-component="viewPaymentPlanSummaryWidget">
    <h5>Zahlungsart</h5>
    <span data-testid="payment-instrument-name">MasterCard</span>
    <span data-testid="payment-instrument-prefix">****</span>
    <span data-testid="payment-instrument-number">0000</span>
  </div>
</div>
</body></html>]])
local details = paymentHtml:xpath('//div[contains(@id,"orderDetails")]')
local pay = env.getPaymentMethod(details)
assert(pay == "MasterCard **** 0000",
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
      <li>Alex</li>
      <li>Beispielweg 1</li>
      <li>12345 Musterstadt</li>
    </ul>
  </div>
</div>
</body></html>]])
local orderAddr = {}
env.getOrderaddress(addrHtml:xpath('//div[contains(@id,"orderDetails")]'), orderAddr)
assert(orderAddr.shippingAddress == "Alex Beispielweg 1 12345 Musterstadt",
  "address must land in shippingAddress, got: " .. tostring(orderAddr.shippingAddress))

local order = {
  accountNumber = "Persoenliches Konto",
  bookingText = "BT",
  mandateReference = "MasterCard **** 0000",
  shippingAddress = "Alex Beispielweg 1 12345 Musterstadt",
}
local shortTitle = "Item A"
local tx = env.makeAccountTransaction(
  order,
  "304-1111111-1111111",
  shortTitle,
  -22.99,
  1669593600
)
assert(tx.name == shortTitle, "short name stays unchanged")
assert(tx.purpose == shortTitle, "purpose is article only")
assert(tx.bookingText == order.shippingAddress, "bookingText (Umsatzart) must be shipping address")
assert(tx.batchReference == order.shippingAddress, "batchReference must be shipping address")
assert(tx.endToEndReference == "304-1111111-1111111", "Referenz (endToEndReference) must be order code")
assert(tx.mandateReference == "MasterCard **** 0000", "mandate must be payment method")
assert(tx.accountNumber == "Persoenliches Konto", "accountNumber must be sub-account")
assert(tx.amount == -22.99)

local src = assert(io.open("amazon-bestellungen.lua", "rb")):read("*all")
assert(not src:find("MM%.toEncoding%(const%.fixEncoding,", 1),
  "MoneyMoney transaction strings must not be converted to binary data")

local longTitle = string.rep("A", 80) .. " END"
local txLong = env.makeAccountTransaction(order, "304-1111111-1111111", longTitle, -1, 1669593600)
assert(txLong.name == longTitle, "default nameMaxLength=0 keeps full title, got " .. tostring(txLong.name))
assert(txLong.purpose == longTitle, "purpose must keep full title")
assert(txLong.bookingText == order.shippingAddress)
assert(txLong.batchReference == order.shippingAddress)
assert(txLong.endToEndReference == "304-1111111-1111111")

local umlautFull = string.rep("ä", 75)
local txUmlFull = env.makeAccountTransaction(order, "304-uml", umlautFull, -1, 1)
assert(txUmlFull.name == umlautFull, "default keeps full UTF-8 title")
assert(txUmlFull.purpose == umlautFull)

env.applyAccountAttribute("nameMaxLength", "70", true)
local txCapped = env.makeAccountTransaction(order, "304-1111111-1111111", longTitle, -1, 1669593600)
assert(#txCapped.name == 70, "nameMaxLength=70 must truncate, got " .. #txCapped.name)
assert(txCapped.name == string.rep("A", 70), "name prefix must be first 70 chars")
assert(txCapped.purpose == longTitle, "purpose must keep full title when name is truncated")

-- UTF-8: nameMaxLength counts characters, not bytes (umlaut is 2 bytes)
local umlautTitle = string.rep("ä", 75)
local txUml = env.makeAccountTransaction(order, "304-1", umlautTitle, -1, 1)
assert(env.utf8Len(txUml.name) == 70, "name must be 70 UTF-8 chars")
assert(txUml.purpose == umlautTitle, "purpose keeps full UTF-8 title")
assert(txUml.bookingText == order.shippingAddress)
assert(txUml.batchReference == order.shippingAddress)

-- Invalid UTF-8 must be rejected before a malformed transaction reaches MoneyMoney.
local bad = string.char(0x80) .. string.rep("B", 80)
assert(env.utf8CharLen(bad, 1) == nil, "lone continuation is invalid")
local invalidUtf8Ok, invalidUtf8Error = pcall(
  env.makeAccountTransaction,
  order,
  "304-2",
  bad,
  -1,
  1)
assert(invalidUtf8Ok == false, "invalid UTF-8 transaction text must be rejected")
assert(tostring(invalidUtf8Error):find("UTF-8", 1, true),
  "invalid UTF-8 must produce an explicit encoding error")
for _, invalid in ipairs({
  string.char(0xC0, 0x80),
  string.char(0xE0, 0x80, 0x80),
  string.char(0xED, 0xA0, 0x80),
  string.char(0xF4, 0x90, 0x80, 0x80),
  string.char(0xF0, 0x90, 0x80),
}) do
  assert(env.isValidUtf8(invalid) == false, "invalid UTF-8 boundary must be rejected")
end
assert(env.isValidUtf8("ä") == true, "valid UTF-8 must remain accepted")
env.applyAccountAttribute("nameMaxLength", "0", true)

local tx2 = env.makeAccountTransaction(
  order,
  "304-1111111-1111111",
  "Amazon Bestellung 304-1111111-1111111",
  22.99,
  1669593600,
  "extra note"
)
assert(tx2.purpose == "extra note", "explicit purpose must be kept when provided")
assert(tx2.name == "Amazon Bestellung 304-1111111-1111111")
assert(tx2.endToEndReference == "304-1111111-1111111")
assert(tx2.bookingText == order.shippingAddress)
assert(tx2.batchReference == order.shippingAddress)

local orderNoAddr = { accountNumber = "X", bookingText = "LegacyBT" }
local txNoAddr = env.makeAccountTransaction(orderNoAddr, "303-1", "Kabel", -1, 1)
assert(txNoAddr.purpose == "Kabel")
assert(txNoAddr.endToEndReference == "303-1")
assert(txNoAddr.batchReference == nil, "no address => no batchReference")
assert(txNoAddr.bookingText == "LegacyBT", "without address, legacy bookingText kept")

local orderOnlyAddr = { accountNumber = "X", shippingAddress = "Beispielweg 1" }
local txOnlyAddr = env.makeAccountTransaction(orderOnlyAddr, "303-2", "Kabel", -1, 1)
assert(txOnlyAddr.bookingText == "Beispielweg 1")
assert(txOnlyAddr.batchReference == "Beispielweg 1")

assert(type(env.sortTransactionsNewestFirst) == "function",
  "sortTransactionsNewestFirst must be available")
local unsorted = {
  {bookingDate = 100, amount = 1},
  {bookingDate = 300, amount = 2},
  {bookingDate = 200, amount = 3},
  {bookingDate = 300, amount = 4},
}
env.sortTransactionsNewestFirst(unsorted)
assert(unsorted[1].amount == 2 and unsorted[2].amount == 4,
  "equal newest dates must preserve their existing order")
assert(unsorted[3].bookingDate == 200 and unsorted[4].bookingDate == 100,
  "transactions must be sorted newest first")

print("test_transaction_fields OK")
