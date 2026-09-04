-- Schema migration must be executable while the plugin is loading.
-- Run: test/run.sh test/test_schema_upgrade_load.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local storage = {
  cacheVersion = 20,
  OrderCache = { ["legacy-order"] = { orderCode = "legacy-order" } },
}
local env = mm.loadPlugin("amazon-orders.lua", storage)

assert(storage.cacheVersion == 23, "schema version must be upgraded during plugin load")
assert(storage.requireFullReimport == true, "schema migration must require full reimport")
assert(next(storage.OrderCache) == nil, "schema migration must clear the legacy order cache")

print("test_schema_upgrade_load OK")
