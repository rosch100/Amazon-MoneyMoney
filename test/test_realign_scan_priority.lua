-- Resume incomplete personal scan on Refresh sub:business must restart with business first.
-- Run: test/run.sh test/test_realign_scan_priority.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local plan = {
  { kind = "personal", label = "Persönliches Konto" },
  { kind = "business", label = "Altanis GmbH" },
}

env.LocalStorage = {
  loginCounter = 1,
  harvestPriorityKind = "business",
  OrderCache = {},
  subAccountScan = {
    phase = "running",
    incomplete = true,
    plan = plan,
    index = 1,
    totalNew = 255,
    loginCounter = 1,
  },
}

env.realignSubAccountScanForHarvestPriority("business")
assert(env.LocalStorage.subAccountScan == nil,
  "incomplete personal scan must be cleared when business is priority")

env.LocalStorage.subAccountScan = {
  phase = "running",
  incomplete = true,
  plan = {
    { kind = "business", label = "Altanis GmbH" },
    { kind = "personal", label = "Persönliches Konto" },
  },
  index = 1,
  totalNew = 12,
  loginCounter = 1,
}
env.realignSubAccountScanForHarvestPriority("business")
assert(env.LocalStorage.subAccountScan ~= nil,
  "running business scan must be kept when priority matches")

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
env.collectOrdersFromOrderList = function()
  return 0, nil
end
env.subAccountHarvestHasMore = function()
  return false
end

env.LocalStorage.subAccountScan = {
  phase = "running",
  incomplete = true,
  plan = plan,
  index = 1,
  totalNew = 255,
  loginCounter = 1,
}
env.continueSubAccountScan(nil)
assert(switchSequence[1] == "business",
  "after realign, first switch must be business, got " .. tostring(switchSequence[1]))

print("test_realign_scan_priority OK")
