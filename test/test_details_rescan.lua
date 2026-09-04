-- Details rescan: recent orders sooner; harvest reappear still does not reset detailsDate.
-- Run: test/run.sh test/test_details_rescan.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "test@example.com"

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
assert(env.orderNeedsDetailsForAccount(recent, now, "test@example.com") == false,
  "just-scheduled detailsDate must not fetch again this refresh")

local nodate = {}
env.scheduleNextDetailsDate(nodate, now)
assert(nodate.detailsDate >= now + 7 * day)
assert(nodate.detailsDate < now + 14 * day)

-- Empty details HTML must stay due so the next refresh retries (not 7–90 days later).
env.connectShopWithCheck = function()
  return mm.HTML("<html><body></body></html>")
end
local emptyPage = {
  orderCode = "303-empty-details",
  detailsDate = 0,
  bookingDate = now - day,
}
---@diagnostic disable-next-line: redundant-parameter -- Sandbox function is dynamically replaced below.
env.getOrderDetails(emptyPage)
assert(emptyPage.detailsDate == 0, "empty details page must not schedule a rescan delay")
assert(emptyPage.detailsParsed ~= true, "empty details page must not count as parsed")

env.connectShop = function()
  return mm.HTML("<html><body></body></html>")
end
env.orderBlacklist = {}
env.getOrderDetails = function()
  return false
end
local fetchState = env.fetchOrderDetailsBatch(
  {{ orderCode = "303-failed-details", order = {}}},
  now,
  250,
  { counter = 0, pendingAtStart = 1, failed = 0 })
assert(fetchState.counter == 1 and fetchState.failed == 1,
  "failed detail fetch must be counted in caller-owned state")

local sessionSwitches = 0
env.LocalStorage = { OrderCache = {} }
env.rememberDiscoveredSubAccounts({
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
})
env.ensureAmazonSubAccountSession = function()
  sessionSwitches = sessionSwitches + 1
  return nil
end
env.fetchPendingOrderDetails("AO.3BUSINESSID02", now)
assert(sessionSwitches == 0,
  "empty details queue must not switch Amazon sub-account sessions")

print("test_details_rescan OK")
