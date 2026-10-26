-- COOKIE: password import for Amazon sessions (additive to password login).
-- Run: ./test/run.sh test/test_cookie_import.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = { loginCounter = 0, patcher = {} }

local validCookies =
  "session-id=138-1111111-2222222; at-acbde=Atza|fake; sess-at-acbde=Ag|; ubid-acbde=x"

assert(env.normalizeImportedCookieString(" a=1, b=2 ") == "a=1; b=2",
  "comma-separated cookie lists must normalize to semicolon form")
assert(env.normalizeImportedCookieString("a=1; b=2") == "a=1; b=2",
  "semicolon lists must stay intact")

assert(env.amazonImportedCookiesMissingRequired("session-id=only") ~= nil,
  "auth token cookie must be required")
assert(env.amazonImportedCookiesMissingRequired("at-acbde=Atza|x") ~= nil,
  "session-id must be required")
assert(env.amazonImportedCookiesMissingRequired(validCookies) == nil,
  "session-id + at-acbde must satisfy required cookies")
assert(env.amazonImportedCookiesMissingRequired(
  "session-id=1; at-main=Atza|x") == nil,
  "at-main must also count as auth token")

local loggedInHtml = [[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body>
  <span class="nav-shortened-name">Ada</span>
  <form name="timeFilter" action="/your-orders/orders">
    <select name="timeFilter" id="time-filter"><option value="months-3">3 Monate</option></select>
  </form>
  <div class="order-card js-order-card" data-csa-c-slot-id="amzn1.yourorders.order-card.303-1111111-2222222"></div>
</body></html>]]

local softShell = assert(io.open("test/fixtures/aws_waf_softblock_shell.html", "rb")):read("*all")
local signInHtml = [[<!doctype html><html lang="de-de"><head><title>Anmelden</title></head>
<body><form name="signIn"><input name="email"/><input id="ap_password" name="password"/></form></body></html>]]

-- Success: COOKIE: skips claim and establishes session from jar.
env.connection = false
env.connectShop = function()
  return mm.HTML(loggedInHtml)
end
env.resolveAkamaiInterstitial = function(page)
  return page, nil
end
env.enterOrderList = function() end
env.discoverAmazonSubAccounts = function()
  return true, nil
end

local ok = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "COOKIE:" .. validCookies},
  true)
assert(ok == nil, "cookie import login must succeed, got " .. tostring(ok))
assert(type(env.LocalStorage.cookies) == "string"
    and env.LocalStorage.cookies:find("session-id=", 1, true),
  "imported cookies must be persisted in LocalStorage")
assert(env.secPassword == nil or env.secPassword == "",
  "cookie blob must not become secPassword")

-- Cookie-only: claim-collect hint must still be stripped without secPassword.
local claimOnly = mm.HTML([[<html><body>
<form name="signIn">
  <input type="hidden" name="subPageType" value="SignInClaimCollect"/>
  <input type="email" name="email" value=""/>
  <input type="password" id="ap-credential-autofill-hint" name="password" value="x"/>
</form>
</body></html>]])
env.secPassword = nil
env.fillAmazonSignInFields(claimOnly)
assert(claimOnly:xpath('//*[@name="password"]'):length() == 0,
  "claim-collect password name must be cleared without secPassword")
assert(claimOnly:xpath('//*[@id="ap-credential-autofill-hint"]'):attr("disabled") == "disabled",
  "claim-collect hint must be disabled without secPassword")

-- Softblock after import still returns Bot-Prüfung (not LoginFailed).
env.LocalStorage.cookies = nil
env.connectShop = function()
  return mm.HTML(softShell)
end
local soft = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "COOKIE:" .. validCookies},
  true)
assert(type(soft) == "string" and soft:find("Bot-Prüfung", 1, true),
  "softblock after cookie import must return Bot-Prüfung, got: " .. tostring(soft))

-- Sign-in page after import → expired session guidance.
env.connectShop = function()
  return mm.HTML(signInHtml)
end
env.enterOrderList = function() end
local expired = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "COOKIE:" .. validCookies},
  true)
assert(type(expired) == "string"
    and (expired:find("abgelaufen", 1, true) or expired:find("Cookie", 1, true)),
  "expired cookie session must ask to re-import, got: " .. tostring(expired))

-- Invalid COOKIE payload never hits the network.
local net = false
env.connectShop = function()
  net = true
  return mm.HTML(loggedInHtml)
end
local bad = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "COOKIE:session-id=only"},
  true)
assert(net == false, "incomplete COOKIE: must not call connectShop")
assert(type(bad) == "string" and bad:find("unvollständig", 1, true),
  "incomplete cookies need a clear validation error, got: " .. tostring(bad))

-- COOKIE: sessions must not remote-logout (would invalidate imported at-* cookies).
env.connectShop = function()
  return mm.HTML(loggedInHtml)
end
env.enterOrderList = function() end
env.discoverAmazonSubAccounts = function()
  return true, nil
end
assert(env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "COOKIE:" .. validCookies},
  true) == nil, "cookie import for EndSession test must succeed")

local logoutClicks = 0
local logoutHtml = {
  xpath = function()
    return {
      click = function()
        logoutClicks = logoutClicks + 1
        return "logout-response"
      end,
    }
  end,
}
for index = 1, 40 do
  local name = debug.getupvalue(env.EndSession, index)
  if name == "html" then
    debug.setupvalue(env.EndSession, index, logoutHtml)
    break
  end
end
env.connectShop = function(response)
  return response
end
env.EndSession()
assert(logoutClicks == 0,
  "COOKIE: EndSession must not click sign-out (imported cookies stay valid)")

print("test_cookie_import OK")
