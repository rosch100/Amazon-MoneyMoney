-- Canonical account note keys and allowlist.
-- Run: test/run.sh test/test_account_attributes.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

assert(env.isSupportedAccountAttributeKey("blacklistOrders") == true)
assert(env.isSupportedAccountAttributeKey("blackListOrders") == true, "legacy alias")
assert(env.isSupportedAccountAttributeKey("keepStorno") == true)
assert(env.isSupportedAccountAttributeKey("nameMaxLength") == true)
assert(env.isSupportedAccountAttributeKey("stornoAnzeigen") == false)
assert(env.isSupportedAccountAttributeKey("resetCache") == true)
assert(env.isSupportedAccountAttributeKey("limitOrders") == true)
assert(env.isSupportedAccountAttributeKey("debug") == false)

local merged = env.mergeAccountAttributes(env.defaultAccountAttributes(), {
  blacklistOrders = "303-1111111-1111111",
  keepStorno = "true",
  stornoAnzeigen = "ignored",
  debug = "true",
})
assert(merged.blacklistOrders == "303-1111111-1111111")
assert(merged.blackListOrders == nil)
assert(merged.stornoAnzeigen == nil)
assert(merged.keepStorno == "true")
assert(merged.debug == nil, "internal flags must not merge from known accounts")

local mergedLegacy = env.mergeAccountAttributes(env.defaultAccountAttributes(), {
  blackListOrders = "303-legacy-1111111-1111111",
})
assert(mergedLegacy.blacklistOrders == "303-legacy-1111111-1111111")

env.applyAccountAttribute("blackListOrders", "303-2222222-2222222", true)
local blacklist = env.loadOrderBlacklistFromConfig()
assert(blacklist["303-2222222-2222222"] == true)

print("test_account_attributes OK")
