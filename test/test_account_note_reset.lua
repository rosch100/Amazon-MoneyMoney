-- An orderDetailsUrl account note must not stay active for the next account.
-- Run: test/run.sh test/test_account_note_reset.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local defaultPrefix = env.buildDetailsUrl("X"):sub(1, -2)
local customPrefix = "/custom-orders/order-details?orderID="

env.resetAccountNoteSettings()
env.applyAccountAttribute("orderDetailsUrl", customPrefix, true)
assert(env.buildDetailsUrl("123") == customPrefix.."123", "note must override the details URL")

env.resetAccountNoteSettings()
assert(env.buildDetailsUrl("123") == defaultPrefix.."123", "override must not survive the reset")

print("test_account_note_reset OK")
