-- Mix (Alle Konten): one harvest batch per sub-account per refresh, then pause.
-- Run: test/run.sh test/test_mix_scan_round_robin.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local harvestedKinds = {}
env.collectOrdersFromOrderList = function(label, kind)
  harvestedKinds[#harvestedKinds + 1] = kind
  return 1, nil
end
env.subAccountHarvestHasMore = function(_label, kind)
  return kind == "personal"
end
env.openAccountSwitcherEmbed = function()
  return mm.HTML('<html><body><a data-testid="switch-account-link">x</a></body></html>')
end
env.parseAccountSwitcher = function()
  return {
    { kind = "personal", label = "Persönliches Konto" },
    { kind = "business", label = "Altanis GmbH" },
  }
end
env.switchAmazonSubAccount = function(_opt)
  return { needsMfa = false, error = nil }
end

env.LocalStorage = {
  loginCounter = 1,
  refreshSince = 0,
  OrderCache = {},
}

env.beginSubAccountScanPlan({
  { kind = "personal", label = "Persönliches Konto" },
  { kind = "business", label = "Altanis GmbH" },
}, nil)

env.runSubAccountScanLoop()
local state = env.LocalStorage.subAccountScan
assert(harvestedKinds[1] == "personal", "mix must harvest personal first, got " .. tostring(harvestedKinds[1]))
assert(harvestedKinds[2] == "business",
  "mix must harvest business in the same refresh after a personal batch pause, got " .. tostring(harvestedKinds[2]))
assert(#harvestedKinds == 2, "one batch per sub-account, got " .. #harvestedKinds)
assert(state.incomplete == true, "personal still has more filters")
assert(state.phase == "running", "scan stays running")
assert(state.index == 1, "next refresh must resume personal, got " .. tostring(state.index))
assert(state.plan[2].done == true, "business batch without remaining filters is done")

print("test_mix_scan_round_robin OK")
