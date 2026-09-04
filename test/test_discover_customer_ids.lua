-- Discovery reads customerIds by switching sub-accounts and restores the starting session.
-- Run: test/run.sh test/test_discover_customer_ids.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.secUsername = "user@example.com"

local fixtureFile = assert(io.open("test/fixtures/cvf_account_switcher.html", "rb"))
local switcherFixture = fixtureFile:read("*all")
fixtureFile:close()

local function accountPage(kind, customerId)
  local marker = kind == "business"
      and '<span class="abnav-accountfor">Example GmbH</span>'
    or '<span class="nav-shortened-name">Test User</span>'
  local customerIdScript = customerId
      and '<script>var iss={customerId:"' .. customerId .. '"};</script>'
    or ""
  return mm.HTML("<html><body>" .. marker .. customerIdScript .. "</body></html>")
end

local function installSwitcher()
  env.openAccountSwitcherEmbed = function()
    return mm.HTML(switcherFixture)
  end
end

local harvestCalls = 0
env.collectOrdersFromOrderList = function()
  harvestCalls = harvestCalls + 1
  error("discovery must not harvest orders")
end

-- Happy path: enrich both options and restore the personal starting session.
installSwitcher()
env.LocalStorage = {}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
local switches = {}
env.ensureAmazonSubAccountSession = function(kind)
  switches[#switches + 1] = kind
  local customerId = kind == "personal" and "A3PERSONALID01" or "A3BUSINESSID02"
  env.bindActiveHtml(accountPage(kind, customerId))
  return nil
end

local discovered, discoverErr = env.discoverAmazonSubAccounts()
assert(discoverErr == nil, tostring(discoverErr))
assert(#discovered == 2, "expected two discovered options")
assert(#env.LocalStorage.discoveredSubAccounts == 2, "both complete options must be remembered")
local byKind = {}
for _, option in ipairs(env.LocalStorage.discoveredSubAccounts) do
  byKind[option.kind] = option
end
assert(byKind.personal.accountNumber == "A3PERSONALID01")
assert(byKind.business.accountNumber == "A3BUSINESSID02")
assert(switches[#switches] == "personal", "discovery must restore the personal starting session")
assert(env.sessionMatchesSubAccountKind("personal") == true)
assert(harvestCalls == 0)

-- Partial IDs are remembered only as complete entries; ListAccounts offers combined only.
installSwitcher()
env.LocalStorage = {}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
env.ensureAmazonSubAccountSession = function(kind)
  local customerId = kind == "personal" and "A3PERSONALID01" or nil
  env.bindActiveHtml(accountPage(kind, customerId))
  return nil
end

local partial, partialErr = env.discoverAmazonSubAccounts()
assert(partialErr == nil, tostring(partialErr))
assert(#partial == 2, "raw discovery options remain available")
assert(#env.LocalStorage.discoveredSubAccounts == 1, "incomplete option must not be remembered")
local partialAccounts = env.ListAccounts({})
assert(#partialAccounts == 1)
assert(partialAccounts[1].accountNumber == "user@example.com")

-- Authentication failure is transactional and does not expose half-applied discovery.
installSwitcher()
env.LocalStorage = {
  discoveredSubAccounts = {
    {
      kind = "personal",
      label = "Previous",
      customerName = "Previous",
      accountNumber = "A3PREVIOUSID01",
    },
  },
}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
env.ensureAmazonSubAccountSession = function(kind)
  if kind == "business" then
    return "2FA beim Kontenwechsel erforderlich – bitte abmelden und erneut anmelden"
  end
  env.bindActiveHtml(accountPage("personal", "A3PERSONALID01"))
  return nil
end

local authResult, authErr = env.discoverAmazonSubAccounts()
assert(authResult == nil)
assert(type(authErr) == "string" and authErr:find("2FA", 1, true), tostring(authErr))
assert(#env.LocalStorage.discoveredSubAccounts == 1)
assert(env.LocalStorage.discoveredSubAccounts[1].accountNumber == "A3PREVIOUSID01",
  "failed discovery must preserve the previous complete snapshot")

-- A failed restore is a hard discovery error and must not commit new IDs.
installSwitcher()
env.LocalStorage = {}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
local personalSwitches = 0
env.ensureAmazonSubAccountSession = function(kind)
  if kind == "personal" then
    personalSwitches = personalSwitches + 1
    if personalSwitches > 1 then
      return "restore blocked"
    end
    env.bindActiveHtml(accountPage("personal", "A3PERSONALID01"))
    return nil
  end
  env.bindActiveHtml(accountPage("business", "A3BUSINESSID02"))
  return nil
end

local restoreResult, restoreErr = env.discoverAmazonSubAccounts()
assert(restoreResult == nil)
assert(type(restoreErr) == "string" and restoreErr:find("Ausgangskonto", 1, true), tostring(restoreErr))
assert(env.LocalStorage.discoveredSubAccounts == nil or #env.LocalStorage.discoveredSubAccounts == 0,
  "restore failure must not commit the newly discovered snapshot")
assert(harvestCalls == 0)

print("test_discover_customer_ids OK")
