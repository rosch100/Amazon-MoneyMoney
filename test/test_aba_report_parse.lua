-- ABA items_report text may contain order ids without order-card HTML.
-- Run: test/run.sh test/test_aba_report_parse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local csv = [[
Order ID,Title,Amount
303-5555555-6666666,Widget,12.34
302-7777777-8888888,Gadget,9.99
]]

local cache = {}
local found, foundNew, n = env.mergeOrdersFromRawText(csv, cache, "Example GmbH", "business")
assert(found == true)
assert(foundNew == true)
assert(n == 2, "expected 2 orders from CSV text, got " .. tostring(n))
assert(cache["303-5555555-6666666"].subAccountKind == "business")

print("test_aba_report_parse OK")
