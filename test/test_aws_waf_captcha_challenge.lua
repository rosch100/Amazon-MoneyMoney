-- AWS WAF captcha challenge (C): extract sitekey, return MoneyMoney challenge, apply token.
-- Run: ./test/run.sh test/test_aws_waf_captcha_challenge.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local function readFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "rb"))
  local html = f:read("*all")
  f:close()
  return html
end

local env = mm.loadPlugin("amazon-bestellungen.lua")
local realEnterOrderList = env.enterOrderList
local withKey = mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
local noKey = mm.HTML(readFixture("aws_waf_challenge.html"))
local shell = mm.HTML(readFixture("aws_waf_softblock_shell.html"))
local relativeOnly = mm.HTML([[<!DOCTYPE html><html lang="en"><head><title></title>
<script src="/cdn/challenge.js"></script></head><body>
<div data-sitekey="x"></div></body></html>]])

local parts = env.amazonAwsWafCaptchaChallengeParts(
  withKey, "https://www.amazon.de/")
assert(type(parts) == "table", "sitekey fixture must yield challenge parts")
assert(parts.scriptUrl:find("token%.awswaf%.com", 1)
    and parts.scriptUrl:find("challenge%.js", 1),
  "scriptUrl must be token.awswaf.com challenge.js")
assert(parts.sitekey == "test-sitekey-001", "sitekey must be extracted")
assert(parts.referer == "https://www.amazon.de/", "referer must pass through")

assert(env.amazonAwsWafCaptchaChallengeParts(noKey, "https://www.amazon.de/") == nil,
  "challenge.js without sitekey / wrong host must not enable C")
assert(env.amazonAwsWafCaptchaChallengeParts(shell, "https://www.amazon.de/") == nil,
  "empty softblock shell must not enable C")
assert(env.amazonAwsWafCaptchaChallengeParts(relativeOnly, "https://www.amazon.de/") == nil,
  "relative challenge.js must not enable C")

print("ok extract")

env.LocalStorage = { loginCounter = 0, patcher = {} }
env.connectShop = function()
  return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
env.enterOrderList = function()
  error("enterOrderList must not run when WAF captcha challenge is returned")
end

local ch = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch) == "table", "expected captcha challenge table, got " .. tostring(ch))
assert(ch.title == "Amazon Bot-Prüfung", "title must be Amazon Bot-Prüfung")
assert(type(ch.challenge) == "string"
  and ch.challenge:find("token%.awswaf%.com", 1)
  and ch.challenge:find("challenge%.js", 1)
  and ch.challenge:find("sitekey=", 1, true)
  and ch.challenge:find("referer=", 1, true),
  "challenge must be awswaf script URL with sitekey+referer")
assert(env.LocalStorage.awsWafCaptchaPending == true,
  "pending flag must be set when returning captcha challenge")

env.LocalStorage = { loginCounter = 0, patcher = {} }
local msg = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, false)
assert(type(msg) == "string" and msg:find("Bot-Prüfung", 1, true),
  "non-interactive must return A message")
assert(env.LocalStorage.awsWafCaptchaPending ~= true,
  "non-interactive must not set captcha pending")

-- Softblock first appears on order-list GET: still offer C when sitekey present
env.LocalStorage = { loginCounter = 0, patcher = {} }
local homeOk = [[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span></body></html>]]
local shopCalls = 0
env.enterOrderList = realEnterOrderList
env.connectShop = function()
  shopCalls = shopCalls + 1
  if shopCalls == 1 then
    return mm.HTML(homeOk)
  end
  return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
local ch2 = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch2) == "table" and ch2.title == "Amazon Bot-Prüfung",
  "order-list softblock with sitekey must return captcha challenge, got "
    .. tostring(ch2))

print("ok challenge return")

-- Unit: empty / nil token → A
env.LocalStorage = { loginCounter = 0, patcher = {}, cookies = "session-id=1" }
env.connection = nil
assert(env.applyAmazonAwsWafCaptchaToken("") ~= nil, "empty token must return A message")
assert(env.applyAmazonAwsWafCaptchaToken(nil) ~= nil, "nil token must return A message")

-- Unit: aws-waf-token cookie via ensureAmazonShopConnection
local cookiesSet = {}
local fakeConn = {
  setCookie = function(_, c) cookiesSet[#cookiesSet + 1] = c end,
  getCookies = function() return table.concat(cookiesSet, "; ") end,
}
env.connection = nil
env.Connection = function() return fakeConn end
assert(env.applyAmazonAwsWafCaptchaToken("waf-token-stub") == nil)
local joined = table.concat(cookiesSet, " ")
assert(joined:find("aws%-waf%-token=waf%-token%-stub", 1),
  "token must be stored as aws-waf-token cookie, got: " .. joined)

-- Integration: step1 challenge → step2 token → softblock gone
env.LocalStorage = { loginCounter = 0, patcher = {} }
local phase = "softblock"
env.connection = nil
env.Connection = function() return fakeConn end
env.connectShop = function()
  if phase == "softblock" then
    return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
  end
  return mm.HTML([[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span>
<form action="/gp/css/order-history"><select name="timeFilter">
<option value="last30">30</option></select></form></body></html>]])
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
env.enterOrderList = function() end
env.discoverAmazonSubAccounts = function() return true, nil end

local ch3 = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch3) == "table", "step1 must return challenge")
assert(env.LocalStorage.awsWafCaptchaPending == true)

phase = "ok"
local step2 = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 2,
  {"waf-token-stub"}, true)
assert(type(step2) ~= "string" or not step2:find("Bot-Prüfung", 1, true),
  "step2 after token must not be softblock A, got: " .. tostring(step2))
assert(env.LocalStorage.awsWafCaptchaPending ~= true,
  "pending must clear after token apply")

-- Empty token on step2 → A
env.LocalStorage = { loginCounter = 0, patcher = {}, awsWafCaptchaPending = true }
phase = "softblock"
env.enterOrderList = function()
  error("enterOrderList must not run when WAF token missing")
end
local empty = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 2,
  {""}, true)
assert(type(empty) == "string" and empty:find("Bot-Prüfung", 1, true),
  "empty WAF token must return A")

print("ok token apply")
print("test_aws_waf_captcha_challenge OK")
