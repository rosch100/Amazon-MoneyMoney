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

local harvestedKinds = {}
-- No live pages offline: the customerId probe finds nothing beyond the active HTML.
env.connectShop = function()
  return nil
end
env.openAccountSwitcherEmbed = function()
  return mm.HTML("<html><body></body></html>")
end
env.parseAccountSwitcher = function()
  return plan
end
env.switchAmazonSubAccount = function(opt)
  local marker = opt.kind == "business"
      and '<span class="abnav-accountfor">Altanis GmbH</span>'
    or '<span class="nav-shortened-name">Personal</span>'
  env.bindActiveHtml(mm.HTML("<html><body>" .. marker .. "</body></html>"))
  return { ok = true }
end
env.collectOrdersFromOrderList = function(_, kind)
  harvestedKinds[#harvestedKinds + 1] = kind
  return 0, nil
end
env.subAccountHarvestHasMore = function()
  return false
end
env.bindActiveHtml(mm.HTML(
  '<html><body><span class="nav-shortened-name">Personal</span></body></html>'))

env.LocalStorage.subAccountScan = {
  phase = "running",
  incomplete = true,
  plan = plan,
  index = 1,
  totalNew = 255,
  loginCounter = 1,
}
env.continueSubAccountScan(nil)
assert(harvestedKinds[1] == "business",
  "after realign, first harvest must be business, got " .. tostring(harvestedKinds[1]))

print("test_realign_scan_priority OK")
