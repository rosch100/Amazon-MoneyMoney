-- ListAccounts: shared Amazon + discovered sub-accounts for "Nach neuen Konten suchen".
-- Run: test/run.sh test/test_list_accounts.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = {}

local onlyShared = env.ListAccounts({})
assert(#onlyShared == 1, "without discovery only shared account, got " .. #onlyShared)
assert(onlyShared[1].accountNumber == "mix")
assert(onlyShared[1].name == "Amazon Alle Konten")
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

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Persönliches Konto" },
  { kind = "business", label = "Example GmbH" },
})
assert(#env.LocalStorage.discoveredSubAccounts == 2)

local listed = env.ListAccounts({})
assert(#listed == 3, "shared + 2 subs, got " .. #listed)
local byNum = {}
for _, a in ipairs(listed) do byNum[a.accountNumber] = a end
assert(byNum["mix"] ~= nil)
assert(byNum["mix"].name == "Amazon Persönliches Konto + Example GmbH")
assert(byNum["sub:personal"].name == "Amazon Persönlich")
assert(byNum["sub:business"].name == "Amazon Geschäftlich")

env.rememberDiscoveredSubAccounts({
  { kind = "business", label = "Example GmbH" },
  { kind = "personal", label = "Persönliches Konto" },
})
local reverseListed = env.ListAccounts({})
assert(reverseListed[1].accountNumber == "mix")
assert(reverseListed[1].name == "Amazon Persönliches Konto + Example GmbH")

assert(env.listAccountDisplayLabel("mix") == "Alle Konten")
assert(env.listAccountDisplayLabel("sub:personal") == "Persönlich")
assert(env.listAccountDisplayLabel("sub:business") == "Geschäftlich")

-- Known accounts: ListAccounts stays stable (no getOrders / reload gate)
env.clearPendingInitialSync()
env.clearAccountSetupState()
env.LocalStorage.lastHarvestSince = os.time()
local listedKnown = env.ListAccounts({ "mix", "sub:personal" })
assert(#listedKnown == 3)
assert(env.isPendingInitialSync() == false, "account search must not trigger initial full import")

local listedWithKnownAttrs = env.ListAccounts({
  { accountNumber = "mix", attributes = { keepStorno = "true", resetCache = "2026-08-27" } },
})
assert(listedWithKnownAttrs[1].attributes.keepStorno == "true")
assert(listedWithKnownAttrs[1].attributes.resetCache == "2026-08-27")
assert(listedWithKnownAttrs[1].attributes[1] == nil)
assert(listedWithKnownAttrs[1].attributes.blacklistOrders == "")

assert(env.subAccountNumberForKind("personal") == "sub:personal")
assert(env.subAccountNumberForKind("business") == "sub:business")
assert(env.isCombinedMoneyMoneyAccount("mix") == true)
assert(env.isCombinedMoneyMoneyAccount("sub:business") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "mix") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "sub:business") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "personal" }, "sub:business") == false)

-- Legacy cache: label only → backfill kind from discovery
local legacy = { accountNumber = "Example GmbH" }
assert(env.orderMatchesMoneyMoneyAccount(legacy, "sub:business") == true)
assert(legacy.subAccountKind == "business")
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "sub:business") == false)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "business" }, 100, "sub:business") == true)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "mix") == true)

local order = {}
env.assignSubAccountMeta(order, "Example GmbH", "business")
assert(order.accountNumber == "Example GmbH")
assert(order.subAccountKind == "business")

print("test_list_accounts OK")
