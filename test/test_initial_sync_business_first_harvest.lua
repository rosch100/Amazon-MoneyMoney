-- Erstimport: Refresh sub:business must harvest business sub-account before personal.
-- Run: test/run.sh test/test_initial_sync_business_first_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"

local plan = {
  { kind = "personal", label = "Persönliches Konto", customerName = "Persönliches Konto",
    accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Altanis GmbH", businessName = "Altanis GmbH",
    accountNumber = "A3BUSINESSID02" },
}
local reordered = env.reorderSubAccountPlanByPriority(plan, "business")
assert(reordered[1].kind == "business")
assert(reordered[2].kind == "personal")

env.LocalStorage = { loginCounter = 1, OrderCache = {} }
env.rememberDiscoveredSubAccounts(plan)

local switchSequence = {}
env.openAccountSwitcherEmbed = function()
  return mm.HTML("<html><body></body></html>")
end
env.parseAccountSwitcher = function()
  return plan
end
env.switchAmazonSubAccount = function(opt)
  switchSequence[#switchSequence + 1] = opt.kind
  return { ok = true }
end
env.collectOrdersFromOrderList = function(label, kind)
  return 0, nil
end
env.subAccountHarvestHasMore = function()
  return false
end

env.LocalStorage.harvestPriorityKind = "business"
env.beginSubAccountScanPlan(plan, "business")
assert(env.LocalStorage.subAccountScan.plan[1].kind == "business")
env.runSubAccountScanLoop()
assert(switchSequence[1] == "business", "first switch must be business, got " .. tostring(switchSequence[1]))

print("test_initial_sync_business_first_harvest OK")
