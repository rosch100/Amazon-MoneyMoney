-- Combined email emit keys: one key per login, no mix markers.
-- Run: test/run.sh test/test_emit_account_key.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

assert(env.emitAccountKey(" Test@Example.COM ") == "test@example.com")
assert(env.emitAccountKey(nil) == "test@example.com")

local marked = {}
env.markOrderEmittedForAccount(marked, "Test@Example.com")
assert(marked.emittedAccounts["test@example.com"] == true)
assert(marked.emittedAccounts.mix == nil)
assert(env.isOrderEmittedForAccount(marked, nil) == true)
assert(env.isOrderEmittedForAccount(marked, "test@example.com") == true)
assert(env.isOrderEmittedForAccount(marked, "AO.3PERSONALID01") == false)

-- Historic mix markers are ignored.
local legacyMix = { emittedAccounts = { mix = true } }
assert(env.isOrderEmittedForAccount(legacyMix, "test@example.com") == false)

local noUser = mm.loadPlugin("amazon-bestellungen.lua")
local ok = pcall(noUser.emitAccountKey, nil)
assert(ok == false, "emitAccountKey without login must error")

print("test_emit_account_key OK")
