package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = {}
env.secUsername = "user@example.com"

assert(env.isCombinedMoneyMoneyAccount("user@example.com") == true)
assert(env.isCombinedMoneyMoneyAccount("mix") == true)
assert(env.isCombinedMoneyMoneyAccount(nil) == true)
assert(env.isCombinedMoneyMoneyAccount("A3PERSONALID01") == false)
assert(env.isCombinedMoneyMoneyAccount("sub:personal") == false)

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", label = "Test User", accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", accountNumber = "A3BUSINESSID02" },
}
assert(env.harvestPriorityKindFromAccountNumber("A3PERSONALID01") == "personal")
assert(env.harvestPriorityKindFromAccountNumber("A3BUSINESSID02") == "business")
assert(env.harvestPriorityKindFromAccountNumber("user@example.com") == nil)
assert(env.harvestPriorityKindFromAccountNumber("sub:personal") == "personal")
assert(env.harvestPriorityKindFromAccountNumber("unknown-id") == nil)

local biz = { subAccountKind = "business" }
assert(env.orderMatchesMoneyMoneyAccount(biz, "user@example.com") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "A3BUSINESSID02") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "A3PERSONALID01") == false)
assert(env.orderMatchesMoneyMoneyAccount(biz, "unknown-id") == false)
print("test_account_role_ssot OK")
