-- Account note ledgerMode restores the original booking presentations.
-- Run: test/run.sh test/test_ledger_modes.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")
env.secUsername = "test@example.com"
env.connectShop = function() return mm.HTML("<html><body></body></html>") end
env.getOrderDetails = function(order)
  if type(order) == "table" then
    order.detailsDate = os.time() + 86400
    order.detailsParsed = true
  end
end

local function close(left, right)
  return math.abs(left - right) < 0.0001
end

local function makeCache()
  local purchaseDate=os.time({year=2026,month=10,day=5,hour=12})
  local refundDate=os.time({year=2026,month=10,day=20,hour=12})
  return {
    ["303-1111111-1111111"]={
      orderCode="303-1111111-1111111",
      subAccountKind="business",
      orderPositions={
        {purpose="Item A",amount=2000,qty=1},
        {purpose="Item B",amount=550,qty=1},
      },
      orderSum=2550,
      orderTotal=2550,
      bookingDate=purchaseDate,
      detailsDate=os.time()+86400,
      detailsParsed=true,
      returns={[refundDate]={[550]={["Item B"]={}}}},
    },
    ["303-2222222-2222222"]={
      orderCode="303-2222222-2222222",
      accountNumber="Business",
      subAccountKind="business",
      orderPositions={{purpose="Item C",amount=1999,qty=1}},
      orderSum=1999,
      orderTotal=1999,
      bookingDate=os.time({year=2026,month=9,day=10,hour=12}),
      detailsDate=os.time()+86400,
      detailsParsed=true,
    },
  }
end

local function refresh(mode,isKnownTransactionId)
  env.LocalStorage={
    cacheVersion=23,
    loginCounter=1,
    lastLoginCounter=1,
    lastHarvestSince=os.time(),
    OrderCache=makeCache(),
  }
  env.rememberDiscoveredSubAccounts({
    {kind="personal",accountNumber="A3PERSONALID01",name="Personal"},
    {kind="business",accountNumber="A3BUSINESSID02",name="Business"},
  })
  return env.RefreshAccount({
    accountNumber="test@example.com",
    owner="test@example.com",
    attributes={ledgerMode=mode=="sub" and "mix" or mode},
  },os.time()-7*86400,isKnownTransactionId or function() return nil end)
end

local function sum(transactions)
  local total=0
  for _,transaction in ipairs(transactions) do total=total+transaction.amount end
  return total
end

for _,mode in ipairs({"","normal","NORMAL","unknown"}) do
  local result=refresh(mode)
  assert(close(sum(result.transactions),-39.99),"normal mode total for "..mode)
  for _,transaction in ipairs(result.transactions) do
    assert(transaction.name:find("Gegenbuchung",1,true)==nil,
      "normal mode has no contra bookings")
  end
end

local inverse=refresh("inverse")
assert(close(sum(inverse.transactions),39.99),
  "inverse flips booking signs, got "..tostring(sum(inverse.transactions)))

local function resync(mode,token)
  return env.RefreshAccount({
    accountNumber="test@example.com",
    owner="test@example.com",
    attributes={
      ledgerMode=mode,
      resyncDeletedTransactions=token,
    },
  },os.time()-7*86400,function() return nil end)
end

local mixed=refresh("mix")
assert(close(sum(mixed.transactions),0),"mix offsets emitted transactions")
local contraCount=0
for _,transaction in ipairs(mixed.transactions) do
  if transaction.name=="Amazon Gegenbuchung" then
    contraCount=contraCount+1
    assert(transaction.purpose:find(transaction.endToEndReference,1,true),
      "contra purpose identifies its order")
  end
end
assert(contraCount==3,"mix offsets each order and booking date")

local savedMixCount=0
for _,order in pairs(env.LocalStorage.OrderCache) do
  local entries=env.cachedOrderTransactionsForAccount(order,"test@example.com")
  savedMixCount=savedMixCount+#entries
end
local mixedResync=resync("mix","mix-resync")
assert(#mixedResync.transactions==savedMixCount,
  "mix resync restores all saved order transactions")
assert(close(sum(mixedResync.transactions),0),"mix resync restores balanced order offsets")

local monthly=refresh("monthly")
local monthlyOffsets={}
for _,transaction in ipairs(monthly.transactions) do
  if transaction.name:find("Amazon Monatsausgleich",1,true)==1 then
    monthlyOffsets[transaction.name]=transaction
  end
end
assert(close(sum(monthly.transactions),0),"monthly offsets emitted transactions")
assert(close(monthlyOffsets["Amazon Monatsausgleich 2026-10"].amount,20),
  "monthly October nets purchase and refund")
assert(close(monthlyOffsets["Amazon Monatsausgleich 2026-09"].amount,19.99),
  "monthly September offsets the separate order")
assert(monthlyOffsets["Amazon Monatsausgleich 2026-10"].purpose
    :find("Monatsausgleich 2026-10 (Abruf ",1,true)==1,
  "monthly offset purpose includes its refresh timestamp")

local knownSourceTransactionId
local firstOctoberContraId
local knownMonthlyIds={}
for _,transaction in ipairs(monthly.transactions) do
  if transaction.endToEndReference=="303-1111111-1111111" then
    knownSourceTransactionId=knownSourceTransactionId or transaction.transactionId
    knownMonthlyIds[transaction.transactionId]=true
  end
  if transaction.name=="Amazon Monatsausgleich 2026-10" then
    firstOctoberContraId=transaction.transactionId
    knownMonthlyIds[transaction.transactionId]=true
  end
