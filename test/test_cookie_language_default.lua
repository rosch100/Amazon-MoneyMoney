-- Sprachcookie lc-acbde: ohne Notiz cookieLanguage gilt Deutsch (de_DE); die Notiz im
-- BCP-Format (de-DE) wird für das Cookie in Unterstrich-Form (en_GB) umgesetzt.
-- Run: test/run.sh test/test_cookie_language_default.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

local function assertEquals(expected, actual, msg)
  assert(expected == actual, msg .. ": erwartet " .. tostring(expected) .. ", erhalten " .. tostring(actual))
end

env.LocalStorage = { loginCounter = 0, patcher = {} }
assertEquals("de_DE", env.amazonLanguageCookieValue(), "ohne Notiz")

env.LocalStorage.patcher = { cookieLanguage = "" }
assertEquals("de_DE", env.amazonLanguageCookieValue(), "leere Notiz")

env.LocalStorage.patcher = { cookieLanguage = "en-GB" }
assertEquals("en_GB", env.amazonLanguageCookieValue(), "Notiz en-GB")

env.LocalStorage.patcher = { cookieLanguage = "fr-FR" }
assertEquals("fr_FR", env.amazonLanguageCookieValue(), "Notiz fr-FR")

print("test_cookie_language_default: OK")
