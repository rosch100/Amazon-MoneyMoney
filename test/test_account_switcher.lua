-- Parses Amazon CVF account switcher (personal + business).
-- Run: luajit test/test_account_switcher.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")

local f = assert(io.open("test/fixtures/cvf_account_switcher.html", "rb"))
local fixture = f:read("*all")
f:close()

local accounts = env.parseAccountSwitcher(mm.HTML(fixture))
assert(#accounts == 2, "expected 2 switchable accounts, got " .. tostring(#accounts))

local byKind = {}
for _, a in ipairs(accounts) do
  byKind[a.kind] = a
end

assert(byKind.personal ~= nil, "personal account missing")
assert(byKind.business ~= nil, "business account missing")
assert(byKind.personal.label == "Personal account", "personal label: " .. tostring(byKind.personal.label))
assert(byKind.business.label == "Example GmbH", "business label prefers businessName: " .. tostring(byKind.business.label))
assert(byKind.personal.token == "DUMMY_SWITCH_TOKEN_PERSONAL")
assert(byKind.business.token == "DUMMY_SWITCH_TOKEN_BUSINESS")
assert(byKind.personal.csrf == "DUMMY_CSRF_PERSONAL")
assert(byKind.business.csrf == "DUMMY_CSRF_BUSINESS")
assert(string.find(byKind.personal.action, "switchaccount", 1, true))
assert(string.find(byKind.business.action, "switchaccount", 1, true))

assert(env.absoluteAmazonUrl("/ap/switchaccount") == "https://www.amazon.de/ap/switchaccount")
assert(env.absoluteAmazonUrl("https://www.amazon.de/x") == "https://www.amazon.de/x")
assert(env.cvfVersionQueryFromText("/ap/cvf/request.embed?arb=X&CVFVersion=1.2.3&AUIVersion=4.5.6")
  == "CVFVersion=1.2.3&AUIVersion=4.5.6")
assert(env.cvfVersionQueryFromText("no versions here") == "")
assert(env.orderHasPositions({ orderPositions = { { purpose = "x" } } }) == true)
assert(env.orderHasPositions({ orderPositions = {} }) == false)
assert(env.orderHasPositions({}) == false)

assert(env.accountSwitcherEmbedUrl("ARBTOKEN") == "/ap/cvf/request.embed?arb=ARBTOKEN")
assert(env.accountSwitcherEmbedUrl("ARBTOKEN", "CVFVersion=1&AUIVersion=2")
  == "/ap/cvf/request.embed?arb=ARBTOKEN&CVFVersion=1&AUIVersion=2")
assert(env.accountSwitcherEmbedUrl("") == nil)
assert(env.accountSwitcherEmbedUrl(nil) == nil)

local embedPage = mm.HTML([[
<html><body>
  <iframe src="/ap/cvf/request.embed?arb=OTHER&CVFVersion=0.1.0.0-2026-01-01&AUIVersion=3.26.6-2026-01-01"></iframe>
  <div data-arbtoken="ARBFROMDIV"></div>
</body></html>]])
assert(env.cvfEmbedVersionQuery(embedPage)
  == "CVFVersion=0.1.0.0-2026-01-01&AUIVersion=3.26.6-2026-01-01")
assert(env.cvfEmbedVersionQuery(nil) == "")
assert(env.accountSwitcherEmbedUrl("ARBFROMDIV", env.cvfEmbedVersionQuery(embedPage))
  == "/ap/cvf/request.embed?arb=ARBFROMDIV&CVFVersion=0.1.0.0-2026-01-01&AUIVersion=3.26.6-2026-01-01")

-- Nav flyout is JS-embedded (accountListContent.html); XPath must not be required.
local switchHref = "https://www.amazon.de/ap/signin?openid.return_to=https%3A%2F%2Fwww.amazon.de%2F%3Fref_%3Dnav_youraccount_switchacct&switch_account=picker&ignoreAuthState=1"
local jsNavPage = mm.HTML([[
<html><body>
<script type="text/javascript">
  window.$Nav && $Nav.when("data").run(function (data) {
    data({ "accountListContent": { "html": "<div id='nav-al-your-account'><a id='nav-item-switch-account' href=']] .. switchHref .. [['>Konto wechseln</a></div>" } });
  });
</script>
<p>no live switcher anchor in the DOM</p>
</body></html>]])
assert(jsNavPage:xpath('//a[@id="nav-item-switch-account"]'):attr('href') == "",
  "fixture must keep switcher link out of the DOM")
assert(env.findAccountSwitcherHref(jsNavPage) == switchHref,
  "must recover switcher href from JS-embedded nav HTML")
assert(env.findAccountSwitcherHref(nil) == "")

local domPage = mm.HTML([[
<html><body>
  <a id="nav-item-switch-account" href="/ap/signin?switch_account=picker&amp;x=1">Konto wechseln</a>
</body></html>]])
assert(env.findAccountSwitcherHref(domPage):find("switch_account=picker", 1, true),
  "DOM switcher link must still be found via XPath")

local picker = env.defaultAccountSwitcherSigninUrl()
assert(picker:find("switch_account=picker", 1, true), "default picker needs switch_account=picker")
assert(picker:find("nav_youraccount_switchacct", 1, true), "default picker needs switchacct return_to")
assert(picker:find("ignoreAuthState=1", 1, true))

assert(env.decodeSwitchAccountRedirect('{"redirectUrl":"https://www.amazon.de/"}')
  == "https://www.amazon.de/")
assert(env.decodeSwitchAccountRedirect("<html>not json</html>") == nil)
assert(env.decodeSwitchAccountRedirect('{"ok":true}') == nil)
assert(env.decodeSwitchAccountRedirect("") == nil)

local order = {
  accountNumber = "Altanis GmbH",
  mandateReference = "MasterCard **** 2022",
  shippingAddress = "Roland Musterweg 1",
}
local tx = env.makeAccountTransaction(order, "303-1234567-1234567", "USB-Kabel", -9.99, 1700000000)
assert(tx.accountNumber == "Altanis GmbH", "Unterkonto must be accountNumber")
assert(tx.batchReference == "Roland Musterweg 1", "Lieferadresse in batchReference")
assert(tx.bookingText == "Roland Musterweg 1", "Lieferadresse in bookingText (Umsatzart)")
assert(tx.endToEndReference == "303-1234567-1234567", "Referenz must be Bestellnummer")
assert(tx.name == "USB-Kabel")
assert(tx.purpose == "USB-Kabel")

local cache = {}
local page = mm.HTML([[
<html><body>
<div class="order-card js-order-card"
     data-csa-c-slot-id="amzn1.yourorders.order-card.302-1111111-1111111"></div>
</body></html>]])
local _, _, n = env.mergeOrdersFromPage(page, cache, "Persönliches Konto", "personal")
assert(n == 1)
assert(cache["302-1111111-1111111"].accountNumber == "Persönliches Konto")
assert(cache["302-1111111-1111111"].subAccountKind == "personal")

-- Switch failure must surface (no silent fallback to current session)
env.LocalStorage = { loginCounter = 1, OrderCache = {}, getOrders = {} }
env.openAccountSwitcherEmbed = function()
  return mm.HTML(fixture)
end
env.switchAmazonSubAccount = function()
  return { error = "boom" }
end
env.collectOrdersFromOrderList = function()
  error("must not fall back to current session")
end
local count, err = env.scanAllAmazonSubAccounts()
assert(count == nil and type(err) == "string" and err:find("fehlgeschlagen", 1, true),
  "failed switch must return error, got " .. tostring(err))

-- Successful switches scrape each sub-account with kind
local calls = {}
env.LocalStorage = { loginCounter = 2, OrderCache = {}, getOrders = {} }
env.switchAmazonSubAccount = function()
  return { ok = true }
end
env.collectOrdersFromOrderList = function(label, kind)
  table.insert(calls, { label = label, kind = kind })
  return 1
end
local nOk, errOk = env.scanAllAmazonSubAccounts()
assert(errOk == nil, tostring(errOk))
assert(nOk == 2, "both sub-accounts scraped, got " .. tostring(nOk))
assert(#calls == 2)
assert(calls[1].kind == "personal" or calls[2].kind == "personal")
assert(calls[1].kind == "business" or calls[2].kind == "business")
assert(#env.LocalStorage.discoveredSubAccounts == 2)
assert(env.LocalStorage.subAccountScan.incomplete ~= true)

-- discoverAmazonSubAccounts: switcher only, never harvests orders
local discoverCalls = 0
env.LocalStorage = { loginCounter = 10, OrderCache = {}, getOrders = {} }
env.openAccountSwitcherEmbed = function()
  return mm.HTML(fixture)
end
env.collectOrdersFromOrderList = function()
  discoverCalls = discoverCalls + 1
  error("discover must not harvest orders")
end
env.switchAmazonSubAccount = function()
  error("discover must not switch accounts")
end
local opts = env.discoverAmazonSubAccounts()
assert(#opts == 2)
assert(#env.LocalStorage.discoveredSubAccounts == 2)
assert(discoverCalls == 0)

-- Switcher unavailable at start: no options → scrape current session only
local softCalls = {}
env.LocalStorage = { loginCounter = 3, OrderCache = {}, getOrders = {} }
env.openAccountSwitcherEmbed = function()
  return nil
end
env.collectOrdersFromOrderList = function(label, kind)
  table.insert(softCalls, { label = label, kind = kind })
  return 1
end
local nSoft, errSoft = env.scanAllAmazonSubAccounts()
assert(errSoft == nil, tostring(errSoft))
assert(nSoft == 1)
assert(#softCalls == 1)
assert(softCalls[1].label == "")

-- Mid-plan: discovery already planned, then embed nil → hard error (no wrong-account scrape)
env.LocalStorage = {
  loginCounter = 4,
  OrderCache = {},
  getOrders = {},
  subAccountScan = {
    phase = "running",
    plan = {
      { kind = "personal", label = "Personal" },
      { kind = "business", label = "Biz" },
    },
    index = 1,
    totalNew = 0,
    incomplete = false,
    loginCounter = 4,
  },
}
softCalls = {}
env.collectOrdersFromOrderList = function(label, kind)
  table.insert(softCalls, { label = label, kind = kind })
  return 2
end
env.html = mm.HTML([[<html><body><span class="nav-shortened-name">Personal</span></body></html>]])
env.bindActiveHtml(env.html)
local mid = env.runSubAccountScanLoop()
assert(type(mid) == "string" and mid:find("Account%-Switcher nicht verfügbar"), tostring(mid))
assert(env.LocalStorage.subAccountScan == nil)
assert(#softCalls == 0, "must not scrape when switcher unavailable mid-plan")

-- Fresh scan after hard fail still works when switcher returns
env.openAccountSwitcherEmbed = function()
  return mm.HTML(fixture)
end
env.switchAmazonSubAccount = function()
  return { ok = true }
end
local retryCalls = {}
env.collectOrdersFromOrderList = function(label, kind)
  table.insert(retryCalls, kind)
  return 1
end
local nRetry, errRetry = env.scanAllAmazonSubAccounts()
assert(errRetry == nil, tostring(errRetry))
assert(nRetry == 2)
assert(#retryCalls == 2)
assert(env.LocalStorage.subAccountScan.incomplete ~= true)

-- MFA during Refresh clears await_mfa
env.LocalStorage = {
  loginCounter = 5,
  OrderCache = {},
  getOrders = {},
  subAccountScan = { phase = "await_mfa", plan = {}, index = 1, totalNew = 0, loginCounter = 5 },
}
env.continueSubAccountScan = function()
  return { title = "2FA", challenge = "code", label = "Code" }
end
local nMfa, errMfa = env.scanAllAmazonSubAccounts()
assert(nMfa == nil and type(errMfa) == "string" and errMfa:find("2FA", 1, true))
assert(env.LocalStorage.subAccountScan == nil, "await_mfa must be cleared for re-login")

-- auth_prompt: password page must not hard-fail; submit credentials once
local function loadAuthPromptHtml()
  local f = assert(io.open("test/fixtures/switch_auth_prompt.html", "rb"))
  local body = f:read("*all")
  f:close()
  return mm.HTML(body)
end

local authHtml = loadAuthPromptHtml()
assert(env.switchAuthBlockReason(authHtml) == "interactive login")

local missing = env.finishAccountSwitchLanding(authHtml)
assert(type(missing.error) == "string" and missing.error:find("password missing", 1, true),
  "without credentials: " .. tostring(missing.error))

env.rememberShopCredentials("user@example.com", "secret")
local promptCalls = 0
env.submitSwitchAuthPrompt = function(node)
  promptCalls = promptCalls + 1
  assert(env.switchAuthBlockReason(node) == "interactive login")
  return mm.HTML("<html><body><span class='nav-shortened-name'>Biz</span></body></html>"), nil
end
local switched = env.finishAccountSwitchLanding(loadAuthPromptHtml())
assert(switched.ok == true, "auth_prompt then home must be ok")
assert(promptCalls == 1)

-- Still on password page after one try → error (no loop)
env.submitSwitchAuthPrompt = function()
  return loadAuthPromptHtml(), nil
end
local stuck = env.finishAccountSwitchLanding(loadAuthPromptHtml())
assert(type(stuck.error) == "string" and stuck.error:find("interactive login", 1, true),
  "second password page must error: " .. tostring(stuck.error))

-- Password then MFA challenge
env.submitSwitchAuthPrompt = function()
  return mm.HTML([[<html><body>
    <form id="auth-mfa-form"><p>Code eingeben</p>
    <input name="otpCode" type="text"/></form>
  </body></html>]]), nil
end
local needMfa = env.finishAccountSwitchLanding(loadAuthPromptHtml())
assert(needMfa.needsMfa == true and needMfa.challenge ~= nil)

local personalHtml = mm.HTML([[<html><body><span class="nav-shortened-name">Max</span></body></html>]])
env.bindActiveHtml(personalHtml)
assert(env.sessionMatchesSubAccountKind("personal") == true)
assert(env.sessionMatchesSubAccountKind("business") == false)

local businessHtml = mm.HTML([[<html><body><span class="abnav-accountfor">Example GmbH</span></body></html>]])
env.bindActiveHtml(businessHtml)
assert(env.sessionMatchesSubAccountKind("business") == true)
assert(env.sessionMatchesSubAccountKind("personal") == false)

print("test_account_switcher OK")
