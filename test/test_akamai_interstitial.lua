-- Akamai interstitial after Amazon account switch + AB orderHistory headers.
-- Run: test/run.sh test/test_akamai_interstitial.lua
---@diagnostic disable: duplicate-set-field -- Test cases intentionally replace sandbox mocks.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local f = assert(io.open("test/fixtures/akamai_interstitial.html", "rb"))
local interstitial = mm.HTML(f:read("*all"))
f:close()

assert(env.isAkamaiInterstitial(interstitial) == true)
assert(env.isAkamaiInterstitial(mm.HTML("<html><body>ok</body></html>")) == false)

local posted = {}
env.connectShopRaw = function(method, url, postContent, contentType, headers)
  table.insert(posted, {
    method = method,
    url = url,
    postContent = postContent,
    contentType = contentType,
  })
  assert(method == "POST")
  assert(url:find("/_sec/verify", 1, true))
  assert(contentType == "application/json")
  assert(postContent:find('"pow":', 1, true))
  -- i + Number("6838".."59211") from fixture
  local expectPow = 1787668364 + tonumber("6838" .. "59211")
  assert(postContent:find('"pow":' .. tostring(expectPow), 1, true), postContent)
  return '{"reload":true}'
end
env.connectShop = function(method, url)
  assert(method == "GET")
  return mm.HTML("<html><body><span class='nav-shortened-name'>Biz</span></body></html>")
end

local nextHtml, err = env.completeAkamaiInterstitial(interstitial)
assert(err == nil, tostring(err))
assert(nextHtml ~= nil)
assert(#posted == 1)

-- finishAccountSwitchLanding must complete interstitial before ok
posted = {}
env.connectShopRaw = function(method, url, postContent, contentType, headers)
  table.insert(posted, url)
  return '{"location":"https://www.amazon.de/"}'
end
env.connectShop = function()
  return mm.HTML("<html><body>home</body></html>")
end
local land = env.finishAccountSwitchLanding(interstitial)
assert(land.ok == true, "interstitial must not be treated as silent success")
assert(#posted == 1)

print("test_akamai_interstitial OK")
