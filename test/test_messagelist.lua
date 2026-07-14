-- Validates that getMessageList() degrades gracefully when Amazon's
-- /gp/message page no longer exposes the a-state ajaxToken (new layout,
-- see the "ajaxToken nil" / 404 crash reported by the user): it must return
-- an empty result instead of falling through to the broken
-- "stateData.token" fallback request.
-- Run: test/run.sh test/test_messagelist.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

-- New-layout /gp/message page: no <script type="...a-state..."> at all.
local pageWithoutToken = [[
<html><body>
<div id="message-center">no ajaxToken here</div>
</body></html>]]

local calls = 0
env.connectShop = function(method, url)
  calls = calls + 1
  assert(url == "/gp/message", "unexpected request: " .. tostring(url))
  return mm.HTML(pageWithoutToken)
end

local orderIds = env.getMessageList(os.time() - 24 * 60 * 60)

local count = 0
for _ in pairs(orderIds) do count = count + 1 end
assert(count == 0, "expected no orders from messages, got " .. count)
assert(calls == 1, "expected getMessageList to stop after the token lookup, got " .. calls .. " requests")

print("TEST_MESSAGELIST OK")
