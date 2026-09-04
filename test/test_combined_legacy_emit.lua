-- Combined email accounts must honor legacy mix emit markers.
-- Run: test/run.sh test/test_combined_legacy_emit.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"

local order = {
  emittedAccounts = { mix = true },
}

assert(env.isOrderEmittedForAccount(order, "test@example.com") == true,
  "combined email account must honor legacy mix marker")
assert(env.isOrderEmittedForAccount(order, "unknown@example.com") == false,
  "unknown account must not honor legacy mix marker")

-- Case and padding differences still address the combined account.
assert(env.isCombinedMoneyMoneyAccount("  Test@Example.com ") == true)
assert(env.isOrderEmittedForAccount(order, " TEST@Example.com ") == true,
  "email spelling must not hide the legacy mix marker")

-- Every email spelling shares one emit key, so nothing is emitted twice.
assert(env.emitAccountKey(" Test@Example.COM ") == "test@example.com")
assert(env.emitAccountKey(nil) == "test@example.com")

local marked = {}
env.markOrderEmittedForAccount(marked, "Test@Example.com")
assert(marked.emittedAccounts["test@example.com"] == true)
assert(env.isOrderEmittedForAccount(marked, nil) == true)
assert(env.isOrderEmittedForAccount(marked, "test@example.com") == true)
assert(env.isOrderEmittedForAccount(marked, "A3PERSONALID01") == false)
