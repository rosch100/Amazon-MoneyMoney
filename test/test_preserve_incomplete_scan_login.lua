-- Incomplete sub-account scan helpers: preserve on login, sync loginCounter.
-- Run: test/run.sh test/test_preserve_incomplete_scan_login.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

env.LocalStorage = {
  loginCounter = 3,
  subAccountScan = {
    phase = "running",
    incomplete = true,
    plan = { { kind = "business", label = "Altanis GmbH" } },
    index = 1,
    totalNew = 10,
    loginCounter = 3,
  },
}

assert(env.shouldPreserveSubAccountScanOnLogin() == true)

env.LocalStorage.loginCounter = 4
env.syncSubAccountScanLoginCounter()
assert(env.LocalStorage.subAccountScan.loginCounter == 4, "scan loginCounter must sync")

env.LocalStorage.subAccountScan = { phase = "done", incomplete = false, loginCounter = 4 }
assert(env.shouldPreserveSubAccountScanOnLogin() == false)

env.LocalStorage.subAccountScan = { phase = "running", incomplete = false, loginCounter = 4 }
assert(env.shouldPreserveSubAccountScanOnLogin() == false)

env.LocalStorage.subAccountScan = { phase = "await_mfa", incomplete = false, loginCounter = 4 }
assert(env.shouldPreserveSubAccountScanOnLogin() == true)

print("test_preserve_incomplete_scan_login OK")
