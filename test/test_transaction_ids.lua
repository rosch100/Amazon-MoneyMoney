-- Stable transaction IDs preserve equal-valued lines in the local snapshot.
-- Run: test/run.sh test/test_transaction_ids.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local ffi = require("ffi")

ffi.cdef[[
  unsigned char *MD5(const unsigned char *d, size_t n, unsigned char *md);
]]
local crypto = assert(ffi.load("crypto"), "OpenSSL libcrypto is required for transaction-ID tests")
local function realMd5(value)
  local digest=ffi.new("unsigned char[16]")
  assert(crypto.MD5(value,#value,digest)~=nil,"OpenSSL MD5 calculation failed")
  return (ffi.string(digest,16):gsub(".",function(byte)
    return string.format("%02x",string.byte(byte))
  end))
end

local env = mm.loadPlugin("amazon-bestellungen.lua",nil,{md5=realMd5})
assert(realMd5("test")=="098f6bcd4621d373cade4e832627b4f6",
  "the transaction-ID test must calculate real MD5 hashes")
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

env.clearOrderEmissionForAccount(
  env.LocalStorage.OrderCache[legacyCode],account.accountNumber)
account.attributes.resyncDeletedTransactions="legacy-snapshot-again"
local repeatedLegacyReplay=env.RefreshAccount(account,now-86400)
local repeatedLegacyIds={}
for _,transaction in ipairs(repeatedLegacyReplay.transactions) do
  if transaction.endToEndReference==legacyCode then
    repeatedLegacyIds[#repeatedLegacyIds+1]=transaction.transactionId
  end
end
assert(#repeatedLegacyIds==2,"the same legacy snapshot can be replayed again")
assert(repeatedLegacyIds[1]==legacyLines[1].transactionId
    and repeatedLegacyIds[2]==legacyLines[2].transactionId,
  "legacy transaction IDs stay stable across identical refreshes")

local offsetDate=os.time({year=2026,month=10,day=20,hour=12})
local function makeMonthlyOffset(purchases,knownIds)
  local context={transactions=purchases,now=offsetDate}
  env.appendPeriodContraTransactions(context,env.ledgerModeProfile("monthly"))
  local offsets={}
  for _,transaction in ipairs(context.transactions) do
    if transaction.name:find("Amazon Monatsausgleich",1,true)==1 then
      offsets[#offsets+1]=transaction
    end
  end
  env.assignAccountTransactionIds(offsets,account.accountNumber,offsetDate,
    function(id)
      return knownIds[id] and {transactionId=id} or nil
    end)
  return offsets
end

local existingPurchase={
  name="Existing purchase",
  purpose="Existing purchase",
  amount=-10,
  bookingDate=offsetDate,
  endToEndReference="303-1111111-1111111",
}
local firstOffsets=makeMonthlyOffset({existingPurchase},{})
assert(#firstOffsets==1,"first monthly batch creates a balancing offset")
local firstOffsetId=firstOffsets[1].transactionId

local newPurchase={
  name="New purchase",
  purpose="New purchase",
  amount=-20,
  bookingDate=offsetDate,
  endToEndReference="303-2222222-2222222",
}
local laterOffsets=makeMonthlyOffset(
  {existingPurchase,newPurchase},{[firstOffsetId]=true})
assert(#laterOffsets==1,"a changed monthly batch still emits its new offset")
assert(laterOffsets[1].transactionId~=firstOffsetId,
  "monthly offsets for changed period contents receive distinct IDs")
local repeatedOffsets=makeMonthlyOffset(
  {existingPurchase,newPurchase},{[laterOffsets[1].transactionId]=true})
assert(#repeatedOffsets==0,
  "an identical monthly batch retains the same known offset ID")

local sameTotalDifferentPurchases=makeMonthlyOffset({
  {
    name="First purchase",
    purpose="First purchase",
    amount=-10,
    bookingDate=offsetDate,
    endToEndReference="303-3333333-3333333",
  },
  {
    name="Second purchase",
    purpose="Second purchase",
    amount=-20,
    bookingDate=offsetDate,
    endToEndReference="303-4444444-4444444",
  },
},{})
assert(sameTotalDifferentPurchases[1].transactionId~=laterOffsets[1].transactionId,
  "offset identity includes its purchase set, not only amount and period")

print("test_transaction_ids OK")
