-- Login must report a host-visible failure when Amazon returns no HTML page.
-- Run: test/run.sh test/test_login_nil_page.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = {
  loginCounter = 0,
  patcher = {},
  cookies = "session=keep",
}
env.connectShop = function()
  return nil
end

local ok, result = pcall(
  env.InitializeSession2,
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret"},
  true)

assert(ok == true, "missing login page must not crash: " .. tostring(result))
assert(type(result) == "string" and result ~= "" and result ~= env.LoginFailed,
  "missing login page must be reported as a transient error")
assert(env.LocalStorage.cookies == "session=keep",
  "transient login failure must preserve session cookies")

local unexpectedEnv = mm.loadPlugin("amazon-bestellungen.lua")
unexpectedEnv.LocalStorage = {
  loginCounter = 0,
  patcher = {},
  cookies = "session=keep",
}
unexpectedEnv.connectShop = function()
  return mm.HTML("<html><body><div>temporarily unavailable</div></body></html>")
end
local unexpectedResult = unexpectedEnv.InitializeSession2(
  unexpectedEnv.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret"},
  true)
assert(type(unexpectedResult) == "string"
    and unexpectedResult ~= ""
    and unexpectedResult ~= unexpectedEnv.LoginFailed,
  "unexpected login layout must be reported as a transient error")
assert(unexpectedEnv.LocalStorage.cookies == "session=keep",
  "unexpected login layout must preserve session cookies")

local rawEnv = mm.loadPlugin("amazon-bestellungen.lua")
rawEnv.LocalStorage = {
  cookies = "session=keep",
}
rawEnv.Connection = function()
  return {
    getBaseURL = function()
      return "https://www.amazon.de"
    end,
    getCookies = function()
      return "session=changed"
    end,
    request = function()
      return nil
    end,
    setCookie = function() end,
  }
end
rawEnv.connectShopRaw("GET", "https://www.amazon.de/test")
assert(rawEnv.LocalStorage.cookies == "session=keep",
  "request without response must not overwrite persisted cookies")

local function loginPageWithError(message)
  local empty = {
    attr = function() return "" end,
    each = function() end,
    length = function() return 0 end,
    text = function() return "" end,
  }
  local errorNode = {
    text = function() return message end,
  }
  return {
    xpath = function(_, query)
      if query == '//div[@id="auth-error-message-box"]' then
        return errorNode
      end
      return empty
    end,
  }
end

local technicalErrorEnv = mm.loadPlugin("amazon-bestellungen.lua")
technicalErrorEnv.LocalStorage = {
  loginCounter = 0,
  patcher = {},
  cookies = "session=keep",
}
technicalErrorEnv.connectShop = function()
  return loginPageWithError("Amazon ist vorübergehend nicht verfügbar.")
end
local technicalError = technicalErrorEnv.InitializeSession2(
  technicalErrorEnv.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret"},
  true)
assert(type(technicalError) == "string"
    and technicalError ~= ""
    and technicalError ~= technicalErrorEnv.LoginFailed,
  "generic Amazon login error must remain transient")
assert(technicalErrorEnv.LocalStorage.cookies == "session=keep",
  "generic Amazon login error must preserve session cookies")

local credentialErrorEnv = mm.loadPlugin("amazon-bestellungen.lua")
credentialErrorEnv.LocalStorage = {
  loginCounter = 0,
  patcher = {},
  cookies = "session=invalid",
}
credentialErrorEnv.connectShop = function()
  return loginPageWithError("Your password is incorrect.")
end
local credentialError = credentialErrorEnv.InitializeSession2(
  credentialErrorEnv.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "wrong"},
  true)
assert(credentialError == credentialErrorEnv.LoginFailed,
  "explicit Amazon credential rejection must return LoginFailed")

print("test_login_nil_page OK")
