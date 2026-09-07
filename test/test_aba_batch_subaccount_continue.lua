-- Business ABA batch must not block harvesting other sub-accounts in the same refresh.
-- Run: test/run.sh test/test_aba_batch_subaccount_continue.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end

env.LocalStorage = {
  loginCounter = 1,
  refreshSince = 0,
  OrderCache = {},
  abaFullHarvestHasMore = true,
}

local harvested = {}

env.openAccountSwitcherEmbed = function()
  return mm.HTML('<html><body><a data-testid="switch-account-link">x</a></body></html>')
end
env.parseAccountSwitcher = function()
  return {
    { kind = "business", label = "Altanis GmbH" },
    { kind = "personal", label = "Persönliches Konto" },
  }
end
env.switchAmazonSubAccount = function(opt)
  return { needsMfa = false, error = nil }
end
env.collectOrdersFromOrderList = function(label, kind)
  harvested[#harvested + 1] = kind
  return 1, nil
end
env.subAccountHarvestHasMore = function(label, kind)
  return env.hasMoreBusinessOrdersToHarvest(label, kind, 0, os.time())
end

env.beginSubAccountScanPlan({
  { kind = "business", label = "Altanis GmbH" },
  { kind = "personal", label = "Persönliches Konto" },
})

local err = env.runSubAccountScanLoop()
assert(err == nil, "scan loop must succeed, got " .. tostring(err))

local state = env.LocalStorage.subAccountScan
assert(state.phase == "done", "scan must finish in one run, got phase " .. tostring(state.phase))
assert(state.incomplete ~= true, "ABA batch alone must not mark sub-account scan incomplete")
assert(#harvested == 2, "business and personal must both harvest, got " .. table.concat(harvested, ","))
assert(harvested[1] == "business" and harvested[2] == "personal", "unexpected harvest order")

env.LocalStorage.refreshSince = 0
env.LocalStorage.subAccountScan.harvestSince = 0
env.LocalStorage.subAccountScan.loginCounter = 1
assert(env.resolveSubAccountScanCache() == nil,
  "completed scan must not skip harvest while ABA batch has more")

print("test_aba_batch_subaccount_continue OK")
