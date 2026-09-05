-- Akamai interstitial after Amazon account switch + AB orderHistory headers.
-- Run: test/run.sh test/test_akamai_interstitial.lua
---@diagnostic disable: duplicate-set-field -- Test cases intentionally replace sandbox mocks.
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local f = assert(io.open("test/fixtures/akamai_interstitial.html", "rb"))
local interstitialHtml = f:read("*all")
f:close()
local interstitial = mm.HTML(interstitialHtml)

assert(env.isAkamaiInterstitial(interstitial) == true)
assert(env.isAkamaiInterstitial(mm.HTML("<html><body>ok</body></html>")) == false)

local challenge = env.parseAkamaiInterstitialChallenge(interstitialHtml)
assert(challenge ~= nil)
assert(type(challenge.refresh) == "string" and challenge.refresh ~= "")
assert(type(challenge.bmVerify) == "string" and challenge.bmVerify ~= "")
local expectPow = 1787668364 + tonumber("6838" .. "59211")
assert(challenge.pow == expectPow, "pow mismatch: " .. tostring(challenge.pow))

-- Meta-refresh first: if it already clears the challenge, skip POST.
local posted = {}
local gets = {}
env.connectShopRaw = function()
  table.insert(posted, true)
  error("POST should not run when meta-refresh clears interstitial")
end
env.connectShop = function(method, url)
  assert(method == "GET")
  table.insert(gets, url)
  assert(url:find("bm-verify=", 1, true), "meta-refresh must keep bm-verify: " .. tostring(url))
  return mm.HTML("<html><body><span class='nav-shortened-name'>Biz</span></body></html>")
end

local nextHtml, err = env.completeAkamaiInterstitial(interstitial)
assert(err == nil, tostring(err))
assert(nextHtml ~= nil)
assert(#posted == 0, "cleared meta-refresh must not POST verify")
assert(#gets == 1)

-- Meta-refresh still interstitial → fall through to POST verify.
posted = {}
gets = {}
env.connectShopRaw = function(method, url, postContent, contentType)
  table.insert(posted, {
    method = method,
    url = url,
    postContent = postContent,
    contentType = contentType,
  })
  assert(method == "POST")
  assert(url:find("/_sec/verify", 1, true))
  assert(contentType == "application/json")
  assert(postContent:find('"pow":' .. tostring(expectPow), 1, true), postContent)
  return '{"reload":true}'
end
env.connectShop = function(method, url)
  assert(method == "GET")
  table.insert(gets, url)
  if #gets == 1 then
    return interstitial
  end
  return mm.HTML("<html><body><span class='nav-shortened-name'>Biz</span></body></html>")
end

nextHtml, err = env.completeAkamaiInterstitial(interstitial)
assert(err == nil, tostring(err))
assert(nextHtml ~= nil)
assert(#posted == 1)
assert(#gets >= 2)

-- finishAccountSwitchLanding must complete interstitial before ok
posted = {}
gets = {}
env.connectShopRaw = function()
  table.insert(posted, true)
  error("POST unused when meta-refresh clears")
end
env.connectShop = function()
  table.insert(gets, true)
  return mm.HTML("<html><body>home</body></html>")
end
local land = env.finishAccountSwitchLanding(interstitial)
assert(land.ok == true, "interstitial must not be treated as silent success")
assert(#posted == 0)
assert(#gets >= 1)

-- MoneyMoney-202609051525.log: meta-refresh clears without POST (avoids host Bad Request abort).
local badF = assert(io.open("test/fixtures/akamai_interstitial_bad_request_20260905.html", "rb"))
local badHtml = badF:read("*all")
badF:close()
local badPage = mm.HTML(badHtml)
assert(env.isAkamaiInterstitial(badPage) == true)
local badChallenge = env.parseAkamaiInterstitialChallenge(badHtml)
assert(badChallenge.pow == 1788614740 + tonumber("4279" .. "64485"))

posted = {}
gets = {}
env.connectShopRaw = function()
  table.insert(posted, true)
  error("HTTPS response: Bad Request")
end
env.connectShop = function(method, url)
  table.insert(gets, url)
  assert(url:find("bm-verify=", 1, true))
  return mm.HTML("<html><body>amazon home</body></html>")
end
nextHtml, err = env.completeAkamaiInterstitial(badPage)
assert(err == nil, tostring(err))
assert(nextHtml ~= nil)
assert(#posted == 0, "must not POST when meta-refresh already clears interstitial")
assert(#gets == 1)

-- If meta-refresh stays on interstitial and POST fails, surface a soft error (no host abort in tests).
posted = {}
gets = {}
env.connectShopRaw = function()
  table.insert(posted, true)
  error("HTTPS response: Bad Request")
end
env.connectShop = function()
  table.insert(gets, true)
  return badPage
end
nextHtml, err = env.completeAkamaiInterstitial(badPage)
assert(nextHtml == nil)
assert(type(err) == "string" and err:find("Bad Request", 1, true), tostring(err))
assert(#posted == 1)

print("test_akamai_interstitial OK")
