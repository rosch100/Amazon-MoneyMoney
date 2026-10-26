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
