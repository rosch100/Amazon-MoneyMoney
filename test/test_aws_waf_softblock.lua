-- AWS WAF / softblock on the first GET must halt login with a clear error.
-- Continuing into claim yields a misleading "password incorrect" (#7).
-- Run: ./test/run.sh test/test_aws_waf_softblock.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local f = assert(io.open("test/fixtures/aws_waf_challenge.html", "rb"))
local wafHtml = f:read("*all")
f:close()

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = {
  loginCounter = 0,
  patcher = {},
}

local wafPage = mm.HTML(wafHtml)
assert(env.isAmazonAwsWafChallengePage(wafPage) == true,
  "challenge.js softblock must be detected")
assert(env.isAmazonAwsWafChallengePage(mm.HTML(
  "<!doctype html><html lang=\"de-de\"><head><title>Amazon.de</title></head>"
    .."<body><span class=\"nav-shortened-name\">Ada</span></body></html>")) == false,
  "normal Amazon page must not look like WAF softblock")

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
assert(result:find("Bot-Prüfung", 1, true) or result:find("WAF", 1, true),
  "error must name the bot/WAF block, got: " .. result)
assert(result ~= env.LoginFailed,
  "must not return LoginFailed (clears cookies / looks like bad password)")
print("test_aws_waf_softblock OK")