end
assert(type(knownSourceTransactionId)=="string",
  "monthly source transaction has a stable ID")
local monthlyReimport=refresh("monthly",function(id)
  if id==knownSourceTransactionId then
    return {transactionId=id}
  end
end)
assert(close(sum(monthlyReimport.transactions),0),
  "period offsets balance only source transactions not already imported")

-- A later refresh balances only newly emitted purchases for the same month.
local laterDate=os.time({year=2026,month=10,day=28,hour=12})
local laterOrderCode="303-4444444-4444444"
env.LocalStorage.OrderCache[laterOrderCode]={
  orderCode=laterOrderCode,
  accountNumber="Business",
  subAccountKind="business",
  orderPositions={{purpose="Item D",amount=750,qty=1}},
  orderSum=750,
  orderTotal=750,
  bookingDate=laterDate,
  detailsDate=os.time()+86400,
  detailsParsed=true,
}
local laterRefresh=env.RefreshAccount({
  accountNumber="test@example.com",
  owner="test@example.com",
  attributes={ledgerMode="monthly"},
},os.time()-7*86400,function(id)
  return knownMonthlyIds[id] and {transactionId=id} or nil
end)
local laterOctoberOffset
for _,transaction in ipairs(laterRefresh.transactions) do
  if transaction.name=="Amazon Monatsausgleich 2026-10" then
    laterOctoberOffset=transaction
  end
  assert(transaction.endToEndReference~="303-1111111-1111111",
    "previously imported source must not be returned again")
end
assert(laterOctoberOffset~=nil,"later refresh creates an offset for the new purchase")
assert(close(laterOctoberOffset.amount,7.5),
  "later refresh offsets only the newly emitted purchase")
assert(laterOctoberOffset.transactionId~=firstOctoberContraId,
  "later refresh offset ID differs from the already booked offset")

local monthlyResync=resync("monthly","monthly-resync")
assert(#monthlyResync.transactions>0,"monthly resync restores saved order transactions")
for _,transaction in ipairs(monthlyResync.transactions) do
  assert(transaction.name:find("Amazon Monatsausgleich",1,true)~=1,
    "monthly resync does not recreate period offsets")
end

local yearly=refresh("yearly")
assert(close(sum(yearly.transactions),0),"yearly offsets emitted transactions")
local yearOffsets=0
for _,transaction in ipairs(yearly.transactions) do
  if transaction.name=="Amazon Jahresausgleich 2026" then
    yearOffsets=yearOffsets+1
    assert(close(transaction.amount,39.99),"yearly offset amount")
  end
end
assert(yearOffsets==1,"yearly emits one offset per period")

-- MoneyMoney's duplicate check ignores order references and account numbers.
local duplicateDate=os.time({year=2026,month=10,day=5,hour=12})
local duplicateTransactions={
  {name="Item A",purpose="Item A",amount=-20,bookingDate=duplicateDate,
    endToEndReference="303-1111111-1111111",accountNumber="Business"},
  {name="Item A",purpose="Item A",amount=-20,bookingDate=duplicateDate,
    endToEndReference="303-2222222-2222222",accountNumber="Personal"},
}
local duplicateContext={transactions=duplicateTransactions,now=duplicateDate}
env.appendPeriodContraTransactions(duplicateContext,env.ledgerModeProfile("monthly"))
assert(#duplicateContext.transactions==2,
  "period calculation removes purchases MoneyMoney will deduplicate")
assert(close(sum(duplicateContext.transactions),0),
  "period offset balances the transaction MoneyMoney retains")
assert(close(duplicateContext.transactions[2].amount,20),
  "period offset counts the similar purchase only once")

-- Equal refunds emitted in separate batches need distinct, replayable contras.
local order={}
local code="303-3333333-3333333"
local date=os.time({year=2026,month=10,day=20,hour=12})
for index=1,2 do
  local ctx={accountNumber="test@example.com",transactions={
    {name="Refund "..index,amount=5,bookingDate=date,endToEndReference=code},
  }}
  env.appendOrderContraTransactions(ctx,order,code,1)
  env.rememberOrderTransactions(order,ctx.accountNumber,ctx.transactions,1,false)
end
local replay={}
assert(env.appendCachedOrderTransactions(replay,order,"test@example.com"))
assert(#replay==4,"snapshot retains both equal refund contras")
assert(not env.accountTransactionsEqual(replay[2],replay[4]),"contras have distinct identities")
assert(close(sum(replay),0),"replayed refunds remain balanced")
local purchase={name="Purchase",amount=-10,bookingDate=date,endToEndReference=code}
env.rememberOrderTransactions(order,"test@example.com",{purchase},1,false)
env.rememberOrderTransactions(order,"test@example.com",{purchase},1,false)
assert(#env.cachedOrderTransactionsForAccount(order,"test@example.com")==5,
  "reissued purchases still deduplicate")

env.resetAccountNoteSettings()
assert(env.defaultAccountAttributes().ledgerMode=="normal","default account note")
assert(env.isSupportedAccountAttributeKey("ledgerMode"),"ledgerMode is supported")

print("test_ledger_modes OK")
