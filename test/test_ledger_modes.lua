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
        {purpose="Item A",amount=1000,qty=2},
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

local function refresh(mode)
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
  },os.time()-7*86400,function() return nil end)
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
assert(monthlyOffsets["Amazon Monatsausgleich 2026-10"].purpose:find("Abruf",1,true),
  "monthly offset distinguishes refresh runs")

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

env.resetAccountNoteSettings()
assert(env.defaultAccountAttributes().ledgerMode=="normal","default account note")
assert(env.isSupportedAccountAttributeKey("ledgerMode"),"ledgerMode is supported")

print("test_ledger_modes OK")
