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
