package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = {}
env.secUsername = "user@example.com"

assert(env.isCombinedMoneyMoneyAccount("user@example.com") == true)
assert(env.isCombinedMoneyMoneyAccount("mix") == false)
assert(env.isCombinedMoneyMoneyAccount(nil) == true)
assert(env.isCombinedMoneyMoneyAccount("A3PERSONALID01") == false)
assert(env.isCombinedMoneyMoneyAccount("sub:personal") == false)

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", label = "Test User", accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", accountNumber = "A3BUSINESSID02" },
}
assert(env.harvestPriorityKindFromAccountNumber("AO.3PERSONALID01") == "personal")
assert(env.harvestPriorityKindFromAccountNumber("AO.3BUSINESSID02") == "business")
assert(env.harvestPriorityKindFromAccountNumber("user@example.com") == nil)
assert(env.harvestPriorityKindFromAccountNumber("sub:personal") == nil)
assert(env.harvestPriorityKindFromAccountNumber("unknown-id") == nil)

local biz = { subAccountKind = "business" }
local personal = { subAccountKind = "personal" }
assert(env.orderMatchesMoneyMoneyAccount(biz, "user@example.com") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, nil) == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "AO.3BUSINESSID02") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "AO.3PERSONALID01") == false)
assert(env.orderMatchesMoneyMoneyAccount(biz, "unknown-id") == false)

assert(env.refreshAccountLedgerProfile("user@example.com").divisor == -100)
assert(env.refreshAccountLedgerProfile("AO.3PERSONALID01").divisor == -100)

-- Combined sentinel is not obsolete (SSOT vs recreate path).
assert(env.isObsoleteMoneyMoneyAccountNumber(nil) == false)
assert(env.isObsoleteMoneyMoneyAccountNumber("") == false)

-- Obsolete numbers: RefreshAccount demands recreate (ledger profile itself is constant).
for _, obsolete in ipairs({ "mix", "normal", "inverse", "monthly", "yearly",
    "sub:personal", "sub:business" }) do
  assert(env.isObsoleteMoneyMoneyAccountNumber(obsolete) == true, obsolete)
  assert(env.orderMatchesMoneyMoneyAccount(biz, obsolete) == false, obsolete)
  assert(env.orderMatchesMoneyMoneyAccount(personal, obsolete) == false, obsolete)
  local ok, err = pcall(env.RefreshAccount, { accountNumber = obsolete }, 0)
  assert(ok == false, "RefreshAccount must reject "..obsolete)
  assert(tostring(err):find("neu anlegen", 1, true), obsolete.." error text")
end
assert(env.isObsoleteMoneyMoneyAccountNumber("A3PERSONALID01") == true,
  "bare customerId / AB- forms collide with Amazon Kreditkarte")
assert(env.isObsoleteMoneyMoneyAccountNumber("AB-A3PERSONALID01") == true)
assert(env.isObsoleteMoneyMoneyAccountNumber("AO.3PERSONALID01") == false)
assert(env.isObsoleteMoneyMoneyAccountNumber("user@example.com") == false)

local bareOk, bareErr = pcall(env.RefreshAccount, { accountNumber = "A3PERSONALID01" }, 0)
assert(bareOk == false, "RefreshAccount must reject bare customerId")
assert(tostring(bareErr):find("neu anlegen", 1, true))

local abOk, abErr = pcall(env.RefreshAccount, { accountNumber = "AB-A3PERSONALID01" }, 0)
assert(abOk == false, "RefreshAccount must reject AB- customerId form")
assert(tostring(abErr):find("neu anlegen", 1, true))

local refreshOk, refreshErr = pcall(env.RefreshAccount, { accountNumber = "mix" }, 0)
assert(refreshOk == false, "RefreshAccount must reject obsolete mix")
assert(tostring(refreshErr):find("Amazon Bestellungen", 1, true),
  "RefreshAccount must name the current service")

print("test_account_role_ssot OK")
