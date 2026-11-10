-- Stable transaction IDs preserve equal-valued lines in the local snapshot.
-- Run: test/run.sh test/test_transaction_ids.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"
env.connectShop = function() return mm.HTML("<html><body></body></html>") end
env.getOrderDetails = function(order)
  order.detailsDate=os.time()+86400
  order.detailsParsed=true
end

local now=os.time()
local code="303-1234567-1234567"
local account={
  accountNumber="test@example.com",
  owner="test@example.com",
  attributes={},
}
env.LocalStorage={
  cacheVersion=23,
  loginCounter=1,
  lastLoginCounter=1,
  lastHarvestSince=now,
  OrderCache={
    [code]={
      orderCode=code,
      orderPositions={
        {purpose="Same item",amount=1999,qty=1},
        {purpose="Same item",amount=1999,qty=1},
      },
      orderSum=3998,
      orderTotal=3998,
      bookingDate=now-3600,
      detailsDate=now+86400,
      detailsParsed=true,
    },
  },
}

local knownIds={}
local first=env.RefreshAccount(account,now-86400,function(id)
  return knownIds[id] and {transactionId=id} or nil
end)
local lines={}
for _,transaction in ipairs(first.transactions) do
  if transaction.endToEndReference==code then
    lines[#lines+1]=transaction
  end
end
assert(#lines==2,"two identical article lines stay in the output")
assert(lines[1].transactionId and lines[2].transactionId,
  "both emitted transactions have IDs")
assert(lines[1].transactionId~=lines[2].transactionId,
  "duplicate article lines get distinct stable IDs")
assert(lines[1].transactionId:find("AMZ:"..code..":",1,true)==1,
  "transaction ID is namespaced by order")
knownIds[lines[1].transactionId]=true
local repeated=env.RefreshAccount(account,now-86400,function(id)
  return knownIds[id] and {transactionId=id} or nil
end)
for _,transaction in ipairs(repeated.transactions) do
  assert(transaction.endToEndReference~=code,
    "known transaction IDs are filtered before MoneyMoney sees them")
end

local snapshot=env.LocalStorage.OrderCache[code]
local stored=snapshot.emittedTransactionsByAccount["test@example.com"]
assert(#stored==2,"snapshot preserves both otherwise identical lines")
assert(stored[1].transactionId~=stored[2].transactionId,
  "snapshot stores distinct IDs")

env.clearOrderEmissionForAccount(snapshot,account.accountNumber)
account.attributes.resyncDeletedTransactions="transaction-id-test"
local replay=env.RefreshAccount(account,now-86400)
local replayIds={}
for _,transaction in ipairs(replay.transactions) do
  if transaction.endToEndReference==code then
    replayIds[#replayIds+1]=transaction.transactionId
  end
end
assert(#replayIds==2,"resync restores both identical lines")
assert(replayIds[1]==lines[1].transactionId and replayIds[2]==lines[2].transactionId,
  "resync keeps each stable ID")

local legacyCode="303-7654321-7654321"
env.LocalStorage.OrderCache[legacyCode]={
  orderCode=legacyCode,
  orderPositions={
    {purpose="Legacy duplicate",amount=500,qty=1},
    {purpose="Legacy duplicate",amount=500,qty=1},
  },
  orderSum=1000,
  orderTotal=1000,
  bookingDate=now-7200,
  detailsDate=now+86400,
  detailsParsed=true,
  emittedAccounts={[account.accountNumber]=true},
  emittedTransactionsByAccount={
    [account.accountNumber]={
      {name="Legacy duplicate",amount=-5,bookingDate=now-7200+1,
        endToEndReference=legacyCode,accountNumber=account.owner,purpose="Legacy duplicate"},
    },
  },
}
account.attributes.resyncDeletedTransactions="legacy-snapshot"
local legacyReplay=env.RefreshAccount(account,now-86400)
local legacyLines={}
for _,transaction in ipairs(legacyReplay.transactions) do
  if transaction.endToEndReference==legacyCode then
    legacyLines[#legacyLines+1]=transaction
  end
end
assert(#legacyLines==2,"legacy snapshots without IDs are rebuilt from order details")
assert(legacyLines[1].transactionId~=legacyLines[2].transactionId,
  "rebuilt legacy duplicate lines receive distinct IDs")

print("test_transaction_ids OK")
