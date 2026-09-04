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
