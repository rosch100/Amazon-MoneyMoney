-- Login flow: a wrong OTP code asks again (no hard abort), a correct code logs in,
-- a wrong password stays a credential rejection, and unexpected pages name the stage.
-- Run: ./test/run.sh test/test_login_otp_reprompt_and_stage.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local signInForm = [[
<form name="signIn" method="post" action="https://www.amazon.de/ap/signin">
  <input type="hidden" name="appAction" value="SIGNIN_PASSWORD_ASSERT"/>
  <input type="text" id="ap_email" name="email" value=""/>
  <input type="password" id="ap_password" name="password" value=""/>
</form>]]

local startHtml = "<html><body>" .. signInForm .. "</body></html>"

local wrongPasswordHtml = '<html><body><div id="auth-error-message-box">'
  .. "Ihr Passwort ist falsch.</div>" .. signInForm .. "</body></html>"

local claimHtml = [[<html><body>
<form id="ap_login_form" name="signIn" method="post" action="https://www.amazon.de/ax/claim">
  <input type="hidden" name="appAction" value="SIGNIN_CLAIM_COLLECT"/>
  <input type="hidden" name="subPageType" value="FullPageUnifiedClaimCollect"/>
  <input type="text" id="ap_email_login" name="email" value=""/>
  <input type="password" id="auth-credential-autofill-hint" name="password" value=""/>
</form>
</body></html>]]

local loggedInHtml = [[<html><body>
<form action="/gp/css/order-history">
  <select name="timeFilter"><option value="last30">30 Tage</option></select>
</form>
<span class="nav-shortened-name">Ada</span>
</body></html>]]

local unknownHtml = "<html><body><p>Unbekannte Seite</p></body></html>"

local function mfaPage(errorText)
  local errorBox = ""
  if errorText ~= nil then
    errorBox = '<div id="auth-error-message-box">' .. errorText .. "</div>"
  end
  return mm.HTML("<html><body>" .. errorBox .. [[
<form id="auth-mfa-form" action="/ap/signin" method="post">
  <p>Code aus der Authenticator-App</p>
  <input name="otpCode" type="text"/>
  <input name="rememberDevice" type="checkbox"/>
</form>
</body></html>]])
end

-- Plugin with a scripted sequence of form responses. Every form submit is recorded.
local function newLogin(startPage, responses)
  -- Stage names are detail trace lines, enabled like a user would: account note debug=true,
  -- stored with the account so the login applies it.
  local env = mm.loadPlugin("amazon-bestellungen.lua", { loginCounter = 0, patcher = { debug = "true" } })
  local statuses = {}
  env.MM = setmetatable({
    printStatus = function(text)
      statuses[#statuses + 1] = text
    end,
  }, { __index = env.MM })
  local logs = {}
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring((select(i, ...)))
    end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  local posts = {}
  env.connectShop = function()
    return mm.HTML(startPage)
  end
  env.connectShopForm = function(form)
    local _, _, body = form:submit()
    posts[#posts + 1] = body or ""
    local nextPage = table.remove(responses, 1)
    assert(nextPage ~= nil, "unexpected extra form submit #" .. #posts)
    return nextPage
  end
  env.discoverAmazonSubAccounts = function()
    return {}, nil
  end
  return env, logs, posts, statuses
end

local function hasLog(logs, needle)
  for _, line in ipairs(logs) do
    if line:find(needle, 1, true) then
      return true
    end
  end
  return false
end

-- 1) Wrong OTP: Amazon's message is shown and the code is asked again.
do
  local env, logs, posts = newLogin(startHtml, {
    mfaPage(nil),
    mfaPage("Der Code ist nicht korrekt."),
    mm.HTML(loggedInHtml),
  })
  local first = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  assert(type(first) == "table" and first.title == "Zwei-Faktor-Authentifizierung",
    "first OTP challenge expected, got: " .. tostring(first))
  assert(first.challenge:find("Authenticator", 1, true), "prompt must name the app")
  assert(not first.challenge:find("Der Code ist nicht korrekt.", 1, true),
    "first challenge must not show an error")

  local again = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2,
    { "111111" }, true)
  assert(type(again) == "table",
    "wrong OTP must ask again instead of aborting, got: " .. tostring(again))
  assert(again.title == "Zwei-Faktor-Authentifizierung")
  assert(again.challenge:find("Der Code ist nicht korrekt.", 1, true),
    "Amazon's error text must be shown with the new challenge")
  assert(again.challenge:find("Authenticator", 1, true),
    "original prompt must stay in the challenge")
  assert(posts[2]:find("otpCode=111111", 1, true), "first code must be posted")
  assert(hasLog(logs, "login otp rejected by Amazon, asking again (submitted 1)"))

  local done = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2,
    { "222222" }, true)
  assert(done == nil, "correct OTP must log in, got: " .. tostring(done))
  assert(posts[3]:find("otpCode=222222", 1, true), "second code must be posted")
  assert(not posts[3]:find("otpCode=111111", 1, true), "old code must not be reused")
  assert(hasLog(logs, "login otp submit 2"))
end

-- 2) OTP page without error box: asked again with the plain prompt (no error text).
do
  local env, logs = newLogin(startHtml, {
    mfaPage(nil),
    mfaPage(nil),
  })
  env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  local again = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2,
    { "333333" }, true)
  assert(type(again) == "table", "OTP page must be asked again, got: " .. tostring(again))
  assert(again.challenge == "Code aus der Authenticator-App" or
    again.challenge == "Bitte den Code aus der Authenticator-App eingeben.",
    "plain prompt expected, got: " .. tostring(again.challenge))
  assert(not hasLog(logs, "login otp rejected by Amazon"),
    "no rejection without an error box")
