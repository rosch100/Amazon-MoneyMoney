-- Tests scanFiltersMonths window against Amazon timeFilter values.
-- Run: luajit test/test_scan_filters_months.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

-- Unlimited (nil/0): everything allowed
assert(env.orderFilterWithinScanMonths("last30", nil) == true)
assert(env.orderFilterWithinScanMonths("year-2015", 0) == true)
assert(env.orderFilterWithinScanMonths("year-2015", nil) == true)

-- 3 months: recent windows + current/overlapping years only
assert(env.orderFilterWithinScanMonths("last30", 3) == true)
assert(env.orderFilterWithinScanMonths("months-3", 3) == true)
assert(env.orderFilterWithinScanMonths("months-3", 1) == false,
  "months-3 is outside a 1-month incremental window (last30 covers it)")

local now = os.date("*t")
assert(env.orderFilterWithinScanMonths("year-" .. now.year, 3) == true)
assert(env.orderFilterWithinScanMonths("year-1999", 3) == false)
assert(env.orderFilterWithinScanMonths("year-1999", 12) == false)

-- 14 months from Aug 2026 reaches into previous year
-- Use a fixed "now" via optional asOf for deterministic tests
local asOf = {year=2026, month=8, day=25}
assert(env.orderFilterWithinScanMonths("year-2026", 14, asOf) == true)
assert(env.orderFilterWithinScanMonths("year-2025", 14, asOf) == true)
assert(env.orderFilterWithinScanMonths("year-2024", 14, asOf) == false)
assert(env.orderFilterWithinScanMonths("year-2025", 6, asOf) == false)
assert(env.orderFilterWithinScanMonths("year-2026", 6, asOf) == true)

-- months-N fits when window <= scanFiltersMonths
assert(env.orderFilterWithinScanMonths("months-6", 6, asOf) == true)
assert(env.orderFilterWithinScanMonths("months-6", 3, asOf) == false)
assert(env.orderFilterWithinScanMonths("months-12", 12, asOf) == true)
assert(env.orderFilterWithinScanMonths("months-12", 6, asOf) == false)

assert(env.orderFilterWithinScanMonths("unknown", 3) == false)

print("test_scan_filters_months OK")
