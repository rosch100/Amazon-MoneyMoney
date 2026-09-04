-- ListAccounts: shared Amazon + discovered sub-accounts for "Nach neuen Konten suchen".
-- Run: test/run.sh test/test_list_accounts.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
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
  { kind = "personal", accountNumber = "A3PERSONALID01", label = "Test User" },
  { kind = "business", accountNumber = "A3BUSINESSID02", label = "Example GmbH" },
}
local listedWithJunk = env.ListAccounts({})
assert(#listedWithJunk == 3, "only complete discovered entries may be offered")
local junkNumbers = {}
for _, account in ipairs(listedWithJunk) do
  junkNumbers[account.accountNumber] = true
end
assert(junkNumbers["JUNK-NO-NAME"] == nil)
assert(junkNumbers["JUNK-UNKNOWN-KIND"] == nil)
assert(junkNumbers["A3PERSONALID01"] == true)
assert(junkNumbers["A3BUSINESSID02"] == true)

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
assert(byNum["A3PERSONALID01"].name == "Amazon Test User")
assert(byNum["A3BUSINESSID02"].name == "Amazon Example GmbH")
assert(byNum["user@example.com"].type == "AccountTypeOther")
assert(byNum["A3PERSONALID01"].type == "AccountTypeOther")
assert(byNum["mix"] == nil)
assert(byNum["sub:personal"] == nil)

env.rememberDiscoveredSubAccounts({
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
  { kind = "personal", label = "Test User", customerName = "Test User",
    accountNumber = "A3PERSONALID01" },
})
local reverseListed = env.ListAccounts({})
assert(reverseListed[1].accountNumber == "user@example.com")
assert(reverseListed[1].name == "Amazon")

assert(env.listAccountDisplayLabel("mix") == "Test User + Example GmbH")
assert(env.listAccountDisplayLabel("sub:personal") == "Persönlich")
assert(env.listAccountDisplayLabel("sub:business") == "Geschäftlich")

-- Known accounts: ListAccounts stays stable (no getOrders / reload gate)
env.clearPendingInitialSync()
env.clearAccountSetupState()
env.LocalStorage.lastHarvestSince = os.time()
local listedKnown = env.ListAccounts({ "user@example.com", "A3PERSONALID01" })
assert(#listedKnown == 3)
assert(env.isPendingInitialSync() == false, "account search must not trigger initial full import")

local listedWithKnownAttrs = env.ListAccounts({
  { accountNumber = "user@example.com", attributes = { keepStorno = "true", resetCache = "2026-08-27" } },
})
assert(listedWithKnownAttrs[1].attributes.keepStorno == "true")
assert(listedWithKnownAttrs[1].attributes.resetCache == "2026-08-27")
assert(listedWithKnownAttrs[1].attributes[1] == nil)
assert(listedWithKnownAttrs[1].attributes.blacklistOrders == "")

assert(env.subAccountNumberForKind("personal") == "A3PERSONALID01")
assert(env.subAccountNumberForKind("business") == "A3BUSINESSID02")
assert(env.isCombinedMoneyMoneyAccount("mix") == true)
assert(env.isCombinedMoneyMoneyAccount("A3BUSINESSID02") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "mix") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "A3BUSINESSID02") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "personal" }, "A3BUSINESSID02") == false)

-- Legacy cache: label only → backfill kind from discovery
local legacy = { accountNumber = "Example GmbH" }
assert(env.orderMatchesMoneyMoneyAccount(legacy, "A3BUSINESSID02") == true)
assert(legacy.subAccountKind == "business")
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "A3BUSINESSID02") == false)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "business" }, 100, "A3BUSINESSID02") == true)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "mix") == true)

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

print("test_list_accounts OK")
