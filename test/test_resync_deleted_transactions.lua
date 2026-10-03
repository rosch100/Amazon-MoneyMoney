-- Explicit resync re-emits cached orders once when the note token changes.
-- Run: test/run.sh test/test_resync_deleted_transactions.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"
env.connectShop = function() return mm.HTML("<html><body></body></html>") end

local now = os.time()
local orderCode = "303-1234567-1234567"
local account = {
  accountNumber = "test@example.com",
  owner = "test@example.com",
  attributes = { resyncDeletedTransactions = "2026-10-03-a" },
}
local since = now - 86400

env.LocalStorage = {
  cacheVersion = 23,
  loginCounter = 1,
  lastLoginCounter = 1,
  lastHarvestSince = now,
  OrderCache = {
    [orderCode] = {
      orderCode = orderCode,
      orderPositions = { { purpose = "Cached item", amount = 1234, qty = 1 } },
      orderSum = 1234,
      orderTotal = 1234,
      bookingDate = now - 3600,
      detailsDate = now + 86400,
      detailsParsed = true,
      emittedAccounts = { [account.accountNumber] = true },
      refundTransactions = {
        [now - 1800] = {
          [234] = { emittedAccounts = { [account.accountNumber] = true } },
        },
      },
      subAccountKind = "business",
    },
  },
}

local function transactionsForOrder()
  local result = env.RefreshAccount(account, since)
  local transactions = {}
  for _, transaction in ipairs(result.transactions) do
    if transaction.endToEndReference == orderCode then
      table.insert(transactions, transaction)
    end
  end
  return transactions
end

local first = transactionsForOrder()
assert(#first == 2, "new resync token must re-emit cached purchase and refund once")
local purchaseCount = 0
local refundCount = 0
for _, transaction in ipairs(first) do
  if transaction.name == "Cached item" then purchaseCount = purchaseCount + 1 end
  if transaction.name == "Erstattung für Bestellung " .. orderCode then refundCount = refundCount + 1 end
end
assert(purchaseCount == 1, "resync must return the cached purchase")
assert(refundCount == 1, "resync must return the cached refund")
assert(type(env.LocalStorage.OrderCache[orderCode].emittedTransactionsByAccount) == "table",
  "emitted transactions must be cached for exact later replay")

assert(env.LocalStorage.deletedTransactionResyncTokens[account.accountNumber] == "2026-10-03-a",
  "successful refresh must persist the replay token per account")
env.LocalStorage.OrderCache[orderCode].emittedAccounts = nil
account.attributes.resyncDeletedTransactions = ""
local rescanned = transactionsForOrder()
assert(#rescanned == 1,
  "explicitly re-emitted purchase is returned once, got " .. #rescanned)
account.attributes.resyncDeletedTransactions = "2026-10-03-b"
local replayAfterRescan = transactionsForOrder()
assert(#replayAfterRescan == 2,
  "re-emitting the same purchase must not duplicate its stored replay snapshot, got "
    .. #replayAfterRescan)
assert(env.LocalStorage.OrderCache[orderCode].emittedAccounts[account.accountNumber] == true,
  "resync-emitted order must be marked emitted again")

local unchanged = transactionsForOrder()
assert(#unchanged == 0, "same resync token must not replay transactions repeatedly")

env.LocalStorage.OrderCache[orderCode].orderPositions[1].purpose = "Changed Amazon description"
account.attributes.resyncDeletedTransactions = "2026-10-03-c"
local changed = transactionsForOrder()
assert(#changed == 2, "changing the resync token must request another one-shot replay")
assert(changed[1].name == "Cached item" or changed[2].name == "Cached item",
  "replay must preserve the transaction as originally emitted, not current parsed details")

local returnOrderCode = "303-7654321-7654321"
env.LocalStorage.OrderCache[returnOrderCode] = {
  orderCode = returnOrderCode,
  orderPositions = { { purpose = "Returned item", amount = 500, qty = 1 } },
  orderSum = 500,
  orderTotal = 500,
  bookingDate = now - 7200,
  detailsDate = now + 86400,
  detailsParsed = true,
  subAccountKind = "business",
}
account.attributes.resyncDeletedTransactions = ""
local originalPurchase = env.RefreshAccount(account, since)
local originalPurchaseCount = 0
for _, transaction in ipairs(originalPurchase.transactions) do
  if transaction.endToEndReference == returnOrderCode then
    originalPurchaseCount = originalPurchaseCount + 1
    assert(transaction.name == "Returned item")
  end
end
assert(originalPurchaseCount == 1, "purchase must be saved before its later return")

env.LocalStorage.OrderCache[returnOrderCode].orderTotal = 0
env.LocalStorage.OrderCache[returnOrderCode].returnActivity = true
env.LocalStorage.OrderCache[returnOrderCode].returns = {
  [now - 3600] = { [500] = { ["Returned item"] = {} } },
}
account.attributes.resyncDeletedTransactions = "2026-10-03-d"
local replayedReturnOrder = env.RefreshAccount(account, since)
local replayedReturnCount = 0
for _, transaction in ipairs(replayedReturnOrder.transactions) do
  if transaction.endToEndReference == returnOrderCode then
    replayedReturnCount = replayedReturnCount + 1
    assert(transaction.name == "Returned item",
      "replay must preserve original purchase despite updated return state")
  end
end
assert(replayedReturnCount == 1,
  "resync must restore the transaction originally emitted before the return")

local subAccount = { accountNumber = "AO.3BUSINESSID02", owner = account.owner,
  attributes = { resyncDeletedTransactions = "subaccount-replay" } }
env.rememberDiscoveredSubAccounts({
  { kind = "business", businessName = "Example GmbH", accountNumber = "A3BUSINESSID02" },
})
local subAccountReplay = env.RefreshAccount(subAccount, since)
for _, transaction in ipairs(subAccountReplay.transactions) do
  assert(transaction.endToEndReference ~= orderCode
      and transaction.endToEndReference ~= returnOrderCode,
    "combined-account transactions must not be replayed into a new sub-account")
end

print("test_resync_deleted_transactions OK")
