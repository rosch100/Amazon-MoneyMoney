-- ListAccounts: shared Amazon + discovered sub-accounts for "Nach neuen Konten suchen".
-- Run: test/run.sh test/test_list_accounts.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = { getOrders = {} }

local onlyShared = env.ListAccounts({})
assert(#onlyShared == 1, "without discovery only shared account, got " .. #onlyShared)
assert(onlyShared[1].accountNumber == "mix")
assert(onlyShared[1].name:find("Amazon", 1, true))
assert(env.LocalStorage.getOrders["mix"] == false, "new mix needs reload")

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Persönliches Konto" },
  { kind = "business", label = "Altanis GmbH" },
})
assert(#env.LocalStorage.discoveredSubAccounts == 2)

local listed = env.ListAccounts({})
assert(#listed == 3, "shared + 2 subs, got " .. #listed)
local byNum = {}
for _, a in ipairs(listed) do byNum[a.accountNumber] = a end
assert(byNum["mix"] ~= nil)
assert(byNum["sub:personal"].name == "Amazon Persönliches Konto")
assert(byNum["sub:business"].name == "Amazon Altanis GmbH")

-- Known accounts: do not reset getOrders that already refreshed
env.LocalStorage.getOrders["mix"] = true
env.LocalStorage.getOrders["sub:personal"] = true
local listedKnown = env.ListAccounts({ "mix", "sub:personal" })
assert(#listedKnown == 3)
assert(env.LocalStorage.getOrders["mix"] == true, "known mix must keep getOrders")
assert(env.LocalStorage.getOrders["sub:personal"] == true)
assert(env.LocalStorage.getOrders["sub:business"] == false, "new sub still needs reload")

assert(env.subAccountNumberForKind("personal") == "sub:personal")
assert(env.subAccountNumberForKind("business") == "sub:business")
assert(env.isCombinedMoneyMoneyAccount("mix") == true)
assert(env.isCombinedMoneyMoneyAccount("sub:business") == false)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "mix") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "business" }, "sub:business") == true)
assert(env.orderMatchesMoneyMoneyAccount({ subAccountKind = "personal" }, "sub:business") == false)

-- Legacy cache: label only → backfill kind from discovery
local legacy = { accountNumber = "Altanis GmbH" }
assert(env.orderMatchesMoneyMoneyAccount(legacy, "sub:business") == true)
assert(legacy.subAccountKind == "business")
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "sub:business") == false)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "business" }, 100, "sub:business") == true)
assert(env.orderNeedsDetailsForAccount({ detailsDate = 1, subAccountKind = "personal" }, 100, "mix") == true)

local order = {}
env.assignSubAccountMeta(order, "Altanis GmbH", "business")
assert(order.accountNumber == "Altanis GmbH")
assert(order.subAccountKind == "business")

print("test_list_accounts OK")
