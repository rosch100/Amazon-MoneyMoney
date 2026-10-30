-- A Business orders SPA shell must not count as a personal session, even without abnav-accountfor.
-- Run: test/run.sh test/test_session_kind_business_spa.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local spaShell = env.HTML([[
<html><body><div id="ab-your-orders-anticsrf-token">token</div></body></html>]])
env.bindActiveHtml(spaShell)
assert(env.sessionMatchesSubAccountKind("business") == true, "SPA shell is a business session")
assert(env.sessionMatchesSubAccountKind("personal") == false, "SPA shell must not match personal")

local personalPage = env.HTML([[
<html><body><div id="nav">no business markers</div></body></html>]])
env.bindActiveHtml(personalPage)
assert(env.sessionMatchesSubAccountKind("personal") == true, "plain page is a personal session")
assert(env.sessionMatchesSubAccountKind("business") == false)

print("test_session_kind_business_spa OK")
