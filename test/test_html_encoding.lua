-- Amazon HTML is UTF-8 even if a page-level charset declaration is stale.
-- Run: test/run.sh test/test_html_encoding.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local raw = [[
<html>
  <head><meta charset="windows-1252"></head>
  <body><div data-component="itemTitle">Das Beste Von Kurz Nach Früher</div></body>
</html>
]]

env.connectShopRaw = function()
  return raw, "windows-1252"
end

local page = env.connectShop("GET", "/your-orders/order-details")
local title = page:xpath('//*[@data-component="itemTitle"]'):text()
assert(title == "Das Beste Von Kurz Nach Früher",
  "Amazon HTML must be decoded as UTF-8, got: " .. tostring(title))

print("test_html_encoding OK")
