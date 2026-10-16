-- Amazon HTML is UTF-8 even if a page-level charset declaration is stale.
-- Run: test/run.sh test/test_html_encoding.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
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

-- Order pages through about 2015 are windows-1252. Forcing UTF-8 leaves ü as 0xFC.
local legacy = mm.loadPlugin("amazon-bestellungen.lua")
local legacyRaw = "<html><body><div data-component=\"itemTitle\">Fr\252her</div></body></html>"
legacy.connectShopRaw = function()
  return legacyRaw, "UTF-8"
end
local legacyTitle = legacy.connectShop("GET", "/gp/css/summary/edit.html"):xpath('//*[@data-component="itemTitle"]'):text()
assert(legacyTitle == "Früher",
  "windows-1252 order HTML must keep umlauts, got bytes " .. tostring(legacyTitle))

local now = 1700000000
env.secUsername = "user@example.com"
local damaged = {
  detailsDate = now + 86400,
  subAccountKind = "personal",
  orderPositions = { { purpose = "Fr\239\191\189her" } },
}
assert(env.orderNeedsDetailsForAccount(damaged, now, "user@example.com") == true,
  "replacement-character titles must be fetched again")
damaged.encodingRepairDone = true
assert(env.orderNeedsDetailsForAccount(damaged, now, "user@example.com") == false,
  "one repair attempt must not loop")

print("test_html_encoding OK")