end

-- 3) Wrong password is still a credential rejection (LoginFailed).
do
  local env = newLogin(startHtml, { mm.HTML(wrongPasswordHtml) })
  local result = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "falsch" }, true)
  assert(result == "LoginFailed",
    "wrong password must stay LoginFailed, got: " .. tostring(result))
end

-- 4) Unexpected page names the stage where the login was last handled.
do
  local env, logs = newLogin(startHtml, { mm.HTML(unknownHtml) })
  local result = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  assert(type(result) == "string"
      and result:find("Unerwartete Antwort nach Stufe Passwort-Schritt", 1, true),
    "stage must be named in the error, got: " .. tostring(result))
  assert(hasLog(logs, "login step: Passwort-Schritt"))
end

-- 5) Claim-collect (email) step is named as E-Mail-Schritt, not as password step.
do
  local env, logs = newLogin(claimHtml, { mm.HTML(unknownHtml) })
  local result = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  assert(type(result) == "string"
      and result:find("Unerwartete Antwort nach Stufe E-Mail-Schritt", 1, true),
    "claim step must be named E-Mail-Schritt, got: " .. tostring(result))
  assert(hasLog(logs, "login step: E-Mail-Schritt"))
end

-- Real Amazon pages from the 2026-10-30 logs (sanitized, see test/fixtures).
local function loadFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "rb"))
  local body = f:read("*all")
  f:close()
  return mm.HTML(body)
end

-- 6) Real wrong-OTP page: the OTP form stays on screen with Amazon's alert.
do
  local env, logs, posts = newLogin(startHtml, {
    loadFixture("amazon_mfa_otp_20261030.html"),
    loadFixture("amazon_mfa_wrong_otp_20261030.html"),
    mm.HTML(loggedInHtml),
  })
  local first = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  assert(type(first) == "table" and first.challenge:find("Einmalkennwort", 1, true),
    "real OTP prompt expected, got: " .. tostring(first))

  local again = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2,
    { "111111" }, true)
  assert(type(again) == "table",
    "real wrong OTP must ask again, got: " .. tostring(again))
  assert(again.challenge:find("Der eingegebene Code ist ungültig. Bitte erneut versuchen.", 1, true),
    "Amazon's alert must be shown, got: " .. tostring(again.challenge))
  assert(not again.challenge:find("  ", 1, true), "alert text must be whitespace-collapsed")
  assert(again.challenge:find("Einmalkennwort", 1, true), "OTP prompt must stay")
  assert(posts[2]:find("otpCode=111111", 1, true), "first code must be posted")

  local done = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2,
    { "222222" }, true)
  assert(done == nil, "correct OTP must log in, got: " .. tostring(done))
  assert(hasLog(logs, "login otp rejected by Amazon, asking again (submitted 1)"))
end

-- 7) Real wrong-password page: LoginFailed, alert text collapsed in the log.
do
  local env, logs = newLogin(startHtml, { loadFixture("amazon_signin_wrong_password_20261030.html") })
  local result = env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "falsch" }, true)
  assert(result == "LoginFailed", "real wrong password must be LoginFailed, got: " .. tostring(result))
  assert(hasLog(logs, "login error at stage Passwort-Schritt: Ein Problem ist aufgetreten: Falsches Passwort"),
    "collapsed alert text expected in the log")
end

-- 8) Alert text helper: whitespace collapsed, empty when no alert is shown.
do
  local env = mm.loadPlugin("amazon-bestellungen.lua", { loginCounter = 0, patcher = {} })
  assert(env.amazonAuthAlertText(mm.HTML(
    '<html><body><div id="auth-error-message-box">\n   Falsches   Passwort \n</div></body></html>'))
    == "Falsches Passwort")
  assert(env.amazonAuthAlertText(mm.HTML("<html><body><p>kein Alarm</p></body></html>")) == "")
end

-- 9) Status line follows the real login step (MoneyMoney's own "Lade Kontenliste"
-- text stays until the plugin sets a status, so the first status must come early).
do
  local env, _, _, statuses = newLogin(startHtml, {
    mfaPage(nil),
    mfaPage("Der Code ist nicht korrekt."),
    mm.HTML(loggedInHtml),
  })
  env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 1,
    { "user@example.com", "secret-pw" }, true)
  assert(statuses[1] == "Amazon: Anmeldung läuft…", "first status must start the login, got: " .. tostring(statuses[1]))
  assert(statuses[2] == "Amazon: Passwort wird geprüft…", "password step status expected, got: " .. tostring(statuses[2]))
  assert(statuses[#statuses] == "Amazon: Warte auf Eingabe des Zwei-Faktor-Codes…",
    "last status before the OTP prompt must say so, got: " .. tostring(statuses[#statuses]))

  env.InitializeSession2(env.ProtocolWebBanking, "Amazon", 2, { "111111" }, true)
  assert(statuses[#statuses - 1] == "Amazon: Zwei-Faktor-Code wird geprüft…",
    "code check status expected before the next prompt, got: " .. tostring(statuses[#statuses - 1]))
  assert(statuses[#statuses] == "Amazon: Warte auf Eingabe des Zwei-Faktor-Codes…")
end

print("test_login_otp_reprompt_and_stage OK")
