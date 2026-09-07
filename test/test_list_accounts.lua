-- ListAccounts: shared Amazon + discovered sub-accounts for "Nach neuen Konten suchen".
-- Run: test/run.sh test/test_list_accounts.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "user@example.com"
env.LocalStorage = {}

local onlyShared = env.ListAccounts({})
assert(#onlyShared == 1, "without discovery only shared account, got " .. #onlyShared)
assert(onlyShared[1].accountNumber == "user@example.com")
assert(onlyShared[1].name == "Amazon")
assert(onlyShared[1].type == "AccountTypeOther")
assert(onlyShared[1].portfolio == false)
assert(onlyShared[1].currency == "EUR")
assert(onlyShared[1].withTotalSum == false)
assert(onlyShared[1].showInDiagrams == false)
assert(onlyShared[1].showDailyBalance == false)
assert(onlyShared[1].perspective ~= nil and onlyShared[1].perspective.chart == 1)
assert(type(onlyShared[1].attributes) == 'table', "ListAccounts must return note defaults")
assert(onlyShared[1].attributes[1] == nil, "attributes must be a pure dict, not a hybrid array")
assert(onlyShared[1].attributes.resetCache == "")
assert(onlyShared[1].attributes.blacklistOrders == "")
assert(onlyShared[1].attributes.rescanOrder == "")
assert(onlyShared[1].attributes.keepStorno == "false", "ListAccounts must pre-fill default values for MM note UI")
assert(onlyShared[1].attributes.nameMaxLength == "0", "title line is untruncated by default")

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", accountNumber = "", customerName = "Incomplete" },
  { kind = "business", accountNumber = "JUNK-NO-NAME" },
}
assert(#env.ListAccounts({}) == 1, "incomplete discovery alone must offer only combined")

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", accountNumber = "", customerName = "Incomplete" },
  { kind = "business", accountNumber = "JUNK-NO-NAME" },
  { kind = "other", accountNumber = "JUNK-UNKNOWN-KIND", label = "Junk" },
  { kind = "personal", accountNumber = "sub:personal", customerName = "Legacy Sub" },
  { kind = "personal", accountNumber = "A3PERSONALID01", label = "Label Only" },
  { kind = "personal", accountNumber = "A3PERSONALID01", customerName = "Test User" },
  { kind = "business", accountNumber = "A3BUSINESSID02", businessName = "Example GmbH" },
}
local listedWithJunk = env.ListAccounts({})
assert(#listedWithJunk == 3, "only complete discovered entries may be offered")
local junkNumbers = {}
for _, account in ipairs(listedWithJunk) do
  junkNumbers[account.accountNumber] = true
end
assert(junkNumbers["JUNK-NO-NAME"] == nil)
assert(junkNumbers["JUNK-UNKNOWN-KIND"] == nil)
assert(junkNumbers["sub:personal"] == nil)
assert(junkNumbers["A3PERSONALID01"] == nil, "bare customerId must not be offered")
assert(junkNumbers["AO.3PERSONALID01"] == true)
assert(junkNumbers["AO.3BUSINESSID02"] == true)
assert(env.isCompleteDiscoveredSubAccount({
  kind = "personal", accountNumber = "sub:personal", customerName = "X",
}) == false, "legacy sub:* must not count as complete")
assert(env.isCompleteDiscoveredSubAccount({
  kind = "personal", accountNumber = "A3PERSONALID01", label = "Only Label",
}) == false, "customerName required, label alone is not enough")

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", accountNumber = "A3PERSONALID01", customerName = "Test User" },
  { kind = "business", accountNumber = "A3BUSINESSID02", businessName = "Example GmbH" },
  { kind = "personal", accountNumber = "JUNK-ONLY", customerName = "" },
}
local listedWithIncompleteOnly = env.ListAccounts({})
assert(#listedWithIncompleteOnly == 3, "incomplete entries must not affect complete pair")

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Test User", customerName = "Test User",
    accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
})
assert(#env.LocalStorage.discoveredSubAccounts == 2)

local listed = env.ListAccounts({})
assert(#listed == 3, "shared + 2 subs, got " .. #listed)
local byNum = {}
for _, a in ipairs(listed) do byNum[a.accountNumber] = a end
assert(byNum["user@example.com"].name == "Amazon")
assert(byNum["AO.3PERSONALID01"].name == "Amazon Test User")
assert(byNum["AO.3BUSINESSID02"].name == "Amazon Example GmbH")
assert(byNum["AO.3PERSONALID01"].subAccount == nil)
assert(byNum["user@example.com"].type == "AccountTypeOther")
assert(byNum["AO.3PERSONALID01"].type == "AccountTypeOther")
assert(byNum["AO.3BUSINESSID02"].type == "AccountTypeOther")
assert(byNum["mix"] == nil)
assert(byNum["sub:personal"] == nil)
assert(byNum["A3PERSONALID01"] == nil)
assert(byNum["AB-A3PERSONALID01"] == nil)
assert(string.find(byNum["AO.3PERSONALID01"].accountNumber, "A3PERSONALID01", 1, true) == nil,
  "encoded MM number must not contain raw customerId substring")

env.rememberDiscoveredSubAccounts({
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
  { kind = "personal", label = "Test User", customerName = "Test User",
    accountNumber = "A3PERSONALID01" },
})
local reverseListed = env.ListAccounts({})
assert(reverseListed[1].accountNumber == "user@example.com")
assert(reverseListed[1].name == "Amazon")

assert(env.listAccountDisplayLabel("user@example.com") == "Amazon")
assert(env.listAccountDisplayLabel("A3PERSONALID01", {
  kind = "personal", customerName = "Test User", accountNumber = "A3PERSONALID01",
}) == "Test User")
assert(env.listAccountDisplayLabel("A3BUSINESSID02", {
  kind = "business", businessName = "Example GmbH", accountNumber = "A3BUSINESSID02",
}) == "Example GmbH")

-- Known accounts: ListAccounts stays stable (no getOrders / reload gate)
env.clearPendingInitialSync()
env.clearAccountSetupState()
env.LocalStorage.lastHarvestSince = os.time()
local listedKnown = env.ListAccounts({ "user@example.com", "AO.3PERSONALID01" })
assert(#listedKnown == 3)
assert(env.isPendingInitialSync() == false, "account search must not trigger initial full import")

local listedWithKnownAttrs = env.ListAccounts({
  { accountNumber = "user@example.com", attributes = { keepStorno = "true", resetCache = "2026-08-27" } },
})
assert(listedWithKnownAttrs[1].attributes.keepStorno == "true")
assert(listedWithKnownAttrs[1].attributes.resetCache == "2026-08-27")
assert(listedWithKnownAttrs[1].attributes[1] == nil)
assert(listedWithKnownAttrs[1].attributes.blacklistOrders == "")

assert(env.subAccountNumberForKind("personal") == "AO.3PERSONALID01")
assert(env.subAccountNumberForKind("business") == "AO.3BUSINESSID02")
assert(env.isCombinedMoneyMoneyAccount("mix") == false)
assert(env.isCombinedMoneyMoneyAccount("AO.3BUSINESSID02") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "user@example.com") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "mix") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "AO.3BUSINESSID02") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "personal" }, "AO.3BUSINESSID02") == false)

-- Match requires explicit subAccountKind (no label-only backfill)
assert(env.orderMatchesMoneyMoneyAccount({ accountNumber = "Example GmbH" }, "AO.3BUSINESSID02") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "AO.3BUSINESSID02") == true)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "AO.3BUSINESSID02") == false)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "business" }, 100, "AO.3BUSINESSID02") == true)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "user@example.com") == true)

local order = {}
env.assignSubAccountMeta(order, "Example GmbH", "business")
assert(order.accountNumber == "Example GmbH")
assert(order.subAccountKind == "business")

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Missing ID", customerName = "Missing ID" },
})
assert(#env.LocalStorage.discoveredSubAccounts == 0)
assert(#env.ListAccounts({}) == 1)

env.secUsername = nil
local ok, err = pcall(env.ListAccounts, {})
assert(ok == false and err ~= nil, "ListAccounts must fail without secUsername")
assert(tostring(err):find("Anmeldenamen", 1, true), tostring(err))

print("test_list_accounts OK")
