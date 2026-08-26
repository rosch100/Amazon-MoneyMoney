-- Business session helpers: css order-history URL, not AB SPA nav ref.
-- Run: test/run.sh test/test_business_enter_order_list.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local businessHome = mm.HTML([[
<html><body>
<span class="abnav-accountfor">Konto für Altanis GmbH </span>
<a id="nav-orders" href="/gp/css/order-history?ref_=abn_yadd_ad_your_orders">Bestellungen</a>
</body></html>]])

assert(env.isAmazonBusinessSession(businessHome) == true)
assert(env.isAmazonBusinessSession(mm.HTML("<html><body></body></html>")) == false)

local cssUrl = env.buildCssOrderHistoryUrl(nil)
assert(cssUrl:find("/gp/css/order-history", 1, true))
assert(cssUrl:find("ref_=nav_orders_first", 1, true))
assert(not cssUrl:find("abn_yadd", 1, true), "must not use Business SPA nav ref")

print("test_business_enter_order_list OK")
