-- test/test_customer_id_parse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

local function readFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local fromFixture = env.parseAmazonCustomerIdFromHtml(
  readFixture("ab_your_orders_spa.html"))
assert(fromFixture == "A3PQNNWE23MR9U")

assert(env.parseAmazonCustomerIdFromHtml('var iss={customerId:"A1EXAMPLEID22"};') == "A1EXAMPLEID22")
assert(env.parseAmazonCustomerIdFromHtml('{"customerID":"A9ZZZZZZZZZZZ"}') == "A9ZZZZZZZZZZZ")
assert(env.parseAmazonCustomerIdFromHtml("<html></html>") == nil)
assert(env.parseAmazonCustomerIdFromHtml(nil) == nil)
assert(env.parseAmazonCustomerIdFromHtml('customerId:"not-an-id"') == nil)
print("test_customer_id_parse OK")
