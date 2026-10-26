-- AWS WAF / softblock on the first GET must halt login with a clear error.
-- Continuing into claim yields a misleading "password incorrect" (#7).
-- Run: ./test/run.sh test/test_aws_waf_softblock.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local function readFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "rb"))
  local html = f:read("*all")
  f:close()
  return html
end

local wafHtml = readFixture("aws_waf_challenge.html")
local softShellHtml = readFixture("aws_waf_softblock_shell.html")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = {
  loginCounter = 0,
  patcher = {},
}

local wafPage = mm.HTML(wafHtml)
assert(env.isAmazonAwsWafChallengePage(wafPage) == true,
  "challenge.js softblock must be detected")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(softShellHtml)) == true,
  "empty-title en softblock shell without challenge.js must be detected")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!DOCTYPE html><html lang='en'><head><title></title></head><body><div></div></body></html>"))
  == true,
  "softblock lang='en' (single quotes) must be detected")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!DOCTYPE html><html lang=\"en-US\"><head><title></title></head><body><div></div></body></html>"))
  == true,
  "softblock lang=en-US must be detected")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!doctype html><html lang=\"de-de\"><head><title>Amazon.de</title></head>"
    .."<body><span class=\"nav-shortened-name\">Ada</span></body></html>")) == false,
  "normal Amazon page must not look like WAF softblock")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!DOCTYPE html><html lang=\"de\"><head><title></title></head><body></body></html>"))
  == false,
  "empty title alone in de must not count as softblock")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!DOCTYPE html><html lang=\"de\"><head><title>Amazon</title>"
    .."<script src=\"/static/nochallenge.js\"></script></head>"
    .."<body><div id=\"nav-logo\"></div></body></html>")) == false,
  "nochallenge.js must not count as AWS WAF challenge.js")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!DOCTYPE html><html lang=\"de-de\"><head><title>Amazon.de</title>"
    .."<script src=\"https://cdn.awswaf.com/challenge.js\"></script></head>"
    .."<body><span class=\"nav-shortened-name\">Ada</span></body></html>")) == false,
  "logged-in landing with awswaf script must not count as softblock")

local realEnterOrderList = env.enterOrderList
env.connectShop = function()
  return mm.HTML(wafHtml)
end
env.resolveAkamaiInterstitial = function(page)
  return page, nil
end
env.enterOrderList = function()
  error("enterOrderList must not run after unsolved AWS WAF softblock")
end

local result = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret-pw"},
  true)

assert(type(result) == "string", "login must return an error string, got " .. tostring(result))
assert(result:find("Bot-Prüfung", 1, true),
  "error must be the Bot-Prüfung message, got: " .. result)
assert(result:find("COOKIE:", 1, true),
  "softblock message must point to COOKIE: import, got: " .. result)
assert(result ~= env.LoginFailed,
  "must not return LoginFailed (clears cookies / looks like bad password)")

-- Softblock can appear on the order-history GET after a clean start page.
local homeOk = [[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span></body></html>]]
local shopCalls = 0
env.enterOrderList = realEnterOrderList
env.connectShop = function()
  shopCalls = shopCalls + 1
  if shopCalls == 1 then
    return mm.HTML(homeOk)
  end
  return mm.HTML(wafHtml)
end
env.resolveAkamaiInterstitial = function(page)
  return page, nil
end
-- Real enterOrderList → tryEnterOrderListGet must keep the WAF page in html.
local resultAfterList = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret-pw"},
  true)
assert(type(resultAfterList) == "string")
assert(resultAfterList:find("Bot-Prüfung", 1, true),
  "WAF after order-list entry must halt with Bot-Prüfung, got: "
    .. tostring(resultAfterList))

-- First order-history GET softblocks; a second fallback must not overwrite it.
shopCalls = 0
local junk = [[<!DOCTYPE html><html lang="de"><head><title></title></head>
<body><div>not an order list</div></body></html>]]
env.connectShop = function()
  shopCalls = shopCalls + 1
  if shopCalls == 1 then
    return mm.HTML(homeOk)
  end
  if shopCalls == 2 then
    return mm.HTML(wafHtml)
  end
  return mm.HTML(junk)
end
local resultHold = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret-pw"},
  true)
assert(type(resultHold) == "string")
assert(resultHold:find("Bot-Prüfung", 1, true),
  "WAF must survive order-list fallback GETs, got: " .. tostring(resultHold))
assert(shopCalls == 2,
  "must stop after first WAF order-list GET, shopCalls=" .. tostring(shopCalls))

-- Failed order-list GETs must not replace a prior logged-in landing.
local homeNode = mm.HTML(homeOk)
for index = 1, 40 do
  local name = debug.getupvalue(env.enterOrderList, index)
  if name == "html" then
    debug.setupvalue(env.enterOrderList, index, homeNode)
    break
  end
end
shopCalls = 0
env.connectShop = function()
  shopCalls = shopCalls + 1
  return mm.HTML(junk)
end
env.enterOrderList()
local keptHtml
for index = 1, 40 do
  local name, value = debug.getupvalue(env.enterOrderList, index)
  if name == "html" then
    keptHtml = value
    break
  end
end
assert(keptHtml == homeNode,
  "non-order interstitial GETs must keep the prior logged-in landing")

print("test_aws_waf_softblock OK")
