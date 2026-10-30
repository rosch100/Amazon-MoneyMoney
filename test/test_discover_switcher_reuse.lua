-- Discovery reuses the switcher page it already loaded for its only switch.
-- The active sub-account is read without a switch and the session is not switched back.
-- Run: test/run.sh test/test_discover_switcher_reuse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "user@example.com"

local fixtureFile = assert(io.open("test/fixtures/cvf_account_switcher.html", "rb"))
local switcherFixture = fixtureFile:read("*all")
fixtureFile:close()

local currentKind = "personal"
local switcherOpenings = 0
local switchTargets = {}

env.LocalStorage = {}
env.openAccountSwitcherEmbed = function()
  switcherOpenings = switcherOpenings + 1
  return mm.HTML(switcherFixture)
end
env.switchAuthBlockReason = function() return nil end
env.activeAmazonSubAccountKind = function() return currentKind end
env.sessionMatchesSubAccountKind = function(kind) return currentKind == kind end
env.switchAmazonSubAccount = function(option)
  table.insert(switchTargets, option.kind)
  currentKind = option.kind
  return { ok = true }
end
env.readAmazonCustomerIdForSession = function()
  return "AO.TEST" .. string.upper(currentKind)
end

local options, err = env.discoverAmazonSubAccounts("x")
assert(err == nil, "discovery failed: " .. tostring(err))
assert(#options == 2, "fixture must offer two sub-accounts, got " .. #options)

-- Starting kind is personal: personal is read without a switch, business needs one switch, no switch back.
assert(#switchTargets == 1, "expected 1 switch, got " .. #switchTargets)
assert(switchTargets[1] == "business", "the only switch must target business")

-- The switcher is opened once for discovery; the switch reuses that page.
assert(switcherOpenings == 1, "expected 1 switcher opening, got " .. switcherOpenings)
assert(currentKind == "business", "session stays on the last sub-account read")

print("test_discover_switcher_reuse: OK")
