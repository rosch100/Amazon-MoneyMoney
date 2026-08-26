-- Details rescan: recent orders sooner; harvest reappear still does not reset detailsDate.
-- Run: test/run.sh test/test_details_rescan.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local now = os.time()
local day = 24 * 60 * 60

local function delay(age)
  return env.detailsRescanDelaySec(age)
end

local minRecent, jitRecent = delay(day)
assert(minRecent == 7 * day and jitRecent == 7 * day)
local minMid, jitMid = delay(200 * day)
assert(minMid == 21 * day and jitMid == 21 * day)
local minOld, jitOld = delay(400 * day)
assert(minOld == 90 * day and jitOld == 90 * day)
local minNeg, jitNeg = delay(-10)
assert(minNeg == 7 * day and jitNeg == 7 * day)

local recent = { bookingDate = now - day }
env.scheduleNextDetailsDate(recent, now)
assert(recent.detailsDate >= now + minRecent)
assert(recent.detailsDate < now + minRecent + jitRecent)
assert(env.orderNeedsDetailsForAccount(recent, now, "mix") == false,
  "just-scheduled detailsDate must not fetch again this refresh")

local nodate = {}
env.scheduleNextDetailsDate(nodate, now)
assert(nodate.detailsDate >= now + 7 * day)
assert(nodate.detailsDate < now + 14 * day)

print("test_details_rescan OK")
