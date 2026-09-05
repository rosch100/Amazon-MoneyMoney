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

local function mfaChallengePage()
  return mm.HTML([[
<html><body>
  <form id="auth-mfa-form">
    <p>Bestätigungscode eingeben</p>
    <input name="otpCode" type="text"/>
  </form>
</body></html>]])
end

local function authenticationChallengePage()
  return mm.HTML([[
<html><body>
  <form action="verify">
    <input name="code" type="text"/>
  </form>
</body></html>]])
end

local harvestCalls = 0
env.collectOrdersFromOrderList = function()
  harvestCalls = harvestCalls + 1
  error("discovery must not harvest orders")
end

-- Authentication challenge responses while opening the switcher are hard errors.
env.LocalStorage = {}
env.openAccountSwitcherEmbed = function()
  return authenticationChallengePage()
end
local authChallengeResult, authChallengeErr = env.discoverAmazonSubAccounts()
assert(authChallengeResult == nil)
assert(type(authChallengeErr) == "string"
  and authChallengeErr:find("authentication challenge", 1, true), tostring(authChallengeErr))

-- A missing switcher response must still surface MFA from the active HTML state.
env.LocalStorage = {}
env.bindActiveHtml(mfaChallengePage())
env.openAccountSwitcherEmbed = function()
  return nil
end
local challengeResult, challengeErr = env.discoverAmazonSubAccounts()
assert(challengeResult == nil)
assert(type(challengeErr) == "string" and challengeErr:find("2FA", 1, true), tostring(challengeErr))

-- A benign page without switcher forms means that no sub-accounts are available.
env.LocalStorage = {}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
env.openAccountSwitcherEmbed = function()
  return mm.HTML("<html><body><p>Kein Kontenwechsel verfügbar</p></body></html>")
end
local emptyOptions, emptyErr = env.discoverAmazonSubAccounts()
assert(emptyErr == nil, tostring(emptyErr))
assert(#emptyOptions == 0, "benign no-switcher page must return empty options")
assert(#env.LocalStorage.discoveredSubAccounts == 0)

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

-- A landing page without customerId is retried on the css order-history page.
installSwitcher()
env.LocalStorage = {}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
env.ensureAmazonSubAccountSession = function(kind)
  env.bindActiveHtml(accountPage(kind, nil))
  return nil
end
local probeRequests = {}
env.connectShop = function(method, url)
  probeRequests[#probeRequests + 1] = tostring(method) .. " " .. tostring(url)
  local kind = env.sessionMatchesSubAccountKind("business") and "business" or "personal"
  return accountPage(kind, kind == "personal" and "A3PERSONALID01" or "A3BUSINESSID02")
end

local probed, probeErr = env.discoverAmazonSubAccounts()
assert(probeErr == nil, tostring(probeErr))
assert(#probed == 2)
assert(#probeRequests == 2, "one probe per sub-account, no order harvest")
assert(probeRequests[1]:find("GET ", 1, true) == 1, probeRequests[1])
assert(probeRequests[1]:find("/gp/css/order-history", 1, true), probeRequests[1])
assert(not probeRequests[1]:find("timeFilter", 1, true), "probe must not request an order filter")
local probedByKind = {}
for _, option in ipairs(env.LocalStorage.discoveredSubAccounts) do
  probedByKind[option.kind] = option
end
assert(probedByKind.personal.accountNumber == "A3PERSONALID01")
assert(probedByKind.business.accountNumber == "A3BUSINESSID02")
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
-- Probe page unavailable: the business option stays incomplete.
env.connectShop = function()
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

-- Refresh harvest reuses stored customerIds and skips enrichment switches.
installSwitcher()
env.LocalStorage = {
  discoveredSubAccounts = {
    {
      kind = "personal",
      label = "Test User",
      customerName = "Test User",
      accountNumber = "A3PERSONALID01",
    },
    {
      kind = "business",
      label = "Example GmbH",
      businessName = "Example GmbH",
      accountNumber = "A3BUSINESSID02",
    },
  },
}
env.bindActiveHtml(accountPage("personal", "A3STARTPERSONAL"))
local openedSwitcher = false
env.openAccountSwitcherEmbed = function()
  openedSwitcher = true
  error("warm discovery cache must not open the account switcher")
end
local reuseSwitches = {}
env.ensureAmazonSubAccountSession = function(kind)
  reuseSwitches[#reuseSwitches + 1] = kind
  error("reuse path must not switch for customerId enrichment")
end
local reused, reuseErr = env.discoverAmazonSubAccounts(
  "Amazon: Bestellhistorie wird geladen…",
  {reuseCustomerIds = true})
assert(reuseErr == nil, tostring(reuseErr))
assert(#reused == 2)
assert(openedSwitcher == false, "must print (reused, no switcher) path")
assert(#reuseSwitches == 0, "stored customerIds must skip enrichment switches")
assert(reused[1].accountNumber == "A3PERSONALID01" or reused[2].accountNumber == "A3PERSONALID01")
assert(#env.LocalStorage.discoveredSubAccounts == 2)
assert(harvestCalls == 0)

print("test_discover_customer_ids OK")
