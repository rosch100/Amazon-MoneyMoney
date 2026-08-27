-- Erstimport: harvest pauses per batch; sub-account index stays until filters are done.
-- Run: test/run.sh test/test_initial_sync_batch_harvest.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
local now = os.time()

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end

env.LocalStorage = {
  loginCounter = 1,
  lastLoginCounter = 0,
  refreshSince = 0,
  OrderCache = {},
  orderFilterCacheByAccount = {
    [""] = { ["year-2025"] = true },
  },
}

env.enumerateYourOrdersGetFilters = function()
  return {
    { val = "year-2026", label = "2026" },
    { val = "year-2025", label = "2025" },
    { val = "year-2024", label = "2024" },
  }
end

env.collectOrdersFromOrderList = function()
  return 3, nil
end

env.openAccountSwitcherEmbed = function()
  return mm.HTML('<html><body><a data-testid="switch-account-link">x</a></body></html>')
end
env.parseAccountSwitcher = function()
  return { { kind = "personal", label = "Persönliches Konto" } }
end
env.switchAmazonSubAccount = function(opt)
  return { needsMfa = false, error = nil }
end

env.beginSubAccountScanPlan({
  { kind = "personal", label = "Persönliches Konto" },
})

local state = env.LocalStorage.subAccountScan
assert(state.phase == "running", "scan must start running")

env.runSubAccountScanLoop()
state = env.LocalStorage.subAccountScan
assert(state.index == 1, "index must stay on personal while filters remain, got " .. tostring(state.index))
assert(state.incomplete == true, "batch pause must mark scan incomplete")
assert(state.phase == "running", "scan must stay running after batch pause")

print("test_initial_sync_batch_harvest OK")
