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

-- Legacy account numbers span all sub-accounts, "normal" included.
local personal = { subAccountKind = "personal" }
for _, legacy in ipairs({ "mix", "normal", "inverse", "monthly", "yearly" }) do
  assert(env.isLegacyMoneyMoneyAccountNumber(legacy) == true, legacy)
  assert(env.orderMatchesMoneyMoneyAccount(biz, legacy) == true, legacy)
  assert(env.orderMatchesMoneyMoneyAccount(personal, legacy) == true, legacy)
end
assert(env.isLegacyMoneyMoneyAccountNumber("A3PERSONALID01") == false)
assert(env.isLegacyMoneyMoneyAccountNumber("user@example.com") == false)

-- Only legacy "normal"/"inverse" track a real balance; everything else is mixed.
local normalLedger = env.refreshAccountLedgerProfile("normal")
assert(normalLedger.mixed == false, "legacy normal must not use the mixed ledger")
assert(normalLedger.divisor == -100)
assert(normalLedger.periodly == false)

local inverseLedger = env.refreshAccountLedgerProfile("inverse")
assert(inverseLedger.mixed == false, "legacy inverse must not use the mixed ledger")
assert(inverseLedger.divisor == 100)

assert(env.refreshAccountLedgerProfile("mix").mixed == true)
assert(env.refreshAccountLedgerProfile(nil).mixed == true)
assert(env.refreshAccountLedgerProfile("user@example.com").mixed == true)
assert(env.refreshAccountLedgerProfile("A3PERSONALID01").mixed == true)

local monthlyLedger = env.refreshAccountLedgerProfile("monthly")
assert(monthlyLedger.mixed == true)
assert(monthlyLedger.periodly == true)
assert(monthlyLedger.periodFmt == "%Y-%m")

local yearlyLedger = env.refreshAccountLedgerProfile("yearly")
assert(yearlyLedger.mixed == true)
assert(yearlyLedger.periodly == true)
assert(yearlyLedger.periodFmt == "%Y")

print("test_account_role_ssot OK")
