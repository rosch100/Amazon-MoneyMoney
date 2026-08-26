-- Amazon Plugin for https://moneymoney-app.com
--
-- Plugin Homepage https://github.com/Michael-Beutling/Amazon-MoneyMoney
--
-- Copyright 2019-2023 Michael Beutling

-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
-- (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify,
-- merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
-- BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
-- OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local connection=nil
local secPassword
local secUsername
local captcha1run
local mfa1run
local aName

--- @function rememberShopCredentials
-- In-memory login credentials for the current session (not persisted).
-- Used by auth_prompt during Amazon sub-account switch.
function rememberShopCredentials(username, password)
  if type(username) == 'string' then
    secUsername=username
  end
  if type(password) == 'string' then
    secPassword=password
  end
end
local html
local configDirty=false
local webCache=false
local webCacheFolder='webCache'
local webCacheHit=false
local webCacheState='start'
local invalidPrice=1e99
local invalidDate=1e99
local invalidQty=1e99
local cacheVersion=16
local debugBuffer={context=''}
local webCacheLastId=nil

local config={
  configOk=true,
  reallyLogout=true,
  cleanCookies=false,
  cleanOrdersCache=false,
  cleanFilterCache=false,
  cleanInvalidCache=false,
  noRefresh=false,
  debug=false,
  forceCaptcha=false,
  limitOrders=250,
  scanFiltersMonths=0,
  cookieLanguage='',
  rescanOrder='',
  blackListOrders='',
}

local const={
  regexOrderCodeNew="([D%d]%d%d%-%d%d%d%d%d%d%d%-%d%d%d%d%d%d%d)",
  regexPriceOld="EUR%s+(%d+),(%d%d)",
  regexPriceNew="€(%d+),(%d%d)",
  -- 2024+ layout writes the currency after the amount, e.g. "169,98€" / "0,00 €"
  regexPriceEur="(%d+),(%d%d)%s*€",
  -- order details page; the order code is appended. The legacy /gp/css/... paths
  -- 301-redirect here. Overridable via the orderDetailsUrl account-setting.
  orderDetailsUrl="/your-orders/order-details?orderID=",
  nameMaxLength=70,
  recentMonthsFilter="months-3",
  str2date = {
    Januar=1,
    January=1,
    Februar=2,
    February=2,
    ["März"]=3,
    March=3,
    April=4,
    Mai=5,
    May=5,
    Juni=6,
    June=6,
    Juli=7,
    July=7,
    August=8,
    September=9,
    Oktober=10,
    October=10,
    November=11,
    Dezember=12,
    December=12
  },
  domain='.amazon.de',
  services    = {"Amazon Orders"},
  description = "Give you an overview about your amazon orders.",
  contra="Amazon contra ",
  returnText="Returned item: ",
  returnTextContra="Amazon contra returned item: ",
  refundTransaction="Refund for order ",
  refundTransactionContra="Amazon contra refund for order ",
  fixEncoding='latin1',
  differenceText='Difference (shipping costs, coupon etc.)',
  xpathOrderHistoryLink='//a[@id="nav-orders" or contains(@href,"/order-history")]',
  xpathOrderMonthForm="//form[contains(@action,'order')][.//option]",
  xpathOrderMonthSelect='//select[@name="orderFilter" or @name="timeFilter"]',
  orderListLink='/gp/your-account/order-history?unifiedOrders=1',
  orderListLinkBusiness='/ab/your-orders',
  -- Retail-style list with explicit timeFilter (works for Business session without SPA XHR).
  yourOrdersTimeFilterPath='/your-orders/orders',
  yourOrdersTimeFilterRef='ppx_yo2ov_dt_b_filter_all',
  classicOrderFilterPath='/gp/your-account/order-history?unifiedOrders=1',
  -- Server-rendered order cards on Amazon Business (nav SPA link is AB shell).
  cssOrderHistoryPath='/gp/css/order-history',
  cssOrderHistoryRef='nav_orders_first',
  businessHomepageAfterSwitch='/gp/css/homepage.html?ref_=nav_youraccount_switchacct',
  abaLandingPath='/b2b/aba/',
  abaItemsReportPath='/b2b/aba/reports',
  abaRollupTablePath='/b2b/aba/ajax/v2/report/rollupTable',
  abaReportSchedulerPath='/b2b/aba/report/v2/scheduler',
  abaReportStatusPath='/b2b/aba/report/status/',
  abaGenerateDownloadLinksPath='/b2b/aba/ajax/generate-download-links',
  abaItemsReportType='items_report_1',
  abaReportRef='ab_ppx_hpr_redirect_report',
  abaPlaceholderOrderCode='700-5426221-4134938',
  abaReportPollAttempts=15,
  abaReportPollSleepSec=2,
  abaFullHarvestSpan='PAST_12_MONTHS',
  abaCustomRangeSpan='CUSTOM_RANGE',
  abaCoverageMonths=12,
  abaIncrementalMaxAgeSec=366 * 24 * 60 * 60,
  abaLandingMarkers={
    'reportType', 'items_report', 'dateSpanSelection',
    'Business Analytics', 'Geschäftsanalyse', 'Beschaffungsanalysen', 'dashboard',
  },
  abaCsvHeaders={
    'Bestellnummer', 'Order ID', 'Bestell-ID', 'Order Number', 'Amazon Order ID',
    'Bestellnummer ', 'Order Id',
  },
  monthlyContra="monthy contra",
  yearlyContra="yearly contra",
  daysByMonth={31,28,31,30,31,30,31,31,30,31,30,31}
}

function mergeConfig(default,read)
  for k,v in pairs(default) do
    if type(v) == 'table' then
      if type(read[k]) ~= 'table' then
        read[k] = {}
      end
      mergeConfig(v,read[k])
    else
      if type(read[k]) ~= 'nil'then
        if default[k]~=read[k] then
          default[k]=read[k]
          --print(k,'=',read[k])
        end
      else
        configDirty=true
      end
    end
  end
end


local configFileName='amazon_orders.json'

-- run every time which plug in is loaded
local configFile=nil
-- io=nil
-- io.open=nil
-- signed version has no io.open functions
if io ~= nil and io.open ~= nil then
  configFile=io.open(configFileName,"rb")
end

if configFile~=nil then
  local configJson=configFile:read('*all')
  --print(configJson)
  local configTemp=JSON(configJson):dictionary()
  if configTemp['configOk'] then
    configDirty=false
    mergeConfig(config,configTemp)
    print('config read...')
  end
  io.close(configFile)
else
  configDirty=true
end


function clearOrderFilterCaches()
  LocalStorage.orderFilterCache=nil
  LocalStorage.orderFilterCacheByAccount={}
end

function orderHasPositions(order)
  if type(order) ~= 'table' or type(order.orderPositions) ~= 'table' then
    return false
  end
  for _ in pairs(order.orderPositions) do
    return true
  end
  return false
end

-- Marks already-detailed orders so MoneyMoney does not re-import them after the
-- name/purpose field layout change (name was Bestellnr, now Artikel).
-- Matching for new bookings: purpose (Artikel) + amount + bookingDate; Bestellnr in endToEndReference.
-- Also stamps refundTransactions: a later details parse must not emit
-- "Refund for order" when purchase+Amazon contra were already booked.
function suppressRefundReemit(order)
  if type(order) ~= 'table' or type(order.refundTransactions) ~= 'table' then
    return 0
  end
  local n=0
  for _,byAmount in pairs(order.refundTransactions) do
    if type(byAmount) == 'table' then
      for _,leaf in pairs(byAmount) do
        if type(leaf) == 'table' then
          leaf.since=0
          n=n+1
        end
      end
    end
  end
  return n
end

function suppressReemitForDetailedOrders(orderCache)
  if type(orderCache) ~= 'table' then
    return 0
  end
  local n=0
  for _,order in pairs(orderCache) do
    if orderHasPositions(order) then
      order.since=0
      suppressRefundReemit(order)
      n=n+1
    end
  end
  return n
end

--- @function shouldSuppressFullRefundReimport
-- Mixed mode already booked purchase + "Amazon contra <order>" for the order.
-- Re-parsing details later finds "Summe der Erstattung" and would emit
-- "Refund for order" / "Amazon contra refund for order" — MoneyMoney does not
-- match those names to the existing pair, causing duplicates.
-- Suppress only full refunds on orders reported in a prior sync (order.since < since).
-- Partial refunds are intentionally not suppressed: matching purchase+contra pairs by
-- amount is ambiguous; users may still see duplicate partial-refund lines until matched manually.
function shouldSuppressFullRefundReimport(order, amount, accountSince, mixed)
  if not mixed then
    return false
  end
  if type(order) ~= 'table' or type(amount) ~= 'number' then
    return false
  end
  if type(order.since) ~= 'number' or type(accountSince) ~= 'number' then
    return false
  end
  if not (order.since < accountSince) then
    return false
  end
  local total=tonumber(order.orderTotal)
  if total == nil or total <= 0 then
    return false
  end
  return amount >= total
end

--- @function registerRefundTransaction
-- Stores refundTransactions[bookingDate][amount]. When the order was already
-- reported and this is a new full-refund leaf, stamp since=0 immediately.
function registerRefundTransaction(order, bookingDate, amount)
  if type(order) ~= 'table' or type(bookingDate) ~= 'number' or type(amount) ~= 'number' then
    return
  end
  local existed=type(order.refundTransactions) == 'table'
    and type(order.refundTransactions[bookingDate]) == 'table'
    and type(order.refundTransactions[bookingDate][amount]) == 'table'
  makeBranch(order, {'refundTransactions', bookingDate, amount})
  local leaf=order.refundTransactions[bookingDate][amount]
  if type(leaf) ~= 'table' or leaf.since ~= nil or existed then
    return
  end
  local total=tonumber(order.orderTotal)
  if type(order.since) == 'number' and total ~= nil and total > 0 and amount >= total then
    leaf.since=0
  end
end

-- Legacy: Lieferadresse lived in order.endToEndReference; MoneyMoney "Referenz"
-- is endToEndReference and must carry the Bestellnummer instead.
function migrateShippingAddressFromLegacy(orderCache)
  if type(orderCache) ~= 'table' then
    return 0
  end
  local n=0
  for orderCode,order in pairs(orderCache) do
    if type(order) == 'table' then
      local legacy=order.endToEndReference
      if (order.shippingAddress == nil or order.shippingAddress == '')
          and type(legacy) == 'string' and legacy ~= ''
          and legacy ~= orderCode and legacy ~= order.orderCode then
        order.shippingAddress=legacy
        n=n+1
      end
      order.endToEndReference=nil
    end
  end
  return n
end

if LocalStorage ~=nil then
  if LocalStorage.cacheVersion ~= cacheVersion then
    configDirty=true
    -- Keep OrderCache: wiping it re-emits booked transactions and risks MoneyMoney duplicates
    -- when name/purpose mapping changes. Only reset filter completion markers.
    print("migrate filter caches (keep OrderCache)...")
    clearOrderFilterCaches()
    local moved=migrateShippingAddressFromLegacy(LocalStorage.OrderCache)
    if moved > 0 then
      print("migrated shippingAddress from legacy endToEndReference for", moved, "orders")
    end
    local suppressed=suppressReemitForDetailedOrders(LocalStorage.OrderCache)
    if suppressed > 0 then
      print("suppressed re-emit for", suppressed, "already-detailed orders after name/purpose layout change")
      LocalStorage.txLayoutNotice=true
    end
    LocalStorage.cacheVersion = cacheVersion
  end

  if config.cleanOrdersCache and LocalStorage ~=nil then
    config.cleanOrdersCache=false
    configDirty=true
    print("clean orders cache...")
    LocalStorage.OrderCache={}
  end

  if config.cleanFilterCache  then
    config.cleanFilterCache=false
    configDirty=true
    print("clean filter cache...")
    clearOrderFilterCaches()
  end

  if config.cleanInvalidCache  then
    config.cleanInvalidCache=false
    configDirty=true
    print("clean invalid cache...")
    LocalStorage.invalidCache={}
  end

  if config.cleanCookies then
    config.cleanCookies=false
    configDirty=true
    print("clean cookies...")
    LocalStorage.cookies=nil
  end

end

if configDirty and io ~= nil and io.open ~= nil then
  print('write config...')
  configFile=io.open(configFileName,"wb")
  configFile:write(JSON():set(config):json())
  io.close(configFile)
end

print(((io == nil or io.open == nil) and 'signed ' or '')  .. const.services[1],"plugin loaded...")
if config.debug then print('debugging...') end
if debug ~= nil then
  print("lua debug is usable")
end
local baseurl='https://www'..const.domain

-- NOTE: version must be a Lua number (no letters). To mark this as an
-- unofficial build the "(beta)" tag is added to the description instead.
WebBanking{version  = 1.66,
  url         = baseurl,
  services    = const.services,
  description = const.description.." (beta)"}

function debugBuffer.tablePrint(tbl)
  local t={}
  for k,v in pairs(tbl) do
    if type(v)=='table' then
      table.insert(t,k.."(#table)={"..debugBuffer.tablePrint(v).."}")
    else
      table.insert(t,k.."#"..type(v).."='"..tostring(v).."'")
    end
  end
  return table.concat(t,",")
end

function debugBuffer.print(...)
  if debugBuffer.context == nil then
    debugBuffer.context=''
  end
  --local args={debugBuffer.getStack(),debugBuffer.context}
  local args={debugBuffer.context}
  for _,v in pairs({...}) do
    local n
    if type(v)=='table' then
      n=type(v).."='"..debugBuffer.tablePrint(v).."'"
    else
      n=type(v).."='"..tostring(v).."'"
    end
    table.insert(args,n)
  end
  table.insert(debugBuffer,table.concat(args," "))
end

function debugBuffer.getStack(skip)
  local stack={}
  if skip== nil then
    skip=3
  end
  while debug.getinfo(skip) ~= nil do
    table.insert(stack,debug.getinfo(skip).name)
    skip=skip+1
  end

  return(table.concat(stack,"#"))
end

function debugBuffer.flush()
  if io ~= nil and config.debug then
    local debugFile=io.open("amazon-debug.log","a")
    if debugFile ~= nil then
      for i,v in ipairs(debugBuffer) do
        debugFile:write(v.."\n")
        debugBuffer[i]=nil
      end
      debugFile:close()
    end
  end
  for i,v in ipairs(debugBuffer) do
    print(v)
    debugBuffer[i]=nil
  end

end

function removeWebCacheLastItem()
  if webCache then
    os.remove(webCacheFolder..'/'..webCacheLastId..'.html')
    os.remove(webCacheFolder..'/'..webCacheLastId..'.json')
    print("remove",webCacheLastId,"from webCache")
  end
end

function connectShop(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  return HTML(connectShopRaw(method, url, postContent, postContentType, headers))
end

function connectShopJson(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  headers={["X-Requested-With"]="XMLHttpRequest" }
  return JSON(connectShopRaw(method, url, postContent, postContentType, headers)):dictionary()
end

function connectShopRaw(method, url, postContent, postContentType, headers)
  -- postContentType=postContentType or "application/json"
  if headers == nil then
    headers={
      --["DNT"]="1",
      --["Upgrade-Insecure-Requests"]="1",
      --["Connection"]="close",
      --["Accept"]="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      }
  end

  if method == 'POST' then
    if config.debug then
      for i in string.gmatch(postContent, "([^&]+)") do
        print("post='"..i.."'")
      end
    end
  end

  if connection == nil then
    connection = Connection()
    --connection.useragent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:66.0) Gecko/20100101 Firefox/66.0"

    local status,err = pcall( function()
      for i in string.gmatch(LocalStorage.cookies, '([^; ]+)') do
        if  i:sub(1, #'ap-fid=') ~= 'ap-fid=' and i:sub(-#'=deleted') ~= '=deleted' then
          -- print("keep cookie:"..i)
          connection:setCookie(i..'; Domain='..const.domain..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
        else
        -- print("suppress cockie:"..i)
        end
      end
    end) --pcall
  end

  local cached=false
  local content, charset, mimeType, filename, headers
  local writeCache=false
  if webCache then
    writeCache=true
    webCacheLastId=MM.md5(tostring(method)..tostring(url)..tostring(postContent)..tostring(postContentType)..tostring(headers)..webCacheState)
    local webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.json','rb')
    if webFile then
      local metaJSON=webFile:read('*all')
      local meta=JSON(metaJSON):dictionary()
      webFile:close()
      webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.html','rb')
      if webFile then
        content=webFile:read('*all')
        webFile:close()
        charset=meta['charset']
        mimeType=meta['mimeType']
        filename=meta['filename']
        headers=meta['headers']
        cached=true
        print("webCache id="..webCacheLastId.." read.")
        webCacheHit=true
      end
      writeCache=false
    end
    if not cached and webCacheHit then
      error('webCache error!')
    end

  end

  if not cached then
    -- issue #28
    if LocalStorage.patcher and LocalStorage.patcher.cookieLanguage then
      connection:setCookie('lc-acbde='..LocalStorage.patcher.cookieLanguage..'; Domain='..const.domain..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
    else
      connection:setCookie('lc-acbde=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    end
    content, charset, mimeType, filename, headers = connection:request(method, url, postContent, postContentType, headers)
    if writeCache then
      local webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.json',"wb")
      webFile:write(JSON():set({
        charset=charset,
        mimeType=mimeType,
        filename=filename,
        headers=headers,
        request={
          method=method,
          url=url,
          postContent=postContent,
          postContentType=postContentType,
          headers=headers,
        },
        webCacheState=webCacheState,
      }):json())
      webFile:close()
      webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.html',"wb")
      webFile:write(content)
      webFile:close()
      print("webCache id="..webCacheLastId.." written.")
    end
  end

  if not cached and baseurl == connection:getBaseURL():lower():sub(1,#baseurl)  then
    -- work around for deleted cookies, prevent captcha
    connection:setCookie('a-ogbcbff=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    connection:setCookie('ap-fid=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/ap/; Secure')
    -- issue #28
    connection:setCookie('lc-acbde=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')

    if config.debug then
      if LocalStorage.cookies~=connection:getCookies() then
        print("store cookies=",connection:getCookies())
      end
    end

    for i in string.gmatch(connection:getCookies(), '([^; ]+)') do
      if  i:sub(1, #'ap-fid=') == 'ap-fid=' or i:sub(-#'=deleted') == '=deleted' then
        error("unwanted cockie:"..i)
      end
    end
    LocalStorage.cookies=connection:getCookies()
  else
  -- if config.debug then print("skip cookie saving") end
  end

  return content,charset
end

local RegressionTest={}


function RegressionTest.getKey(transaction)
    local sortedKeys={}
    for k,v in pairs(transaction) do
      table.insert(sortedKeys,k)
    end
    table.sort(sortedKeys)
    local key=""
    
    for _,k in ipairs(sortedKeys) do
      --key=key..k.."="..MM.base64(transaction[k].." ")
      key=key..k.."="..MM.toEncoding(const.fixEncoding,transaction[k]).." "
    end
  return key
end

function RegressionTest.makeKeys(transactions)
  local keys={}
  for _,transaction in pairs(transactions) do
    
    keys[RegressionTest.getKey(transaction)]=true
    
  end
  
  return keys
end


function RegressionTest.compareTransactions(now,master,differences,text)
  local keys=RegressionTest.makeKeys(now)
  for _,transaction in pairs(master) do
    local key=RegressionTest.getKey(transaction)
    
    if keys[key] ~= true then
      local diff={}
      for k,v in pairs(transaction) do
        diff[k]=v
      end
      diff.name=diff.name.." "..text
      diff.amount=tonumber(diff.amount)
      diff.purpose=diff.purpose.."\n"..MM.base64(key)
      table.insert(differences,diff)
    end
  end
  
  return differences
end

function RegressionTest.run(transactions,regTestPre)
  if io ~= nil then
    local transFile=io.open(regTestPre.."_transactions_master.json",'rb')
    if transFile ~= nil then

      debugBuffer.print("run regression test")

      local master=JSON(transFile:read('*all')):dictionary()
      transFile.close()

      for _,v in pairs(transactions) do
        v.amount=tostring(v.amount)
      end
      local transFile=io.open(regTestPre.."_transactions.json","wb")
      transFile:write(JSON():set(transactions):json())
      transFile.close()

      local differences={}

      RegressionTest.compareTransactions(transactions,master,differences,"master")
      RegressionTest.compareTransactions(master,transactions,differences,"now")
      
      local count = #transactions
      local i
      for i=0, count do transactions[i]=nil end
      for _,v in pairs(differences) do
        table.insert(transactions,v)
      end

      debugBuffer.print("regression test finish")
      table.insert(transactions,{
        name="regression test finish",
        amount = #differences,
        bookingDate = os.time(),
        purpose = 'run '..LocalStorage.loginCounter,
        booked = false,
        accountNumber='accountNumber',
        bankCode='bankCode',
        bookingText='bookingText',
        endToEndReference='endToEndReference',
        mandateReference='mandateReference',
        creditorId='creditorId',
        returnReason='returnReason',
      --comment='comment\ncomment\n',
      --category="test"
      })
    end
  end
  debugBuffer.print(transactions)
  debugBuffer.flush()
end

function connectShopWithCheck(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  local html=HTML(connectShopRaw(method, url, postContent, postContentType, headers))
  local xpform='//form[@name="signIn"]'
  if html:xpath(xpform):attr("name") ~= '' then
    removeWebCacheLastItem()
    print("Forced log out detect, enter username/password")
    html:xpath('//*[@name="email"]'):attr("value", secUsername)
    html:xpath('//*[@name="password"]'):attr("value",secPassword)
    html= connectShop(html:xpath(xpform):submit())
  end
  return html
end

function getDate(text)
  if type(text)~='string' then
    return invalidDate
  end
  local day,month,year=string.match(text,"(%d+)%.%s+([%S]+)%s+(%d+)")
  if day == nil then
    day,month,year=string.match(text,"(%d+)%s+([%S]+)%s+(%d+)")
  end
  local month=const.str2date[month]
  if month ~= nil then
    return os.time({year=year,month=month,day=day})
  end
  --error(text)
  return invalidDate -- error value
end

function getPrice(text)
  if type(text)~='string' then
    return invalidPrice
  end
  -- normalize non-breaking spaces (UTF-8 \194\160 and latin1 \160) to plain
  -- spaces so "%s" matches between amount and currency, then drop thousands dots
  local stripped=text:gsub("\194\160"," "):gsub("\160"," "):gsub("%.","")
  local amountHigh,amountLow=string.match(stripped,const.regexPriceEur)
  if amountHigh == nil or amountLow == nil then
    amountHigh,amountLow=string.match(stripped,const.regexPriceNew)
  end
  if amountHigh == nil or amountLow == nil then
    amountHigh,amountLow=string.match(stripped,const.regexPriceOld)
  end
  --debugBuffer.print(text,amountHigh,amountLow)
  if amountHigh == nil or amountLow == nil then
    return invalidPrice
  end
  return amountHigh*100+amountLow
end

function getQty(text)
  if type(text)~='string' then
    return invalidQty
  end
  local qty=tonumber(text)
  if qty>0 then
    return qty
  end
  return invalidQty
end

function trim(text)
  if type(text)~='string' then
    return ''
  end
  return (text:gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' '))
end

-- 2024+ detail layout: the quantity component is empty for single items and
-- holds a number (or "Menge: n") otherwise.
function getQtyNew(text)
  local n=tonumber((text or ''):match('%d+'))
  if n ~= nil and n > 0 then
    return n
  end
  return 1
end

function buildDetailsUrl(orderCode)
  return const.orderDetailsUrl..orderCode
end

function getQtyFromElement(element)
  local qty=1
  if nodeExists(element,'.//span[contains(@class,"item-view-qty")]') then
    qty=getQty(element:xpath('.//span[contains(@class,"item-view-qty")]'):text())
  end
  return qty
end

function getOrderCode(text)
  if type(text)~='string' then
    return nil
  end
  local orderCode=string.match(text,const.regexOrderCodeNew)
  return orderCode
end

function nodeExists(element,xpath)
  return element:xpath(xpath)[1] ~= nil
end

function getLastElementText(html,...)
  local elements=html:xpath(table.concat({...}))
  if elements:length() == 0 then
    return ''
  end
  return elements:get(elements:length()):text()
end

function getOrderInfosFromSummaryHeader(orderInfo,order)
  if orderInfo:text() == "" then
    return false
  end

  local headData={}

  orderInfo:xpath('.//span[contains(@class,"a-color-secondary") and contains(@class,"value")]'):each(function(index,element)
    headData[index]=element:text()
  end)

  if #headData == 3 then
    -- customer account
    order.orderCode=getOrderCode(headData[3])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.orderTotal=getPrice(headData[2])
  elseif #headData == 4 then
    -- business account
    order.orderCode=getOrderCode(headData[4])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.accountNumber=headData[2]
    order.orderTotal=getPrice(headData[3])
  elseif #headData == 5 then
    -- business account
    order.orderCode=getOrderCode(headData[5])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.accountNumber=headData[2]
    order.bookingText=headData[4]
    order.orderTotal=getPrice(headData[3])
  else
    debugBuffer.print("unkown elements",table.concat(headData,"#"))
    return false
  end

  -- only business accounts: who placed the order (not MoneyMoney Referenz)
  local placedBy=orderInfo:xpath('.//div[contains(@class,"placed-by")]//span[contains(@class,"trigger-text")]'):text()
  if placedBy ~= '' then
    order.placedBy=placedBy
  end

  if order.bookingDate == invalidDate then
    debugBuffer.print("getOrderInfosFromSummaryHeader invalidDate")
    order.orderCode=nil
  end

  if order.orderTotal == invalidPrice then
    debugBuffer.print("getOrderInfosFromSummaryHeader invalidPrice")
    order.orderCode=nil
  end

  order.detailsUrl=orderInfo:xpath('.//a[contains(@class,"a-link-normal") and contains(@href,"/order-details/")]'):attr('href')
  if order.detailsUrl == "" then
    order.digitalUrl=orderInfo:xpath('.//a[contains(@class,"a-link-normal") and contains(@href,"/digital/")]'):attr('href')
    if order.digitalUrl == "" then
      debugBuffer.print("getOrderInfosFromSummaryHeader nodetails")
      order.orderCode=nil
    end
  end

  return order.orderCode ~= nil
end

function isShipmentShorted(shipment)
  return shipment:xpath('.//a[contains(@href,"/order-details/")]'):length() ~= 0
end

--- @type orderPosition
-- @field purpose
-- @field amount
-- @field qty

--- @type order
-- @field #string orderCode
-- @field #number totalSum
-- @field #number orderTotal   total from header
-- @field #number refund       sum of refund from header
-- @field #number bookingDate  date of order
-- @field #string detailsUrl
-- @field #string digitalUrl
-- @field #list<#orderPosition> orderPositions
-- @field #boolean invalidArticles
-- @field #number detailsDate
-- @field #string accountNumber  Amazon-Unterkonto (persönlich / Firma)
-- @field #string shippingAddress  Lieferadresse (auch in purpose)
-- @field #string mandateReference  payment method (Zahlungsart)

--- @function utf8CharLen
-- Length in bytes of the UTF-8 character starting at index i, or nil if invalid.
function utf8CharLen(text, i)
  local c=text:byte(i)
  if c == nil then
    return nil
  end
  if c < 0x80 then
    return 1
  end
  if c < 0xC0 then
    return nil
  end
  local len
  if c < 0xE0 then
    len=2
  elseif c < 0xF0 then
    len=3
  elseif c < 0xF8 then
    len=4
  else
    return nil
  end
  if i + len - 1 > #text then
    return nil
  end
  for j=1,len-1 do
    local b=text:byte(i+j)
    if b == nil or b < 0x80 or b >= 0xC0 then
      return nil
    end
  end
  return len
end

--- @function utf8Step
-- Byte length of one UTF-8 character at i (invalid byte => 1).
function utf8Step(text, i)
  return utf8CharLen(text, i) or 1
end

--- @function utf8Len
-- Counts UTF-8 characters (not bytes). Treats invalid bytes as one character each.
function utf8Len(text)
  if type(text) ~= 'string' then
    return 0
  end
  local n=0
  local i=1
  while i <= #text do
    i=i+utf8Step(text, i)
    n=n+1
  end
  return n
end

--- @function truncateUtf8
-- Truncates to at most maxChars UTF-8 characters (no ellipsis). Single pass.
function truncateUtf8(text, maxChars)
  if type(text) ~= 'string' then
    return text
  end
  maxChars=tonumber(maxChars) or 0
  if maxChars <= 0 then
    return text
  end
  local n=0
  local i=1
  while i <= #text do
    if n >= maxChars then
      return text:sub(1, i-1)
    end
    i=i+utf8Step(text, i)
    n=n+1
  end
  return text
end

--- @function makeAccountTransaction
-- Maps plugin fields onto MoneyMoney transaction fields:
-- name = Artikelbezeichnung truncated to const.nameMaxLength,
-- purpose = full Artikelbezeichnung,
-- endToEndReference = Bestellnummer (MoneyMoney UI "Referenz"),
-- bookingText = Lieferadresse (MoneyMoney UI "Umsatzart", visible in list line),
-- batchReference = Lieferadresse (Sammlerreferenz),
-- mandateReference = Zahlungsart,
-- accountNumber = Amazon-Unterkonto.
function encodeFormText(text)
  -- MoneyMoney expects latin1 form fields; const.fixEncoding is the SSOT
  -- (never pass nil — MM.toEncoding(nil, …) aborts the host with signal 11).
  return MM.toEncoding(const.fixEncoding, text)
end

function makeAccountTransaction(order, orderCode, name, amount, bookingDate, purpose)
  local fullName=name or ""
  local shortName=truncateUtf8(fullName, const.nameMaxLength)
  local purposeText=firstNonEmpty(purpose, fullName)
  local tx={
    name=encodeFormText(shortName),
    amount=amount,
    bookingDate=bookingDate,
    endToEndReference=orderCode,
    accountNumber=order.accountNumber,
    mandateReference=order.mandateReference,
  }
  if purposeText ~= '' then
    tx.purpose=encodeFormText(purposeText)
  end
  local addr=order.shippingAddress
  if type(addr) == 'string' and addr ~= '' then
    local encodedAddr=encodeFormText(addr)
    tx.bookingText=encodedAddr
    tx.batchReference=encodedAddr
  elseif type(order.bookingText) == 'string' and order.bookingText ~= '' then
    tx.bookingText=encodeFormText(order.bookingText)
  end
  return tx
end

-- @field  #number orderTotal Sum of order showed by Amazon
-- @field  #number refund amount of refund showed by Amazon

--- @function  getTotalsFromDetails
-- @return #totals
--


function getTotalsFromDetails(orderDetails)
  local totals={orderTotal=invalidPrice,refund=0} --#totals

  -- 2024+ layout: order summary is a list of "od-line-item-row" rows; the grand
  -- total ("Gesamtsumme") is the bold row. Anchor on the label, fall back to the
  -- last bold row so we stay robust to localized wording.
  local labelTotal=invalidPrice
  local lastBold=invalidPrice
  orderDetails:xpath('.//div[contains(@class,"od-line-item-row")]'):each(function(index,row)
    local label=row:xpath('.//*[contains(@class,"od-line-item-row-label")]'):text()
    local value=getPrice(row:xpath('.//*[contains(@class,"od-line-item-row-content")]'):text())
    if value ~= invalidPrice and not label:find("Erstattung") then
      if label:find("Gesamtsumme") or label:find("Grand Total") then
        labelTotal=value
      end
      if row:xpath('.//*[contains(@class,"a-text-bold")]'):length() > 0 then
        lastBold=value
      end
    end
  end)
  if labelTotal ~= invalidPrice then
    totals.orderTotal=labelTotal
  elseif lastBold ~= invalidPrice then
    totals.orderTotal=lastBold
  end

  return totals

end

--- @function getPositionsFromDetails
-- 2024+ layout: each purchased item is a "purchasedItemsRightGrid" block holding
-- data-component itemTitle / unitPrice / quantity. Fills order.orderPositions
-- and order.orderSum.
-- @param #table orderDetails
-- @param #order order
function getPositionsFromDetails(orderDetails,order)
  order.orderPositions={}
  order.orderSum=0
  orderDetails:xpath('.//*[@data-component="purchasedItemsRightGrid"]'):each(function(index,item)
    local purpose=trim(item:xpath('.//*[@data-component="itemTitle"]'):text())
    local priceText=item:xpath('.//*[@data-component="unitPrice"]//*[contains(@class,"a-offscreen")]'):text()
    if priceText == '' then
      priceText=item:xpath('.//*[@data-component="unitPrice"]'):text()
    end
    local amount=getPrice(priceText)
    -- quantity (>1) is shown as a badge over the item image (od-item-view-qty)
    -- in the enclosing item container, NOT in the (empty) quantity component.
    local qtyText=item:xpath('ancestor::div[contains(concat(" ",normalize-space(@class)," ")," a-fixed-left-grid-inner ")][1]//div[contains(@class,"od-item-view-qty")]'):text()
    if qtyText == '' then
      qtyText=item:xpath('.//*[@data-component="quantity"]'):text()
    end
    local qty=getQtyNew(qtyText)
    if purpose ~= '' and amount ~= invalidPrice then
      table.insert(order.orderPositions,{purpose=purpose,amount=amount,qty=qty})
      order.orderSum=order.orderSum+amount*qty
    else
      order.invalidArticles=true
      --debugBuffer.print("invalid article",order.orderCode,purpose,amount,qty)
    end
  end)
end

--- @function  getArticleFromShipment
-- @param #string shipment
-- @param #order order
-- @param #boolean doInsert
-- @return
function getArticleFromShipment(shipment,order,doInsert)
  doInsert=doInsert ~= false

  local refund=invalidPrice
  local refundText=shipment:xpath('.//div[contains(@class,"actions")]'):text()
  if refundText ~=""then
    refund=getPrice(refundText)
    --debugBuffer.print("action",order.orderCode,doInsert,refund)
  end

  shipment:xpath('.//div[contains(@class,"a-fixed-left-grid-inner")]'):each(function(index,article)
    local purpose
    local amount=invalidPrice
    local qty=getQtyFromElement(article)
    article:xpath('.//div[contains(@class,"a-row")]'):each(function(index,row)
      if purpose==nil then
        purpose=row:text()
      else
        local price=getPrice(row:text())
        if price~=invalidPrice and amount == invalidPrice then
          amount=price
        end
      end
    end) -- row
    if order.digitalUrl ~= nil then
      amount=order.orderTotal
      --debugBuffer.print(amount,purpose,qty)
    end
    if purpose~= nil and amount ~=invalidPrice and qty~= invalidQty then
      if doInsert then
        table.insert(order.orderPositions,{purpose=purpose,amount=amount,qty=qty})
        order.orderSum=order.orderSum+amount*qty
      end
      if refund~=invalidPrice then
        order.orderPositions[#order.orderPositions].refund=refund
        refund=invalidPrice
        --debugBuffer.print("refunded",order)
      end
    else
      order.invalidArticles=true
      --debugBuffer.print("invalid article",order.orderCode,amount,qty)
    end
  end) -- article
end

--- @function makeBranch
-- @param #map tree
-- @param #list branch
-- @return #map


function makeBranch(tree,branch)
  local temp=tree
  for _,v in ipairs(branch) do
    if temp[v] == nil then
      temp[v]={}
    end
    temp=temp[v]
  end
  return temp
end

--- @type returned
--  @field #number amount
--  @number #number bookingDate

--- @function getReturnsFromDetails
-- @param #table orderDetails
-- @param #order order
-- @return

function getReturnsFromDetails(orderDetails,order)
  orderDetails:xpath('//div[contains(@id,"od-returns-panel")]//div[contains(@class,"a-box-inner")]'):each(function(index,returnedShipments)
    -- debugBuffer.print(order.orderCode)
    local bookingDate=getDate(returnedShipments:xpath('.//div[@class="a-row a-spacing-base"]'):text())

    if bookingDate ~= invalidDate then
      returnedShipments:xpath('.//div[contains(@class,"a-row")and contains(@class,"a-spacing-mini")]'):each(function(index,returnedItems)
        local purpose
        local amount=invalidPrice
        returnedItems:xpath('.//div[contains(@class,"a-row")]'):each(function(index,row)
          if purpose==nil then
            purpose=row:text()
          else
            local price=getPrice(row:text())
            if price~=invalidPrice then
              amount=price
            end
          end
        end) -- row
        if amount ~=invalidPrice and bookingDate ~=invalidDate then
          makeBranch(order,{'returns',bookingDate,amount,purpose})
          -- debugBuffer.print(order.returns)
        end
      end)
    end
  end)
  return
end

--- @function getRefundTransActions
-- @param  #table orderDetails
-- @param #order order
-- @return
--
function getRefundTransActions(orderDetails,order)
  orderDetails:xpath('.//div[contains(@class,"a-box") and contains(@class,"a-last")]//div[contains(@class,"a-row") and contains(@class,"a-color-success")]'):each(function(index,transaction)
    local bookingDate=getDate(transaction:text())
    local amount=getPrice(transaction:text())
    if bookingDate ~= invalidDate and amount ~= invalidPrice  then
      registerRefundTransaction(order, bookingDate, amount)
    end
  end)
  return
end

--- @function getRefundFromDetails
-- 2024+ layout: a refunded/returned order keeps all items in the order summary
-- and adds a "Summe der Erstattung" row with the refunded amount. There is no
-- refund date in the DOM, so we book it on the order date (best available).
-- @param #table orderDetails
-- @param #order order
function getRefundFromDetails(orderDetails,order)
  local bookingDate=order.bookingDate
  if bookingDate == nil or bookingDate == invalidDate then
    bookingDate=os.time()
  end
  orderDetails:xpath('.//div[contains(@class,"od-line-item-row")][.//*[contains(@class,"od-line-item-row-label")]]'):each(function(index,row)
    local label=row:xpath('.//*[contains(@class,"od-line-item-row-label")]'):text()
    if label:find("Erstattung") then
      local amount=getPrice(row:xpath('.//*[contains(@class,"od-line-item-row-content")]'):text())
      if amount ~= invalidPrice and amount > 0 then
        registerRefundTransaction(order, bookingDate, amount)
        --debugBuffer.print("refund",order.orderCode,amount)
      end
    end
  end)
  return
end


--- @function getPaymentMethod
-- Zahlungsart from the 2024+ order-details payment widget.
-- @return #string|nil e.g. "MasterCard •••• 2022"
function getPaymentMethod(orderDetails)
  local name=trim(orderDetails:xpath('.//*[@data-testid="payment-instrument-name"]'):text())
  if name == '' then
    return nil
  end
  local parts={name}
  local prefix=trim(orderDetails:xpath('.//*[@data-testid="payment-instrument-prefix"]'):text())
  local number=trim(orderDetails:xpath('.//*[@data-testid="payment-instrument-number"]'):text())
  if prefix ~= '' then
    table.insert(parts, prefix)
  end
  if number ~= '' then
    table.insert(parts, number)
  end
  return table.concat(parts, " ")
end

--- @function getOrderaddress
-- @param #table html
-- @param #order order
-- @return
--

function getOrderaddress(orderDetails,order)
  if type(order.shippingAddress) == 'string' and order.shippingAddress ~= '' then
    return
  end
  -- 2024+ layout: shippingAddress component, address split over <li> items.
  local parts={}
  orderDetails:xpath('.//*[@data-component="shippingAddress"]//li'):each(function(index,li)
    local t=trim(li:text())
    if t ~= '' then
      table.insert(parts,t)
    end
  end)
  if #parts == 0 then
    -- legacy layout fallback
    local name=orderDetails:xpath('//div[contains(@class,"od-shipping-address-container")]//div[@class="a-row"]'):text()
    local address=orderDetails:xpath('//div[contains(@class,"od-shipping-address-container")]//div[@class="displayAddressDiv"]'):text()
    if name ~= '' then table.insert(parts,trim(name)) end
    if address ~= '' then table.insert(parts,trim(address)) end
  end
  if #parts > 0 then
    order.shippingAddress=table.concat(parts," ")
  end
end

--- @function getOrderDetails
-- Fetches and parses an order's "Bestelldetails" page (2024+ layout). The order
-- list no longer exposes per-order data (the cards are client-side encrypted),
-- so the details page is the source of truth for date, total, items and address.
-- @param #order order
-- @return
--
function getOrderDetails(order)
  debugBuffer.context=order.orderCode
  if order.detailsUrl == nil or order.detailsUrl == "" then
    order.detailsUrl=buildDetailsUrl(order.orderCode)
  end
  local html=connectShopWithCheck("GET",order.detailsUrl)
  local orderDetails=html:xpath('//div[contains(@id,"orderDetails")]')
  if orderDetails:text() ~= "" then
    local date=getDate(orderDetails:xpath('.//*[@data-component="orderDate"]'):text())
    if date ~= invalidDate then
      order.bookingDate=date
    end

    local totals=getTotalsFromDetails(orderDetails)
    if totals.orderTotal ~= invalidPrice then
      order.orderTotal=totals.orderTotal
    end
    order.refund=totals.refund

    getPositionsFromDetails(orderDetails,order)
    if order.invalidArticles ~= nil then
      order.orderPositions={}
      order.orderSum=0
      order.invalidArticles=nil
    end

    getRefundFromDetails(orderDetails,order)
    getOrderaddress(orderDetails,order)
    order.mandateReference=getPaymentMethod(orderDetails)
    order.detailsDate=os.time()+math.floor((math.random()*90+90)*24*60*60) -- distribute rescans randomly in future
  else
    debugBuffer.print("getOrderDetails no details",order.orderCode)
  end
  debugBuffer.context=''
end

--- @function getOrdersFromSummary
-- 2024+ layout: order cards (div.order-card) carry the order code in their
-- data-csa-c-slot-id attribute even though the card body is encrypted. We only
-- enumerate the codes here; getOrderDetails fills in everything else.
function getOrdersFromSummary(html)
  local orders={}
  if html == nil then
    return orders
  end
  html:xpath('//div[contains(@class,"order-card")]'):each(function(index,card)
    local orderCode=getOrderCode(card:attr("data-csa-c-slot-id"))
    if orderCode == nil then
      orderCode=getOrderCode(card:html())
    end
    if orderCode ~= nil and orders[orderCode] == nil then
      orders[orderCode]={
        orderCode=orderCode,
        orderPositions={},
        orderSum=0,
        orderTotal=0,
        refund=0,
        bookingDate=os.time(),
        detailsDate=0, -- force detail fetch; the list page has no per-order data
        detailsUrl=buildDetailsUrl(orderCode),
      }
    end
    debugBuffer.flush()
    debugBuffer.context=''
  end) -- order card
  return orders
end

--- @function isRecentOrderFilter
-- Short windows must be re-scanned every run. Amazon's last30 view can be empty
-- (error banner) while months-3 still lists the same recent orders.
-- Business B2B UI uses German values like "Letzte 30.Tage" / "Letzte 3.Monate".
function isRecentOrderFilter(filterVal)
  if type(filterVal) ~= 'string' then
    return false
  end
  if string.match(filterVal, "^last") ~= nil or filterVal == const.recentMonthsFilter then
    return true
  end
  -- Amazon Business (German) timeFilter option values
  if string.find(filterVal, "30.Tage", 1, true) or string.find(filterVal, "3.Monate", 1, true) then
    return true
  end
  if string.find(filterVal, "30 Tage", 1, true) or string.find(filterVal, "3 Monate", 1, true) then
    return true
  end
  -- Amazon Business SPA filter ids used by /ab/your-orders/orderHistory
  if filterVal == "yoLast30Days" or filterVal == "yoPast3months"
      or filterVal == "last_30_days" or filterVal == "last_3_months" then
    return true
  end
  return false
end

--- @function orderFilterWithinScanMonths
-- Whether an Amazon timeFilter value overlaps [now - months, now].
-- months<=0 or nil: no extra limit. asOf optional {year,month,day} for tests.
function orderFilterWithinScanMonths(filterVal, months, asOf)
  if type(filterVal) ~= 'string' then
    return false
  end
  local limit=tonumber(months)
  if limit == nil or limit <= 0 then
    return true
  end
  if isRecentOrderFilter(filterVal) then
    return true
  end
  local monthsWindow=tonumber(string.match(filterVal, "^months%-(%d+)$"))
  if monthsWindow ~= nil then
    return monthsWindow <= limit
  end
  local year=tonumber(string.match(filterVal, "^year%-(%d%d%d%d)$"))
  if year == nil then
    return false
  end
  local now=asOf or os.date("*t")
  local startMonth=now.month - limit
  local startYear=now.year
  while startMonth <= 0 do
    startMonth=startMonth + 12
    startYear=startYear - 1
  end
  return year >= startYear and year <= now.year
end

--- @function getSelectedOrderFilter
-- @return #string value of the selected timeFilter/orderFilter option, or ""
function getSelectedOrderFilter(htmlNode)
  if htmlNode == nil then
    return ''
  end
  local val=htmlNode:xpath(const.xpathOrderMonthSelect..'//option[@selected]'):attr('value')
  if type(val) == 'string' and val ~= '' then
    return val
  end
  return ''
end

function getSelectedOrderFilterLabel(htmlNode, filterVal)
  local label=htmlNode:xpath(const.xpathOrderMonthSelect..'//option[@selected]'):text()
  return firstNonEmpty(label, filterVal)
end

--- @function mergeOrdersFromPage
-- Merges getOrdersFromSummary(html) into orderCache.
-- @param subAccountLabel optional Amazon-Unterkonto label stored on new orders
-- @param kind optional "personal"|"business" for ListAccounts filtering
-- @return foundOrders, foundNewOrders, newCount
function assignSubAccountMeta(order, subAccountLabel, kind)
  if type(order) ~= 'table' then
    return
  end
  if type(subAccountLabel) == 'string' and subAccountLabel ~= '' then
    if order.accountNumber == nil or order.accountNumber == '' then
      order.accountNumber=subAccountLabel
    end
  end
  if type(kind) == 'string' and kind ~= '' then
    order.subAccountKind=kind
  end
end

function assignSubAccountLabel(order, subAccountLabel)
  assignSubAccountMeta(order, subAccountLabel, nil)
end

function mergeOrdersFromPage(htmlNode, orderCache, subAccountLabel, kind)
  if type(orderCache) ~= 'table' then
    error("mergeOrdersFromPage: orderCache must be a table")
  end
  local foundOrders=false
  local foundNewOrders=false
  local newCount=0
  for orderCode,order in pairs(getOrdersFromSummary(htmlNode)) do
    foundOrders=true
    if orderCache[orderCode] == nil then
      assignSubAccountMeta(order, subAccountLabel, kind)
      orderCache[orderCode]=order
      foundNewOrders=true
      newCount=newCount+1
    else
      assignSubAccountMeta(orderCache[orderCode], subAccountLabel, kind)
    end
  end
  return foundOrders, foundNewOrders, newCount
end

--- @function markOrderFilterCacheIfComplete
-- Caches a timeFilter when the scan found no new orders (including empty pages).
-- Empty year-* filters must be marked; otherwise every refresh re-fetches all
-- empty years (1995..) and MoneyMoney can crash (signal 11 / OOM).
-- Recent windows still re-scan every run via isRecentOrderFilter.
function markOrderFilterCacheIfComplete(orderFilterCache, orderFilterVal, foundNewOrders)
  if foundNewOrders then
    return false
  end
  if type(orderFilterCache) ~= 'table' or type(orderFilterVal) ~= 'string' or orderFilterVal == '' then
    return false
  end
  orderFilterCache[orderFilterVal]=true
  return true
end

--- @function scanOrderFilterPages
-- Walks the current order-list page and its "next" links (no filter submit).
-- Mutates global html when paginating. May mark orderFilterCache[filterVal].
-- @return foundOrders, foundNewOrders, newCount
function scanOrderFilterPages(orderFilterVal, orderCache, orderFilterCache, subAccountLabel, kind)
  local foundOrders=false
  local foundNewOrders=false
  local newCountTotal=0
  if html == nil then
    print("scanOrderFilterPages: html is nil, skip filter", tostring(orderFilterVal))
    return foundOrders, foundNewOrders, newCountTotal
  end
  local foundEnd=false
  repeat
    local pageFoundOrders, pageFoundNewOrders, newCount=mergeOrdersFromPage(html, orderCache, subAccountLabel, kind)
    if pageFoundOrders then
      foundOrders=true
    end
    if pageFoundNewOrders then
      foundNewOrders=true
    end
    newCountTotal=newCountTotal+newCount
    local nextPage=html:xpath('//li[contains(@class,"a-last")]/a[@href]')
    if nextPage:text() ~= "" then
      local nextHtml=connectShop(nextPage:click())
      if nextHtml == nil then
        print("scanOrderFilterPages: next page nil, stop pagination")
        foundEnd=true
      else
        html=nextHtml
      end
    else
      foundEnd=true
    end
  until foundEnd
  markOrderFilterCacheIfComplete(orderFilterCache, orderFilterVal, foundNewOrders)
  return foundOrders, foundNewOrders, newCountTotal
end

function absoluteAmazonUrl(url)
  if type(url) ~= 'string' or url == '' then
    return url
  end
  if string.match(url, "^https?://") then
    return url
  end
  if string.sub(url, 1, 1) == '/' then
    return baseurl..url
  end
  return baseurl..'/'..url
end

function firstNonEmpty(...)
  for i=1,select('#', ...) do
    local s=select(i, ...)
    if type(s) == 'string' and s ~= '' then
      return s
    end
  end
  return ''
end

--- @function parseAccountSwitcher
-- Parses CVF account-switcher HTML into switchable personal/business options.
function parseAccountSwitcher(htmlNode)
  local accounts={}
  if htmlNode == nil then
    return accounts
  end
  htmlNode:xpath('//form[contains(@class,"cvf-widget-form-account-switcher")]'):each(function(_, form)
    local action=form:attr('action')
    if action == '' or string.find(action, "switchaccount", 1, true) == nil then
      return true
    end
    local token=form:xpath('.//*[@data-name="switch_account_request"]'):attr('data-value')
    if token == '' then
      token=form:xpath('.//input[@name="switch_account_request"]'):attr('value')
    end
    local csrf=form:xpath('.//input[@name="CsrfToken"]'):attr('value')
    local anti=form:xpath('.//input[@name="anti-csrftoken-a2z"]'):attr('value')
    local accountType=trim(form:xpath('.//*[@data-test-id="accountType"]'):text())
    local businessName=trim(form:xpath('.//*[@data-test-id="businessName"]'):text())
    local customerName=trim(form:xpath('.//*[@data-test-id="customerName"]'):text())
    local kind="personal"
    if form:xpath('.//*[contains(@class,"business-account-icon")]'):length() > 0 then
      kind="business"
    end
    local label=firstNonEmpty(businessName, accountType, customerName)
    if token ~= '' and csrf ~= '' and label ~= '' then
      table.insert(accounts, {
        kind=kind,
        label=label,
        accountType=accountType,
        businessName=businessName,
        customerName=customerName,
        action=action,
        token=token,
        csrf=csrf,
        anti=anti,
      })
    end
    return true
  end)
  return accounts
end

--- @function cvfVersionQueryFromText
-- Parses CVFVersion/AUIVersion from a URL or HTML snippet.
function cvfVersionQueryFromText(text)
  if type(text) ~= 'string' or text == '' then
    return ''
  end
  local cvf=string.match(text, "CVFVersion=([%w%._%-]+)")
  if cvf == nil then
    return ''
  end
  local aui=string.match(text, "AUIVersion=([%w%._%-]+)")
  if aui ~= nil then
    return "CVFVersion="..cvf.."&AUIVersion="..aui
  end
  return "CVFVersion="..cvf
end

--- @function cvfEmbedVersionQuery
-- Pulls CVFVersion/AUIVersion from an existing request.embed URL or page HTML.
function cvfEmbedVersionQuery(htmlNode)
  if htmlNode == nil then
    return ''
  end
  local src=htmlNode:xpath('//*[contains(@src,"request.embed")]'):attr('src')
  local fromSrc=cvfVersionQueryFromText(src)
  if fromSrc ~= '' then
    return fromSrc
  end
  return cvfVersionQueryFromText(htmlNode:html())
end

--- @function accountSwitcherEmbedUrl
-- Builds CVF embed URL from arb; optional versionQuery from cvfEmbedVersionQuery.
function accountSwitcherEmbedUrl(arb, versionQuery)
  if type(arb) ~= 'string' or arb == '' then
    return nil
  end
  local url="/ap/cvf/request.embed?arb="..arb
  if type(versionQuery) == 'string' and versionQuery ~= '' then
    url=url.."&"..versionQuery
  end
  return url
end

--- @function findAccountSwitcherHref
-- "Konto wechseln" is usually NOT a live DOM <a>: Amazon embeds the nav flyout
-- HTML inside $Nav accountListContent (a <script> string). XPath misses it; fall
-- back to scraping the raw page HTML / a HAR-proven OpenID picker URL.
function findAccountSwitcherHref(htmlNode)
  if htmlNode == nil then
    return ''
  end
  local href=htmlNode:xpath('//a[@id="nav-item-switch-account"]'):attr('href')
  if href ~= '' then
    return href
  end
  href=htmlNode:xpath('//a[contains(@href,"switch_account=picker")]'):attr('href')
  if href ~= '' then
    return href
  end
  href=htmlNode:xpath('//a[contains(@href,"nav_youraccount_switchacct")]'):attr('href')
  if href ~= '' then
    return href
  end
  local raw=htmlNode:html()
  if type(raw) ~= 'string' or raw == '' then
    return ''
  end
  local fromJs=string.match(raw, "id=['\"]nav%-item%-switch%-account['\"][^>]*href=['\"]([^'\"]+)['\"]")
  if fromJs == nil then
    fromJs=string.match(raw, "href=['\"]([^'\"]*switch_account=picker[^'\"]*)['\"]")
  end
  if fromJs == nil then
    fromJs=string.match(raw, "href=['\"]([^'\"]*nav_youraccount_switchacct[^'\"]*)['\"]")
  end
  if fromJs == nil then
    return ''
  end
  return (fromJs:gsub("&amp;", "&"))
end

--- @function defaultAccountSwitcherSigninUrl
-- OpenID account-picker entry used when the nav link cannot be recovered.
function defaultAccountSwitcherSigninUrl()
  local returnTo=MM.urlencode(baseurl.."/gp/css/homepage.html?ref_=nav_youraccount_switchacct")
  return "/ap/signin?openid.return_to="..returnTo
    .."&openid.identity="..MM.urlencode("http://specs.openid.net/auth/2.0/identifier_select")
    .."&openid.assoc_handle=deflex"
    .."&openid.mode=checkid_setup"
    .."&openid.claimed_id="..MM.urlencode("http://specs.openid.net/auth/2.0/identifier_select")
    .."&openid.ns="..MM.urlencode("http://specs.openid.net/auth/2.0")
    .."&switch_account=picker&ignoreAuthState=1&_encoding=UTF8"
end

--- @function openAccountSwitcherEmbed
-- Opens Your Account → Konto wechseln → CVF embed with switchable accounts.
function openAccountSwitcherEmbed()
  local ya=connectShop("GET", absoluteAmazonUrl("/gp/css/homepage.html?ref_=nav_youraccount_btn"))
  local switchHref=findAccountSwitcherHref(ya)
  if switchHref == '' then
    switchHref=defaultAccountSwitcherSigninUrl()
    print("account switcher link not in DOM, using OpenID picker URL")
  end
  local signin=connectShop("GET", absoluteAmazonUrl(switchHref))
  if signin:xpath('//form[contains(@class,"cvf-widget-form-account-switcher")]'):length() > 0 then
    return signin
  end
  local embedSrc=signin:xpath('//*[contains(@src,"cvf/request.embed")]'):attr('src')
  if embedSrc == '' then
    local arb=signin:xpath('//div[@data-arbtoken]'):attr('data-arbtoken')
    embedSrc=accountSwitcherEmbedUrl(arb, cvfEmbedVersionQuery(signin)) or ''
  end
  if embedSrc == '' then
    print("account switcher embed not found")
    return nil
  end
  return connectShop("GET", absoluteAmazonUrl(embedSrc))
end

--- @function decodeSwitchAccountRedirect
-- Parses CVF switch JSON for redirectUrl; returns nil on non-JSON / missing field.
function decodeSwitchAccountRedirect(content)
  if type(content) ~= 'string' or content == '' then
    return nil
  end
  local ok, data=pcall(function()
    return JSON(content):dictionary()
  end)
  if not ok or type(data) ~= 'table' then
    return nil
  end
  local redirect=data["redirectUrl"]
  if type(redirect) ~= 'string' or redirect == '' then
    return nil
  end
  return redirect
end

--- @function switchAmazonSubAccount
-- POSTs the CVF switch form and follows redirectUrl (may be /ap/challenge → MFA).
-- @return #table {ok=true} | {needsMfa=true, challenge=...} | {error=string}
function switchAmazonSubAccount(option)
  if option == nil or option.token == nil or option.csrf == nil then
    return {error="missing switch option fields"}
  end
  local action=absoluteAmazonUrl(option.action)
  local post="CsrfToken="..MM.urlencode(option.csrf)
    .."&anti-csrftoken-a2z="..MM.urlencode(option.anti or "")
    .."&switch_account_request="..MM.urlencode(option.token)
  local content=connectShopRaw("POST", action, post, "application/x-www-form-urlencoded", {
    ["Accept"]="application/json, text/javascript, */*",
    ["X-Requested-With"]="XMLHttpRequest",
  })
  local redirect=decodeSwitchAccountRedirect(content)
  if redirect == nil then
    return {error="no redirectUrl for "..tostring(option.label)}
  end
  print("switch account -> "..tostring(option.label).." ("..redirect..")")
  html=connectShop("GET", absoluteAmazonUrl(redirect))
  return finishAccountSwitchLanding(html, {switchKind=option.kind})
end

function mfaChallengeFromHtml(htmlNode)
  if htmlNode == nil then
    return nil
  end
  if htmlNode:xpath('//form[@id="auth-mfa-form"]'):length() == 0
      and htmlNode:xpath('//*[@name="otpCode"]'):length() == 0 then
    return nil
  end
  local mfatext=htmlNode:xpath('//form[@id="auth-mfa-form"]//p'):text()
  if mfatext == '' then
    mfatext='Bitte den Bestätigungscode für den Amazon-Kontenwechsel eingeben.'
  end
  return {
    title='Amazon Konto wechseln – 2FA',
    challenge=mfatext,
    label='Code'
  }
end

function submitAmazonMfa(htmlNode, otpCode)
  if htmlNode == nil then
    return nil, "MFA page missing"
  end
  if type(otpCode) ~= 'string' or otpCode == '' then
    return nil, "MFA code missing"
  end
  local form=htmlNode:xpath('//*[@id="auth-mfa-form"]')
  if form:length() == 0 then
    return nil, "MFA form missing"
  end
  htmlNode:xpath('//*[@name="otpCode"]'):attr("value", otpCode)
  htmlNode:xpath('//*[@name="rememberDevice"]'):attr('checked', 'checked')
  return connectShop(form:submit()), nil
end

--- @function submitSwitchAuthPrompt
-- Completes Amazon switch_account=auth_prompt (password re-auth) using the
-- same credentials as the initial MoneyMoney login (secUsername/secPassword).
-- @return htmlNode, nil | nil, errString
function submitSwitchAuthPrompt(htmlNode)
  if htmlNode == nil then
    return nil, "auth_prompt page missing"
  end
  if type(secPassword) ~= 'string' or secPassword == '' then
    return nil, "password missing for auth_prompt"
  end
  local form=htmlNode:xpath('//form[@name="signIn"]')
  if form:length() == 0 then
    form=htmlNode:xpath('//*[@name="signIn"]')
  end
  if form:length() == 0 then
    return nil, "signIn form missing on auth_prompt"
  end
  if type(secUsername) == 'string' and secUsername ~= '' then
    htmlNode:xpath('//*[@name="email"]'):attr("value", secUsername)
  end
  htmlNode:xpath('//*[@name="password"]'):attr("value", secPassword)
  print("switch auth_prompt: submitting password")
  return connectShop(form:submit()), nil
end

--- @function finishAccountSwitchLanding
-- @param opts optional {authPromptTried=bool, interstitialTried=bool}
function finishAccountSwitchLanding(htmlNode, opts)
  if htmlNode == nil then
    return {error="empty switch landing page"}
  end
  if type(opts) ~= 'table' then
    opts={}
  end
  if isAkamaiInterstitial(htmlNode) and not opts.interstitialTried then
    local nextHtml, err=completeAkamaiInterstitial(htmlNode)
    if err ~= nil then
      return {error=err}
    end
    opts.interstitialTried=true
    return finishAccountSwitchLanding(nextHtml, opts)
  end
  local mfa=mfaChallengeFromHtml(htmlNode)
  if mfa ~= nil then
    html=htmlNode
    return {needsMfa=true, challenge=mfa}
  end
  local authBlock=switchAuthBlockReason(htmlNode)
  if authBlock == "interactive login" and not opts.authPromptTried then
    local nextHtml, err=submitSwitchAuthPrompt(htmlNode)
    if err ~= nil then
      return {error=err}
    end
    opts.authPromptTried=true
    return finishAccountSwitchLanding(nextHtml, opts)
  end
  if authBlock ~= nil then
    return {error="switch landed on "..authBlock}
  end
  html=htmlNode
  if opts.switchKind == 'business' then
    print("Business switch: load Your Account homepage (HAR landing)")
    html=connectShop("GET", baseurl..const.businessHomepageAfterSwitch)
  end
  return {ok=true}
end

function switchAuthBlockReason(htmlNode)
  if htmlNode == nil then
    return nil
  end
  if htmlNode:xpath('//form[@id="auth-mfa-form"]'):length() > 0
      or htmlNode:xpath('//*[@name="otpCode"]'):length() > 0 then
    return "MFA"
  end
  if htmlNode:xpath('//form[contains(@name,"signIn")]//*[@name="password"]'):length() > 0 then
    return "interactive login"
  end
  return nil
end

--- @function isAkamaiInterstitial
-- Bot-management challenge page (bm-verify / _sec/verify) after account switch.
function isAkamaiInterstitial(htmlNode)
  local raw=htmlNodeRaw(htmlNode)
  if raw == '' then
    return false
  end
  if string.find(raw, "bm-verify", 1, true) == nil then
    return false
  end
  return string.find(raw, "/_sec/verify", 1, true) ~= nil
    or string.find(raw, "triggerInterstitialChallenge", 1, true) ~= nil
end

--- @function completeAkamaiInterstitial
-- Completes Amazon/Akamai interstitial without a browser JS engine:
-- POST /_sec/verify with bm-verify + pow, then follow location / meta-refresh.
function completeAkamaiInterstitial(htmlNode)
  local raw=htmlNodeRaw(htmlNode)
  print("Akamai interstitial: completing challenge")
  local iVal=tonumber(string.match(raw, "var%s+i%s*=%s*(%d+)"))
  local n1, n2=string.match(raw, 'Number%s*%(%s*"(%d+)"%s*%+%s*"(%d+)"%s*%)')
  local bmVerify=string.match(raw, 'JSON%.stringify%(%s*{%s*"bm%-verify"%s*:%s*"([^"]+)"')
  if bmVerify == nil then
    bmVerify=string.match(raw, '"bm%-verify"%s*:%s*"([^"]+)"')
  end
  if iVal ~= nil and n1 ~= nil and n2 ~= nil and bmVerify ~= nil then
    local pow=iVal + tonumber(n1..n2)
    local body='{"bm-verify":'..jsonQuote(bmVerify)..',"pow":'..tostring(pow)..'}'
    local ok, content=pcall(function()
      return connectShopRaw("POST", baseurl.."/_sec/verify?provider=interstitial", body,
        "application/json", {
          ["Accept"]="application/json",
          ["Content-Type"]="application/json",
        })
    end)
    if not ok then
      return nil, "Akamai verify request failed: "..tostring(content)
    end
    if type(content) == 'string' then
      local location=string.match(content, '"location"%s*:%s*"([^"]+)"')
      if location ~= nil and location ~= '' then
        location=location:gsub("\\/", "/")
        if string.sub(location, 1, 1) == '/' then
          location=baseurl..location
        end
        print("Akamai interstitial: follow location")
        return connectShop("GET", location), nil
      end
      if string.find(content, '"reload"%s*:%s*true') then
        print("Akamai interstitial: reload after verify")
        return connectShop("GET", baseurl.."/"), nil
      end
    end
  end
  local refresh=string.match(raw, "[Uu][Rr][Ll]%s*=%s*'([^']+)'")
    or string.match(raw, '[Uu][Rr][Ll]%s*=%s*"([^"]+)"')
  if refresh ~= nil and refresh ~= '' then
    refresh=refresh:gsub("&amp;", "&")
    if string.sub(refresh, 1, 1) == '/' then
      refresh=baseurl..refresh
    elseif string.match(refresh, "^https?://") == nil then
      refresh=baseurl.."/"..refresh
    end
    print("Akamai interstitial: follow meta-refresh")
    return connectShop("GET", refresh), nil
  end
  return nil, "Akamai interstitial incomplete"
end

function ensureOrderFilterCacheRoot()
  if LocalStorage.orderFilterCacheByAccount == nil then
    LocalStorage.orderFilterCacheByAccount={}
  end
  LocalStorage.orderFilterCache=nil
end

function filterCacheForSubAccount(subAccountLabel)
  ensureOrderFilterCacheRoot()
  local key=subAccountLabel or ""
  if LocalStorage.orderFilterCacheByAccount[key] == nil then
    LocalStorage.orderFilterCacheByAccount[key]={}
  end
  return LocalStorage.orderFilterCacheByAccount[key]
end

function ensureOrderCache()
  if LocalStorage.OrderCache == nil then
    LocalStorage.OrderCache={}
  end
  return LocalStorage.OrderCache
end

function shouldHarvestOrderFilter(orderFilterVal, orderFilterCache, numbersOfNewOrders, refreshSince, now)
  now=now or os.time()
  local scanMonths=effectiveScanFiltersMonths(refreshSince, now)
  if not orderFilterWithinScanMonths(orderFilterVal, scanMonths, os.date('*t', now)) then
    return false
  end
  return isRecentOrderFilter(orderFilterVal)
    or (orderFilterCache[orderFilterVal] == nil and numbersOfNewOrders < config.limitOrders + 1)
end

function resolveAkamaiInterstitial(page)
  if not isAkamaiInterstitial(page) then
    return page, nil
  end
  local nextHtml, err=completeAkamaiInterstitial(page)
  if err ~= nil then
    return page, err
  end
  return nextHtml, nil
end

--- @function orderListPageReady
-- True when the page has scrapable order cards or a classic order timeFilter form.
-- Amazon Business often lands on an ABYourOrders SPA skeleton (no cards, no form).
function orderListPageReady(htmlNode)
  if htmlNode == nil then
    return false
  end
  if htmlNode:xpath('//div[contains(@class,"order-card")]'):length() > 0 then
    return true
  end
  if htmlNode:xpath(const.xpathOrderMonthForm):length() > 0 then
    return true
  end
  return false
end

--- @function isAmazonBusinessSession
-- Active Amazon Business identity (e.g. after switch to Altanis GmbH).
function isAmazonBusinessSession(htmlNode)
  if htmlNode == nil then
    return false
  end
  return htmlNode:xpath('//span[contains(@class,"abnav-accountfor")]'):length() > 0
end

--- @function isAmazonBusinessOrdersSpa
-- Amazon Business "Meine Bestellungen" loads orders via XHR, not order-card HTML.
function isAmazonBusinessOrdersSpa(htmlNode)
  if htmlNode == nil then
    return false
  end
  return htmlNode:xpath('//*[@id="ab-your-orders-anticsrf-token"]'):length() > 0
end

--- @function isLoggedInOrderLanding
-- True when the session is already authenticated on an order/Business landing.
-- Classic xpathOrderMonthForm is missing on Business SPA shells; treating that
-- as LoginFailed incorrectly clears cookies and forces a password re-prompt.
function isLoggedInOrderLanding(htmlNode)
  if htmlNode == nil then
    return false
  end
  if htmlNode:xpath(const.xpathOrderMonthForm):length() > 0 then
    return true
  end
  if isAmazonBusinessOrdersSpa(htmlNode) then
    return true
  end
  if orderListPageReady(htmlNode) then
    return true
  end
  if isAmazonBusinessSession(htmlNode) then
    return true
  end
  local shortName=htmlNode:xpath('//span[contains(@class,"nav-shortened-name")]'):text()
  if shortName ~= nil and shortName ~= '' then
    return true
  end
  return false
end

function htmlNodeRaw(htmlNode)
  if htmlNode == nil then
    return ''
  end
  local raw=''
  pcall(function()
    raw=htmlNode:html()
  end)
  if type(raw) ~= 'string' then
    return ''
  end
  return raw
end

function firstStringMatch(text, pattern)
  if type(text) ~= 'string' or type(pattern) ~= 'string' then
    return nil
  end
  return string.match(text, pattern)
end

function jsonQuote(value)
  local s=tostring(value or '')
  s=s:gsub('\\', '\\\\'):gsub('"', '\\"')
  return '"'..s..'"'
end

function isPlausibleAmazonOrderCode(orderCode)
  if type(orderCode) ~= 'string' or orderCode == '' then
    return false
  end
  if string.sub(orderCode, 1, 4) == "000-" then
    return false
  end
  return orderCode ~= const.abaPlaceholderOrderCode
end

function countPlausibleOrdersInRawText(raw)
  if type(raw) ~= 'string' or raw == '' then
    return 0
  end
  local count=0
  for orderCode in raw:gmatch(const.regexOrderCodeNew) do
    if isPlausibleAmazonOrderCode(orderCode) then
      count=count+1
    end
  end
  return count
end

--- @function mergeOrdersFromRawText
-- Extracts Bestellnummern from arbitrary HTML/CSV/text (ABA report, orderHistory).
function mergeOrdersFromRawText(raw, orderCache, subAccountLabel, kind)
  local foundOrders=false
  local foundNewOrders=false
  local newCount=0
  if type(raw) ~= 'string' or raw == '' or type(orderCache) ~= 'table' then
    return foundOrders, foundNewOrders, newCount
  end
  for orderCode in raw:gmatch(const.regexOrderCodeNew) do
    if isPlausibleAmazonOrderCode(orderCode) then
      foundOrders=true
      if orderCache[orderCode] == nil then
        local order={
          orderCode=orderCode,
          orderPositions={},
          orderSum=0,
          orderTotal=0,
          refund=0,
          bookingDate=os.time(),
          detailsDate=0,
          detailsUrl=buildDetailsUrl(orderCode),
        }
        assignSubAccountMeta(order, subAccountLabel, kind)
        orderCache[orderCode]=order
        foundNewOrders=true
        newCount=newCount+1
      else
        assignSubAccountMeta(orderCache[orderCode], subAccountLabel, kind)
      end
    end
  end
  return foundOrders, foundNewOrders, newCount
end

function rawContainsAnyMarker(raw, markers)
  if type(raw) ~= 'string' or raw == '' or type(markers) ~= 'table' then
    return false
  end
  for _, marker in ipairs(markers) do
    if string.find(raw, marker, 1, true) then
      return true
    end
  end
  return false
end

function hasAbaCsvHeader(content)
  return rawContainsAnyMarker(content, const.abaCsvHeaders)
end

function isAbaHtmlDocument(content)
  return string.find(content, "<html", 1, true)
    or string.find(content, "<!doctype", 1, true)
end

function isAbaCsvOrOrderText(content)
  if type(content) ~= 'string' or content == '' then
    return false
  end
  if isAbaHtmlDocument(content) then
    return false
  end
  if countPlausibleOrdersInRawText(content) < 1 then
    return false
  end
  if hasAbaCsvHeader(content) then
    return true
  end
  if string.find(content, ",", 1, true) or string.find(content, "\t", 1, true) then
    return string.find(content, "\n", 1, true) ~= nil
  end
  return false
end

function extractAbaCsrfToken(raw)
  if type(raw) ~= 'string' or raw == '' then
    return nil
  end
  local token=string.match(raw, '<meta[^>]-name="anti%-csrftoken%-a2z"[^>]-content="([^"]+)"')
    or string.match(raw, 'name="anti%-csrftoken%-a2z"%s+value="([^"]+)"')
    or string.match(raw, '"anti%-csrftoken%-a2z"%s*:%s*"([^"]+)"')
  if token == nil or token == '' then
    return nil
  end
  return token
end

function abaLanguageTag()
  if type(config.cookieLanguage) == 'string' and config.cookieLanguage ~= '' then
    return config.cookieLanguage
  end
  if const.domain == '.amazon.de' then
    return 'de-DE'
  end
  if const.domain == '.amazon.co.uk' then
    return 'en-GB'
  end
  if const.domain == '.amazon.fr' then
    return 'fr-FR'
  end
  if const.domain == '.amazon.it' then
    return 'it-IT'
  end
  if const.domain == '.amazon.es' then
    return 'es-ES'
  end
  return 'en-US'
end

--- MoneyMoney RefreshAccount(since): incremental when since is a recent last-fetch timestamp.
function orderCacheHasOrders()
  if LocalStorage == nil or type(LocalStorage.OrderCache) ~= 'table' then
    return false
  end
  return next(LocalStorage.OrderCache) ~= nil
end

function validMoneyMoneyRefreshAge(refreshSince, now)
  if type(refreshSince) ~= 'number' or type(now) ~= 'number' or refreshSince <= 0 then
    return nil
  end
  local age=now - refreshSince
  if age <= 0 then
    return nil
  end
  return age
end

function isIncrementalMoneyMoneyRefresh(refreshSince, now)
  if not orderCacheHasOrders() then
    return false
  end
  local age=validMoneyMoneyRefreshAge(refreshSince, now)
  return age ~= nil and age <= const.abaIncrementalMaxAgeSec
end

function isStaleMoneyMoneyRefresh(refreshSince, now)
  local age=validMoneyMoneyRefreshAge(refreshSince, now)
  return age ~= nil and age > const.abaIncrementalMaxAgeSec
end

function requiresFullMoneyMoneyHarvest(refreshSince, now)
  if not orderCacheHasOrders() then
    return true
  end
  if type(refreshSince) ~= 'number' or refreshSince <= 0 then
    return true
  end
  return isStaleMoneyMoneyRefresh(refreshSince, now)
end

function unixToAbaDateParts(unixTime)
  local parts=os.date('*t', unixTime)
  if parts == nil then
    return nil
  end
  return {
    year=parts.year,
    month=parts.month - 1,
    day=parts.day,
  }
end

function abaDatePartsJson(parts)
  if type(parts) ~= 'table' then
    return 'null'
  end
  return '{"year":'..tostring(parts.year)
    ..',"month":'..tostring(parts.month)
    ..',"day":'..tostring(parts.day)..'}'
end

function formatAbaDateLabel(unixTime)
  if type(unixTime) ~= 'number' then
    return ''
  end
  return os.date('%d.%m.%Y', unixTime) or ''
end

function buildAbaRollupTablePostBody(reportType, fromParts, toParts)
  return '{"reportType":'..jsonQuote(reportType)
    ..',"reportId":"","dateSpanSelection":"'..const.abaCustomRangeSpan..'"'
    ..',"fromDate":'..abaDatePartsJson(fromParts)
    ..',"toDate":'..abaDatePartsJson(toParts)
    ..',"groupColumn":"obfCustGroupId","pageMarker":0,"reportName":""'
    ..',"columns":[{"text":"Bestellnummer","value":"ordId","visible":true,"frozen":false}]'
    ..',"groups":[],"localFilters":[],"tableFilters":[],"globalFilters":[],"pageSize":16}'
end

function effectiveScanFiltersMonths(refreshSince, now)
  local configured=tonumber(config.scanFiltersMonths)
  if not isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return configured
  end
  local days=math.ceil((now - refreshSince) / (24 * 60 * 60))
  local months=math.max(1, math.ceil(days / 31))
  if configured == nil or configured <= 0 then
    return months
  end
  return math.min(configured, months)
end

function shouldRunAccountHarvest(refreshSince, now)
  if config.noRefresh then
    return false
  end
  if LocalStorage.loginCounter ~= LocalStorage.lastLoginCounter then
    return true
  end
  if not isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return requiresFullMoneyMoneyHarvest(refreshSince, now)
  end
  local lastHarvest=LocalStorage.lastHarvestSince
  return type(lastHarvest) ~= 'number' or refreshSince > lastHarvest
end

function logMoneyMoneyRefreshMode(refreshSince, now)
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    print("incremental refresh since", formatAbaDateLabel(refreshSince))
    return
  end
  print("full refresh: harvest all order history (empty cache, since=0, or since > 366 days)")
end

function logAbaHarvestMode(refreshSince, now)
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    print("Business ABA harvest: CUSTOM_RANGE since", formatAbaDateLabel(refreshSince))
    return
  end
  print("Business ABA harvest:", const.abaFullHarvestSpan, "(max preset window, no overlapping spans)")
end

function buildAbaAjaxUrl(path, reportType, span)
  return baseurl..path
    ..'?reportType='..MM.urlencode(reportType)
    ..'&dateSpanSelection='..MM.urlencode(span)
    ..'&language='..MM.urlencode(abaLanguageTag())
end

function buildAbaAjaxHeaders(csrf, referer)
  local headers={
    Referer=referer,
    Accept='application/json, text/javascript, */*; q=0.01',
    ['X-Requested-With']='XMLHttpRequest',
  }
  if type(csrf) == 'string' and csrf ~= '' then
    headers['anti-csrftoken-a2z']=csrf
  end
  return headers
end

function fetchAbaAjaxContent(url, csrf, referer, postBody)
  if type(postBody) == 'string' and postBody ~= '' then
    return fetchShopRawContent('POST', url, postBody, 'application/json', buildAbaAjaxHeaders(csrf, referer))
  end
  return fetchShopRawContent('GET', url, nil, nil, buildAbaAjaxHeaders(csrf, referer))
end

function rawTextHasHarvestableOrders(raw)
  return countPlausibleOrdersInRawText(raw) >= 1
end

function fetchAbaRollupTable(reportType, span, csrf, referer, logPrefix, fromParts, toParts)
  local querySpan=span
  local postBody=nil
  if span == const.abaCustomRangeSpan and type(fromParts) == 'table' and type(toParts) == 'table' then
    querySpan='PAST_12_MONTHS'
    postBody=buildAbaRollupTablePostBody(reportType, fromParts, toParts)
    print(logPrefix, "try rollupTable POST CUSTOM_RANGE")
  else
    print(logPrefix, "try rollupTable GET")
  end
  local url=buildAbaAjaxUrl(const.abaRollupTablePath, reportType, querySpan)
  local content, err=fetchAbaAjaxContent(url, csrf, referer, postBody)
  if content == nil then
    print(logPrefix, "rollupTable failed:", tostring(err))
    return nil
  end
  if isAmazonSignInPageHtml(content) then
    print(logPrefix, "rollupTable redirected to sign-in")
    return nil
  end
  if isAbaHtmlDocument(content) then
    print(logPrefix, "rollupTable returned HTML error page")
    return nil
  end
  if not rawTextHasHarvestableOrders(content) then
    print(logPrefix, "rollupTable no orders in response")
    return nil
  end
  print(logPrefix, "rollupTable orders found")
  return content
end

function parseAbaReportStatusIds(raw)
  if type(raw) ~= 'string' or raw == '' then
    return nil, nil
  end
  local reportId=string.match(raw, '"reportRequestId"%s*:%s*"([^"]+)"')
    or string.match(raw, '"reportId"%s*:%s*"([^"]+)"')
    or string.match(raw, '"requestId"%s*:%s*"([^"]+)"')
  local timestamp=string.match(raw, '"timestamp"%s*:%s*(%d+)')
    or string.match(raw, '"reportTimestamp"%s*:%s*(%d+)')
  if reportId ~= nil and timestamp ~= nil then
    return reportId, timestamp
  end
  local path=string.match(raw, '(/b2b/aba/report/status/[^"\\]+)')
  if path ~= nil then
    local id, ts=string.match(path, '/b2b/aba/report/status/([^/]+)/(%d+)')
    return id, ts
  end
  return nil, nil
end

function buildAbaReportStatusUrl(reportId, timestamp, reportType, span)
  return baseurl..const.abaReportStatusPath..reportId..'/'..timestamp
    ..'?reportType='..MM.urlencode(reportType)
    ..'&dateSpanSelection='..MM.urlencode(span)
    ..'&language='..MM.urlencode(abaLanguageTag())
end

function abaReportStatusComplete(raw)
  if type(raw) ~= 'string' or raw == '' then
    return false
  end
  if string.find(raw, "FAILED", 1, true) or string.find(raw, "ERROR", 1, true) then
    return false
  end
  return string.find(raw, "COMPLETE", 1, true) ~= nil
    or string.find(raw, "SUCCESS", 1, true) ~= nil
    or string.find(raw, "READY", 1, true) ~= nil
    or string.find(raw, "complete", 1, true) ~= nil
    or string.find(raw, "download", 1, true) ~= nil
end

function pollAbaReportStatus(statusUrl, csrf, referer, logPrefix)
  local attempts=const.abaReportPollAttempts
  local sleepSec=const.abaReportPollSleepSec
  for attempt=1, attempts do
    print(logPrefix, "status poll", attempt)
    local content, err=fetchAbaAjaxContent(statusUrl, csrf, referer)
    if content == nil then
      print(logPrefix, "status poll failed:", tostring(err))
      return nil
    end
    if abaReportStatusComplete(content) then
      return content
    end
    if attempt < attempts then
      MM.sleep(sleepSec)
    end
  end
  print(logPrefix, "status poll timeout")
  return nil
end

function fetchAbaGenerateDownloadLinks(reportType, span, csrf, referer, logPrefix)
  local url=buildAbaAjaxUrl(const.abaGenerateDownloadLinksPath, reportType, span)
  print(logPrefix, "try generate-download-links GET")
  return fetchAbaAjaxContent(url, csrf, referer)
end

function scheduleAndDownloadAbaReport(reportType, span, csrf, referer, logPrefix)
  local schedUrl=buildAbaAjaxUrl(const.abaReportSchedulerPath, reportType, span)
  print(logPrefix, "try scheduler GET")
  local schedRaw, err=fetchAbaAjaxContent(schedUrl, csrf, referer)
  if schedRaw == nil then
    print(logPrefix, "scheduler failed:", tostring(err))
    return nil
  end
  local reportId, timestamp=parseAbaReportStatusIds(schedRaw)
  local statusRaw=schedRaw
  if reportId ~= nil and timestamp ~= nil then
    local statusUrl=buildAbaReportStatusUrl(reportId, timestamp, reportType, span)
    local polled=pollAbaReportStatus(statusUrl, csrf, referer, logPrefix)
    if polled ~= nil then
      statusRaw=polled
    end
  end
  if isAbaCsvOrOrderText(statusRaw) then
    print(logPrefix, "scheduler/status returned order text")
    return statusRaw
  end
  local fromStatus=harvestAbaDownloadUrls(statusRaw, logPrefix.." status")
  if fromStatus ~= nil then
    return fromStatus
  end
  local linksRaw=fetchAbaGenerateDownloadLinks(reportType, span, csrf, referer, logPrefix)
  if linksRaw == nil then
    return nil
  end
  if isAbaCsvOrOrderText(linksRaw) then
    return linksRaw
  end
  return harvestAbaDownloadUrls(linksRaw, logPrefix.." download-links")
end

function harvestAbaDownloadUrls(raw, logPrefix)
  if type(raw) ~= 'string' or raw == '' then
    return nil
  end
  for _, dlUrl in ipairs(extractAbaDownloadUrls(raw)) do
    local csv=fetchAbaGetContent(dlUrl)
    if csv ~= nil and isAbaCsvOrOrderText(csv) then
      print(logPrefix.." download", dlUrl)
      return csv
    end
  end
  return nil
end

function tryHarvestAbaCsvFromHtmlPage(pageHtml, reportType, span, landingRaw, logPrefix, fromParts, toParts)
  local csrf=extractAbaCsrfToken(pageHtml) or extractAbaCsrfToken(landingRaw)
  if csrf == nil then
    print(logPrefix, "ABA harvest skipped: no CSRF token")
    return nil
  end
  local referer=buildAbaReportUrl(reportType, span, true)
  local rollup=fetchAbaRollupTable(reportType, span, csrf, referer, logPrefix, fromParts, toParts)
  if rollup ~= nil then
    return rollup
  end
  -- Same report: download links when Amazon already finished generation on the page.
  local fromLinks=harvestAbaDownloadUrls(pageHtml, logPrefix)
  if fromLinks ~= nil then
    return fromLinks
  end
  return scheduleAndDownloadAbaReport(reportType, span, csrf, referer, logPrefix)
end

function isAmazonSignInPageHtml(raw)
  if type(raw) ~= 'string' or raw == '' then
    return false
  end
  return switchAuthBlockReason(HTML(raw)) ~= nil
end

function isAbaLandingReady(raw)
  if type(raw) ~= 'string' or raw == '' then
    return false
  end
  if string.find(raw, "/b2b/aba", 1, true) == nil then
    return false
  end
  return rawContainsAnyMarker(raw, const.abaLandingMarkers)
end

function buildAbaLandingUrl()
  return baseurl..const.abaLandingPath..'?ref='..const.abaReportRef
end

function buildAbaReportUrl(reportType, span, reportsPath)
  local path=reportsPath and const.abaItemsReportPath or const.abaLandingPath
  local url=baseurl..path
    ..'?reportType='..MM.urlencode(reportType)
    ..'&dateSpanSelection='..MM.urlencode(span)
  if not reportsPath then
    url=url..'&ref='..const.abaReportRef
  end
  return url
end

function collectAbaHrefs(raw, acceptUrl)
  local urls={}
  local seen={}
  if type(raw) ~= 'string' or raw == '' or type(acceptUrl) ~= 'function' then
    return urls
  end
  for href in raw:gmatch('href="([^"]+)"') do
    local abs=absoluteAmazonUrl(href)
    if not seen[abs] and acceptUrl(abs) then
      seen[abs]=true
      table.insert(urls, abs)
    end
  end
  return urls
end

function isAbaDownloadUrl(url)
  return string.find(url, "/b2b/aba/", 1, true)
    and (string.find(url, "download", 1, true)
      or string.find(url, ".csv", 1, true)
      or string.find(url, "reportDocument", 1, true)
      or string.find(url, "GetReport", 1, true))
end

function isAbaReportLink(url, reportType, span)
  return string.find(url, "/b2b/aba/", 1, true)
    and string.find(url, reportType, 1, true)
    and (span == nil or span == '' or string.find(url, span, 1, true))
end

function extractAbaDownloadUrls(raw)
  local urls=collectAbaHrefs(raw, isAbaDownloadUrl)
  local seen={}
  for _, url in ipairs(urls) do
    seen[url]=true
  end
  if type(raw) ~= 'string' or raw == '' then
    return urls
  end
  for path in raw:gmatch('"(/b2b/aba/[^"]+download[^"]*)"') do
    local abs=absoluteAmazonUrl(path)
    if not seen[abs] and isAbaDownloadUrl(abs) then
      seen[abs]=true
      table.insert(urls, abs)
    end
  end
  for abs in raw:gmatch('"(https://www%.amazon%.[^/]+/b2b/aba/[^"]+download[^"]*)"') do
    if not seen[abs] and isAbaDownloadUrl(abs) then
      seen[abs]=true
      table.insert(urls, abs)
    end
  end
  return urls
end

function extractAbaReportLinksFromLanding(raw, reportType, span)
  return collectAbaHrefs(raw, function(url)
    return isAbaReportLink(url, reportType, span)
  end)
end

function fetchShopRawContent(method, url, body, contentType, headers)
  local ok, content=pcall(function()
    return connectShopRaw(method, url, body, contentType, headers)
  end)
  if not ok then
    return nil, tostring(content)
  end
  if type(content) ~= 'string' or content == '' then
    return nil, "empty response"
  end
  return content, nil
end

function fetchAbaGetContent(url)
  local content, err=fetchShopRawContent('GET', url, nil, nil, nil)
  if content == nil then
    if err == "empty response" then
      print("ABA GET empty:", url)
    else
      print("ABA GET failed:", url, err)
    end
    return nil
  end
  return content
end

function fetchAbaCsvFromUrl(url, logPrefix, reportType, span, landingRaw)
  local content=fetchAbaGetContent(url)
  if content == nil then
    return nil
  end
  if isAbaCsvOrOrderText(content) then
    print(logPrefix, url)
    return content
  end
  if isAbaHtmlDocument(content) and type(reportType) == 'string' and type(span) == 'string' then
    local fromHtml=tryHarvestAbaCsvFromHtmlPage(content, reportType, span, landingRaw, logPrefix)
    if fromHtml ~= nil then
      return fromHtml
    end
  end
  return harvestAbaDownloadUrls(content, logPrefix)
end

function abaPrimaryReportJob(refreshSince, now, reportType)
  now=now or os.time()
  reportType=reportType or const.abaItemsReportType
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    local fromParts=unixToAbaDateParts(refreshSince)
    local toParts=unixToAbaDateParts(now)
    if fromParts == nil or toParts == nil then
      return nil
    end
    return {
      reportType=reportType,
      span=const.abaCustomRangeSpan,
      fromDate=fromParts,
      toDate=toParts,
      fromUnix=refreshSince,
      toUnix=now,
    }
  end
  return {
    reportType=reportType,
    span=const.abaFullHarvestSpan,
  }
end

--- Exactly one ABA job: items_report_1 with PAST_12_MONTHS or CUSTOM_RANGE.
function enumerateAbaReportJobs(refreshSince, now)
  local job=abaPrimaryReportJob(refreshSince, now, const.abaItemsReportType)
  if job == nil then
    return {}
  end
  return { job }
end

function abaJobStatusLabel(job)
  if type(job) ~= 'table' then
    return ''
  end
  if job.span == const.abaCustomRangeSpan
      and type(job.fromUnix) == 'number'
      and type(job.toUnix) == 'number' then
    return job.span..' ('..formatAbaDateLabel(job.fromUnix)..'–'..formatAbaDateLabel(job.toUnix)..')'
  end
  return tostring(job.span)
end

function harvestAbaReportJob(job, landing, orderCache, subAccountLabel, kind)
  if type(job) ~= 'table' or landing == nil or type(orderCache) ~= 'table' then
    return 0
  end
  MM.printStatus('Amazon Business Bericht: '..job.reportType..' / '..abaJobStatusLabel(job))
  local content=harvestAbaReportContent(job.reportType, job.span, landing, job.fromDate, job.toDate)
  if content == nil then
    print("ABA no orders for", job.reportType, job.span)
    return 0
  end
  local _, _, n=mergeOrdersFromRawText(content, orderCache, subAccountLabel, kind)
  if n > 0 then
    print("ABA harvest", job.reportType, job.span, "new=", n)
  end
  return n
end

function harvestAbaReportContent(reportType, span, landingRaw, fromParts, toParts)
  local logPrefix="ABA report "..reportType.." "..span
  local pageHtml=type(landingRaw) == 'string' and landingRaw or ''
  return tryHarvestAbaCsvFromHtmlPage(pageHtml, reportType, span, landingRaw, logPrefix, fromParts, toParts)
end

function failAbaReportsSession(logMsg, statusMsg)
  print(logMsg)
  MM.printStatus(statusMsg)
  return false, nil, statusMsg
end

function loadAbaReportsSession()
  print("Business: open ABA landing")
  local landing=fetchAbaGetContent(buildAbaLandingUrl())
  if landing == nil then
    return failAbaReportsSession("ABA landing unreachable",
      "Amazon Business Analytics nicht erreichbar")
  end
  if isAmazonSignInPageHtml(landing) then
    return failAbaReportsSession("ABA landing redirected to sign-in",
      "Amazon Business Analytics: Anmeldung erforderlich")
  end
  if not isAbaLandingReady(landing) then
    return failAbaReportsSession("ABA landing missing report UI",
      "Amazon Business Analytics: Berichtsseite nicht erreichbar")
  end
  return true, landing, nil
end

--- @function collectOrdersFromAbaReports
-- Business identity: order list is SPA-only; harvest order ids from ABA items_report.
-- @return newCount, errString
function collectOrdersFromAbaReports(subAccountLabel, kind, refreshSince)
  local orderCache=ensureOrderCache()
  local now=os.time()
  logAbaHarvestMode(refreshSince, now)
  local sessionOk, landing, sessionErr=loadAbaReportsSession()
  if not sessionOk then
    return nil, sessionErr or "Amazon Business Analytics nicht erreichbar"
  end
  local job=abaPrimaryReportJob(refreshSince, now, const.abaItemsReportType)
  local totalNew=harvestAbaReportJob(job, landing, orderCache, subAccountLabel, kind)
  if totalNew == 0 then
    MM.printStatus("Amazon Business: keine Bestellnummern in ABA-Berichten gefunden")
  else
    print("ABA harvest total new=", totalNew)
  end
  return totalNew, nil
end

--- @function collectBusinessSpaOrders
-- Business: ABA items_report for ≤12 months; full harvest also GET year filters outside that window.
-- ABA session failure aborts (no Gap-GET pretending the last 12 months were covered).
-- @return newCount, errString
function collectBusinessSpaOrders(subAccountLabel, kind, refreshSince)
  print("Business SPA harvest: ABA items_report; GET years only on full harvest")
  local now=os.time()
  local nAba, abaErr=collectOrdersFromAbaReports(subAccountLabel, kind, refreshSince)
  if abaErr ~= nil then
    return nil, abaErr
  end
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return nAba, nil
  end
  local nGet=collectOrdersViaYourOrdersGet(subAccountLabel, kind, refreshSince, {
    fullHarvest=true,
    abaGapOnly=true,
  })
  if nGet > 0 then
    print("Business GET harvest (years outside ABA window) new=", nGet)
  end
  return nAba + nGet, nil
end

function tryEnterOrderListGet(url, logMsg)
  if logMsg ~= nil then
    print(logMsg)
  end
  local page=connectShop("GET", url)
  if orderListPageReady(page) then
    html=page
    return true
  end
  return false
end

--- @function enterOrderList
-- Opens scrapable order history. Business: css order-history (not SPA nav).
function enterOrderList ()
  if html ~= nil and isAmazonBusinessSession(html) then
    print("Business session: open css order-history")
    if tryEnterOrderListGet(buildCssOrderHistoryUrl(nil)) then
      return
    end
  end
  if html ~= nil then
    local nav=html:xpath(const.xpathOrderHistoryLink)
    if nav:length() > 0 then
      local nextHtml=connectShop(nav:click())
      if orderListPageReady(nextHtml) then
        html=nextHtml
        return
      end
      -- Keep non-ready HTML (e.g. Business SPA shell) so collectOrdersFromOrderList
      -- can route to ABA harvest instead of pretending the classic form exists.
      if nextHtml ~= nil then
        html=nextHtml
      end
    end
  end
  if tryEnterOrderListGet(buildCssOrderHistoryUrl(nil)) then
    return
  end
  if tryEnterOrderListGet(baseurl..const.orderListLink) then
    return
  end
  print("order list page not ready")
end

--- @function submitOrderTimeFilter
-- Selects a timeFilter/orderFilter and loads the result page.
-- Returns next html or nil when the classic order form is missing (B2B shell).
function submitOrderTimeFilter(htmlNode, orderFilterVal)
  if htmlNode == nil or type(orderFilterVal) ~= 'string' or orderFilterVal == '' then
    return nil
  end
  local form=htmlNode:xpath(const.xpathOrderMonthForm)
  if form:length() == 0 then
    print("no order filter form for", orderFilterVal)
    return nil
  end
  htmlNode:xpath(const.xpathOrderMonthSelect):select(orderFilterVal)
  return connectShop(form:submit())
end

--- @function buildCssOrderHistoryUrl
-- gp/css order-history serves order-card HTML on Business sessions; the Business
-- nav link (abn_yadd_ad_your_orders) and /ab/your-orders land on the SPA shell.
function buildCssOrderHistoryUrl(filterVal)
  local url=baseurl..const.cssOrderHistoryPath..'?ref_='..const.cssOrderHistoryRef
  if type(filterVal) == 'string' and filterVal ~= '' then
    url=url..'&timeFilter='..MM.urlencode(filterVal)
  end
  return url
end

--- @function buildYourOrdersTimeFilterUrl
-- GET URL used by the retail your-orders UI (also valid after Business account switch).
function buildYourOrdersTimeFilterUrl(filterVal)
  if type(filterVal) ~= 'string' or filterVal == '' then
    return nil
  end
  return baseurl..const.yourOrdersTimeFilterPath
    ..'?timeFilter='..MM.urlencode(filterVal)
    ..'&ref_='..const.yourOrdersTimeFilterRef
end

function buildClassicOrderFilterUrl(filterVal)
  if type(filterVal) ~= 'string' or filterVal == '' then
    return nil
  end
  return baseurl..const.classicOrderFilterPath
    ..'&orderFilter='..MM.urlencode(filterVal)
end

function recentYourOrdersGetFilters()
  return {
    {val='last30', label='den letzten 30 Tagen'},
    {val=const.recentMonthsFilter, label='den letzten 3 Monaten'},
  }
end

function appendYearGetFilters(list, now, includeYear)
  local asOf=os.date('*t', now)
  if asOf == nil or type(includeYear) ~= 'function' then
    return
  end
  local y=tonumber(os.date('%Y', now))
  if y == nil then
    return
  end
  for year=y, 2000, -1 do
    local val='year-'..tostring(year)
    if includeYear(val, asOf) then
      table.insert(list, {val=val, label=tostring(year)})
    end
  end
end

--- @function enumerateYourOrdersGetFilters
-- last30 / months-3 / year-YYYY — same windows personal harvest uses via the form.
function enumerateYourOrdersGetFilters(refreshSince, now)
  now=now or os.time()
  local scanMonths=effectiveScanFiltersMonths(refreshSince, now)
  local list=recentYourOrdersGetFilters()
  appendYearGetFilters(list, now, function(val, asOf)
    return orderFilterWithinScanMonths(val, scanMonths, asOf)
  end)
  return list
end

--- Year-only GET filters for orders older than the ABA preset window (PAST_12_MONTHS).
function enumerateYourOrdersGetFiltersForAbaGap(now)
  now=now or os.time()
  local list={}
  appendYearGetFilters(list, now, function(val, asOf)
    return not orderFilterWithinScanMonths(val, const.abaCoverageMonths, asOf)
  end)
  return list
end

--- @function loadYourOrdersFilterPage
-- Loads a timeFilter page via GET. css order-history first (Business-safe).
function loadYourOrdersFilterPage(filterVal)
  local urls={
    buildCssOrderHistoryUrl(filterVal),
    buildYourOrdersTimeFilterUrl(filterVal),
    buildClassicOrderFilterUrl(filterVal),
  }
  local lastPage=nil
  for _, url in ipairs(urls) do
    if type(url) == 'string' and url ~= '' then
      local page, akamaiErr=resolveAkamaiInterstitial(connectShop('GET', url))
      if akamaiErr ~= nil then
        print("Akamai on order filter GET:", akamaiErr)
      end
      lastPage=page
      if orderListPageReady(page) then
        return page
      end
    end
  end
  return lastPage
end

function bindActiveHtml(htmlNode)
  if htmlNode ~= nil then
    html=htmlNode
  end
end

function sessionMatchesSubAccountKind(kind)
  if html == nil or type(kind) ~= 'string' or kind == '' then
    return false
  end
  if kind == 'business' then
    return isAmazonBusinessSession(html) or isAmazonBusinessOrdersSpa(html)
  end
  if kind == 'personal' then
    return not isAmazonBusinessSession(html)
  end
  return false
end

function businessGetHarvestBlockedBySpaShell()
  local cssPage=connectShop('GET', buildCssOrderHistoryUrl('last30'))
  if cssPage ~= nil then
    local resolved=resolveAkamaiInterstitial(cssPage)
    if resolved ~= nil and orderListPageReady(resolved) then
      return false
    end
  end
  local probe=loadYourOrdersFilterPage('last30')
  return probe ~= nil and isAmazonBusinessOrdersSpa(probe) and not orderListPageReady(probe)
end

function harvestGetOrderFilter(orderFilterVal, label, orderFilterCache, subAccountLabel, kind)
  MM.printStatus('Amazon Bestellübersicht: "'..label..'"')
  html=loadYourOrdersFilterPage(orderFilterVal)
  if html == nil then
    print("GET timeFilter failed", orderFilterVal)
    return 0
  end
  if not orderListPageReady(html) then
    print("GET timeFilter not ready", orderFilterVal)
    if not isRecentOrderFilter(orderFilterVal) and not isAmazonBusinessOrdersSpa(html) then
      markOrderFilterCacheIfComplete(orderFilterCache, orderFilterVal, false)
    end
    return 0
  end
  local orderCache=ensureOrderCache()
  local _, _, newCount=scanOrderFilterPages(orderFilterVal, orderCache, orderFilterCache, subAccountLabel, kind)
  if newCount > 0 then
    print("harvested "..newCount.." new order(s) from filter "..orderFilterVal)
  end
  return newCount
end

--- @function collectOrdersViaYourOrdersGet
-- Harvest orders with GET timeFilter URLs. Used when Business lands on the SPA
-- shell: POST /ab/your-orders/orderHistory returns Forbidden in MoneyMoney and
-- aborts the whole refresh.
function collectOrdersViaYourOrdersGet(subAccountLabel, kind, refreshSince, opts)
  opts=type(opts) == 'table' and opts or {}
  print("SPA/Business shell: harvest via GET timeFilter (css order-history first)")
  ensureOrderCache()
  if businessGetHarvestBlockedBySpaShell() then
    print("Business GET timeFilter returns SPA shell only; skip GET harvest")
    if opts.fullHarvest then
      MM.printStatus("Amazon Business: Bestellliste per GET nicht verfügbar – ggf. fehlen Bestellungen älter als 12 Monate")
    end
    return 0
  end
  local now=os.time()
  local filters
  if opts.abaGapOnly then
    print("GET harvest: year filters outside ABA window only")
    filters=enumerateYourOrdersGetFiltersForAbaGap(now)
  else
    filters=enumerateYourOrdersGetFilters(refreshSince, now)
  end
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  local totalNew=0
  for _, item in ipairs(filters) do
    if shouldHarvestOrderFilter(item.val, orderFilterCache, totalNew, refreshSince, now) then
      totalNew=totalNew
        + harvestGetOrderFilter(item.val, item.label, orderFilterCache, subAccountLabel, kind)
    end
  end
  return totalNew
end

--- @function collectOrdersFromOrderList
-- Scrapes order-history filters for the currently active Amazon sub-account.
-- @return newCount, errString
function collectOrdersFromOrderList(subAccountLabel, kind, refreshSince)
  enterOrderList()
  if html == nil then
    print("collectOrdersFromOrderList: no order list html for", tostring(subAccountLabel))
    return 0, nil
  end
  if isAmazonBusinessOrdersSpa(html) and not orderListPageReady(html) then
    return collectBusinessSpaOrders(subAccountLabel, kind, refreshSince)
  end
  local orderCache=ensureOrderCache()
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  local orderFilterSelect=html:xpath(const.xpathOrderMonthSelect):children()
  local numbersOfNewOrders=0
  local scannedFilters={}
  local now=os.time()
  local scanMonths=effectiveScanFiltersMonths(refreshSince, now)
  if scanMonths ~= nil and scanMonths > 0 then
    print("scanFiltersMonths=", scanMonths)
  end

  local function harvestFilter(orderFilterVal, statusLabel, submitFilter)
    if scannedFilters[orderFilterVal]
        or not shouldHarvestOrderFilter(orderFilterVal, orderFilterCache, numbersOfNewOrders, refreshSince, now) then
      return
    end
    MM.printStatus('Amazon Bestellübersicht: "'..statusLabel..'"')
    if submitFilter then
      local nextHtml=submitOrderTimeFilter(html, orderFilterVal)
      if nextHtml == nil then
        print("skip filter", orderFilterVal, "(submit failed or no form)")
        scannedFilters[orderFilterVal]=true
        return
      end
      html=nextHtml
    end
    local _, _, newCount=scanOrderFilterPages(orderFilterVal, orderCache, orderFilterCache, subAccountLabel, kind)
    numbersOfNewOrders=numbersOfNewOrders+newCount
    if newCount > 0 then
      print("harvested "..newCount.." new order(s) from filter "..orderFilterVal)
    end
    scannedFilters[orderFilterVal]=true
  end

  local selectedFilterVal=getSelectedOrderFilter(html)
  if selectedFilterVal ~= '' then
    harvestFilter(selectedFilterVal, getSelectedOrderFilterLabel(html, selectedFilterVal), false)
  end

  orderFilterSelect:each(function(index,element)
    harvestFilter(element:attr('value'), element:text(), true)
    return true
  end)

  return numbersOfNewOrders, nil
end

function findSubAccountByKind(options, kind)
  for _,opt in ipairs(options) do
    if opt.kind == kind then
      return opt
    end
  end
  return nil
end

function subAccountNumberForKind(kind)
  if kind == "personal" then
    return "sub:personal"
  end
  if kind == "business" then
    return "sub:business"
  end
  if type(kind) == 'string' and kind ~= '' then
    return "sub:"..kind
  end
  return nil
end

function rememberDiscoveredSubAccounts(options)
  LocalStorage.discoveredSubAccounts={}
  if type(options) ~= 'table' then
    return
  end
  for _,opt in ipairs(options) do
    local accountNumber=subAccountNumberForKind(opt.kind)
    if accountNumber ~= nil and type(opt.label) == 'string' and opt.label ~= '' then
      table.insert(LocalStorage.discoveredSubAccounts, {
        kind=opt.kind,
        label=opt.label,
        accountNumber=accountNumber,
      })
    end
  end
end

function isCombinedMoneyMoneyAccount(accountNumber)
  if accountNumber == nil or accountNumber == '' then
    return true
  end
  return string.sub(tostring(accountNumber), 1, 4) ~= "sub:"
end

--- @function backfillSubAccountKind
-- Legacy OrderCache entries may have accountNumber (Amazon label) but no
-- subAccountKind. Infer kind from discoveredSubAccounts when labels match.
function backfillSubAccountKind(order)
  if type(order) ~= 'table' then
    return
  end
  if type(order.subAccountKind) == 'string' and order.subAccountKind ~= '' then
    return
  end
  local label=order.accountNumber
  if type(label) ~= 'string' or label == '' then
    return
  end
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) ~= 'table' then
    return
  end
  for _,sub in ipairs(discovered) do
    if type(sub) == 'table' and sub.label == label and type(sub.kind) == 'string' and sub.kind ~= '' then
      order.subAccountKind=sub.kind
      return
    end
  end
end

function orderMatchesMoneyMoneyAccount(order, accountNumber)
  if type(order) ~= 'table' then
    return false
  end
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return true
  end
  local wantKind=string.match(tostring(accountNumber), "^sub:(.+)$")
  if wantKind == nil then
    return true
  end
  backfillSubAccountKind(order)
  return order.subAccountKind == wantKind
end

--- @function orderNeedsDetailsForAccount
-- True when order details are stale and the order belongs to this MoneyMoney account.
function orderNeedsDetailsForAccount(order, now, accountNumber)
  if type(order) ~= 'table' or type(now) ~= 'number' then
    return false
  end
  if type(order.detailsDate) ~= 'number' or not (order.detailsDate < now) then
    return false
  end
  return orderMatchesMoneyMoneyAccount(order, accountNumber)
end

function accountNumberIsKnown(knownAccounts, accountNumber)
  if type(knownAccounts) ~= 'table' or accountNumber == nil then
    return false
  end
  for _,entry in pairs(knownAccounts) do
    if entry == accountNumber then
      return true
    end
    if type(entry) == 'table' and entry.accountNumber == accountNumber then
      return true
    end
  end
  return false
end

--- @function markAccountNeedsInitialReload
-- Force "Please reload!" only for newly offered accounts. Do not reset getOrders
-- for accounts MoneyMoney already knows (avoids reload loop on ListAccounts).
function markAccountNeedsInitialReload(accountNumber, knownAccounts)
  if LocalStorage.getOrders == nil then
    LocalStorage.getOrders={}
  end
  if accountNumberIsKnown(knownAccounts, accountNumber) then
    if LocalStorage.getOrders[accountNumber] == nil then
      LocalStorage.getOrders[accountNumber]=false
    end
    return
  end
  LocalStorage.getOrders[accountNumber]=false
end

function clearSubAccountScanState()
  if LocalStorage ~= nil then
    LocalStorage.subAccountScan=nil
  end
end

function subAccountScanMatchesRefresh(state)
  if type(state) ~= 'table' or type(LocalStorage.refreshSince) ~= 'number' then
    return false
  end
  return type(state.harvestSince) == 'number' and state.harvestSince == LocalStorage.refreshSince
end

function newSubAccountScanDoneState(totalNew, incomplete)
  return {
    phase='done',
    totalNew=totalNew or 0,
    incomplete=incomplete and true or false,
    loginCounter=LocalStorage.loginCounter,
    harvestSince=LocalStorage.refreshSince,
    plan={},
    index=1,
  }
end

function harvestSubAccountPlanEntry(label, kind)
  return collectOrdersFromOrderList(label, kind, LocalStorage.refreshSince)
end

function addHarvestedOrders(state, label, kind)
  local n, err=harvestSubAccountPlanEntry(label, kind)
  if err ~= nil then
    clearSubAccountScanState()
    return err
  end
  state.totalNew=state.totalNew+(n or 0)
  return nil
end

function resolveSubAccountScanCache()
  local state=LocalStorage.subAccountScan
  if state == nil or state.phase ~= 'done' or state.loginCounter ~= LocalStorage.loginCounter then
    return nil
  end
  if state.incomplete then
    print("sub-account scan incomplete; retrying")
    LocalStorage.subAccountScan=nil
    return nil
  end
  if subAccountScanMatchesRefresh(state) then
    print("sub-account scan already completed for refreshSince=", tostring(state.harvestSince),
      "new orders=", state.totalNew)
    return state.totalNew or 0
  end
  print("sub-account scan stale (refreshSince changed); re-harvesting")
  LocalStorage.subAccountScan=nil
  return nil
end

function completeSubAccountScan(state, incomplete)
  if type(state) ~= 'table' then
    return
  end
  state.incomplete=incomplete and true or false
  state.phase='done'
  state.harvestSince=LocalStorage.refreshSince
end

function continueMfaSubAccountSwitch(state, otpCode)
  if type(otpCode) ~= 'string' or otpCode == '' then
    return mfaChallengeFromHtml(html) or {
      title='Amazon Konto wechseln – 2FA',
      challenge='Bitte den Bestätigungscode für den Amazon-Kontenwechsel eingeben.',
      label='Code'
    }
  end
  local want=state.plan[state.index]
  if type(want) ~= 'table' then
    clearSubAccountScanState()
    return "Amazon Unterkonto-Scan: kein Eintrag nach 2FA"
  end
  local nextHtml, err=submitAmazonMfa(html, otpCode)
  if err ~= nil then
    clearSubAccountScanState()
    return "Amazon 2FA fehlgeschlagen: "..err
  end
  local land=finishAccountSwitchLanding(nextHtml, {switchKind=want.kind})
  if land.needsMfa then
    return land.challenge
  end
  if land.error then
    clearSubAccountScanState()
    return "Amazon Kontowechsel nach 2FA fehlgeschlagen: "..land.error
  end
  MM.printStatus("Amazon: Unterkonto \""..want.label.."\"")
  local harvestErr=addHarvestedOrders(state, want.label, want.kind)
  if harvestErr ~= nil then
    return harvestErr
  end
  state.index=state.index+1
  state.phase='running'
  return runSubAccountScanLoop()
end

function beginSubAccountScanPlan(options)
  local plan={}
  for _,opt in ipairs(options) do
    table.insert(plan, {kind=opt.kind, label=opt.label})
  end
  LocalStorage.subAccountScan={
    phase='running',
    plan=plan,
    index=1,
    totalNew=0,
    incomplete=false,
    loginCounter=LocalStorage.loginCounter,
  }
end

--- @function runSubAccountScanLoop
-- Switches+scrapes remaining plan entries. May return an MFA challenge table.
-- Hard switch / ABA failures return an error string (no silent skip).
function runSubAccountScanLoop()
  local state=LocalStorage.subAccountScan
  if state == nil then
    return "Amazon Unterkonto-Scan: kein Status"
  end
  while state.index <= #state.plan do
    local want=state.plan[state.index]
    local page=openAccountSwitcherEmbed()
    if page == nil then
      clearSubAccountScanState()
      return "Amazon: Account-Switcher nicht verfügbar – Unterkonto \""
        ..tostring(want.label).."\" nicht erreichbar"
    end
    local options=parseAccountSwitcher(page)
    local match=findSubAccountByKind(options, want.kind)
    if match == nil then
      clearSubAccountScanState()
      return "Amazon-Unterkonto nicht im Switcher: "..tostring(want.label)
    end
    local result=switchAmazonSubAccount(match)
    if result.needsMfa then
      state.phase='await_mfa'
      print("switch requires MFA for "..tostring(match.label))
      return result.challenge
    end
    if result.error then
      clearSubAccountScanState()
      return "Amazon Kontowechsel fehlgeschlagen ("..tostring(match.label).."): "..result.error
    end
    MM.printStatus("Amazon: Unterkonto \""..match.label.."\"")
    local harvestErr=addHarvestedOrders(state, match.label, match.kind)
    if harvestErr ~= nil then
      return harvestErr
    end
    state.index=state.index+1
  end
  completeSubAccountScan(state, false)
  print("sub-account scan done, new orders=", state.totalNew)
  return nil
end

--- @function continueSubAccountScan
-- Drives personal+business harvest. otpCode required when phase=await_mfa.
-- @return nil on success, challenge table for MFA, or error string
function continueSubAccountScan(otpCode)
  local state=LocalStorage.subAccountScan
  if state ~= nil and state.phase == 'done' then
    return nil
  end
  if state ~= nil and state.phase == 'await_mfa' then
    return continueMfaSubAccountSwitch(state, otpCode)
  end
  if state == nil or state.phase ~= 'running' then
    return startSubAccountScan()
  end
  return runSubAccountScanLoop()
end

--- @function discoverAmazonSubAccounts
-- ListAccounts / "Nach neuen Konten suchen": only parse the CVF switcher.
-- Does not switch accounts and does not load orders (no Umsätze).
-- @return #table switcher options (may be empty)
function discoverAmazonSubAccounts()
  MM.printStatus("Amazon: Unterkonten werden ermittelt…")
  local switcherHtml=openAccountSwitcherEmbed()
  local options={}
  if switcherHtml ~= nil then
    options=parseAccountSwitcher(switcherHtml)
  end
  rememberDiscoveredSubAccounts(options)
  local n=0
  if type(LocalStorage.discoveredSubAccounts) == 'table' then
    n=#LocalStorage.discoveredSubAccounts
  end
  print("discovered Amazon sub-accounts=", n)
  return options
end

function startSubAccountScan()
  local options=discoverAmazonSubAccounts()
  if #options == 0 then
    print("no switchable Amazon sub-accounts, scraping current session")
    local n, err=harvestSubAccountPlanEntry("", nil)
    if err ~= nil then
      return err
    end
    LocalStorage.subAccountScan=newSubAccountScanDoneState(n or 0, false)
    return nil
  end
  beginSubAccountScanPlan(options)
  return runSubAccountScanLoop()
end

--- @function scanAllAmazonSubAccounts
-- Used from RefreshAccount only (not during account search). Harvests orders
-- for all Amazon sub-accounts into OrderCache. Prefers a scan already completed
-- in this login session; incomplete scans are retried. MFA mid-Refresh clears
-- await_mfa and asks for re-login (Refresh cannot complete OTP challenges).
-- Returns newCount or nil, errString.
function scanAllAmazonSubAccounts()
  local cachedTotal=resolveSubAccountScanCache()
  if cachedTotal ~= nil then
    return cachedTotal, nil
  end
  local r=continueSubAccountScan(nil)
  if type(r) == 'table' and r.title ~= nil then
    clearSubAccountScanState()
    return nil, "Amazon verlangt 2FA beim Unterkonto-Wechsel. Bitte abmelden und erneut anmelden."
  end
  if type(r) == 'string' then
    return nil, r
  end
  local state=LocalStorage.subAccountScan
  return (state and state.totalNew) or 0, nil
end

function getMessageListURL(ajaxToken,page,pageToken)
  local fields={
    messageType='all',
    startDateTime=1000,
    endDateTime=3167942400000,
    pageSize=10,
    pageNum=page,
    sourcePage='inbox',
    isMobile=0,
    pageToken=pageToken,
    token=ajaxToken,
    stringDebug='',
    isDebug=''
  }
  local t={}
  for k,v in pairs(fields) do
    if v ~= nil then
      table.insert(t,k..'='..MM.urlencode(v))
    end
  end
  return '/gp/message/ajax/message-list.html?'..table.concat(t,"&")
end

function getMessageURL(ajaxToken,messageId,threadId,messageDateTime)
  local fields={
    messageId=messageId,
    threadId=threadId,
    messageType='all',
    sourcePage='inbox',
    messageDateTime=messageDateTime,
    isMobile=0,
    token=ajaxToken,
    stringDebug='',
    isDebug=''
  }
  local t={}
  for k,v in pairs(fields) do
    if v ~= nil then
      table.insert(t,k..'='..MM.urlencode(v))
    end
  end
  return '/gp/message/ajax/message-content.html?'..table.concat(t,"&")
end


function getMessageList(since)
  since=since*1000 -- in milliseconds
  local orderIds={}
  local html=connectShop("GET","/gp/message")
  -- After account switching Amazon sometimes serves the sign-in page here.
  local title=html:xpath('//title'):text()
  if switchAuthBlockReason(html) ~= nil
      or (type(title) == 'string' and (title:find("Anmelden") or title:find("Sign[- ]?[Ii]n"))) then
    print("message center requires login, skipping Amazon message center check")
    return orderIds
  end
  local ajaxToken=html:xpath('//script[contains(@type,"a-state")]'):text()
  ajaxToken=string.match(ajaxToken,'{"token":"([A-Za-z0-9]+)"}')
  print("ajaxToken",ajaxToken)
  if ajaxToken == nil or ajaxToken == "" then
    -- new page layout no longer exposes the a-state token; skip the
    -- message-center check rather than guess at a broken request URL
    print("no ajaxToken found, skipping Amazon message center check")
    return orderIds
  end
  local page=1
  local messages={}
  local nextPageToken
  repeat
    MM.printStatus("Get page",page,"from Amazon message center.")
    local html
    local noNextPage=true
    local json=connectShopJson("GET",getMessageListURL(ajaxToken,page,nextPageToken))
    if json.html ~= nil then
      html=HTML("<html><body>"..json['html'].."</html></body>")
      json.html = nil
    end
    if json.nextPageToken~= nil then
      nextPageToken=json.nextPageToken
      noNextPage=true
    end
    --debugBuffer.flush()

    local newMessages=false
    html:xpath('//td'):each(function(index,td)
      local message={}
      for _,k in pairs({'messageSentTime','message-sent-time-in-ms','messageId','message-id','threadId','thread-id'}) do
        message[k]=td:attr(k:lower())
      end
      if message['message-sent-time-in-ms'] ~= '' then
        message.messageSentTime=message['message-sent-time-in-ms']
        message.threadId=message['threadId']
        message.messageId=message['message-id']
      end
      if tonumber(message.messageSentTime) > since then
        messages[message.messageId]=message
        newMessages=true
      end
      debugBuffer.print(message)
    end)
    --debugBuffer.print(page,json)
    if not newMessages then
      noNextPage=true
    end
    page=page+1
  until noNextPage
  local numAll=0
  local num=0
  for _,v in pairs(messages) do
    numAll=numAll+1
  end
  for _,v in pairs(messages) do
    num=num+1
    MM.printStatus("Get Amazon message",num,"of",numAll)
    local html
    local json=connectShopJson("GET",getMessageURL(ajaxToken,v.messageId,v.threadId,v.messageSentTime))
    if json.html ~= nil then
      html=HTML("<html><body>"..json['html'].."</html></body>")
    else
      html=''
    end
    for orderId in html:html():gmatch(const.regexOrderCodeNew) do
      orderIds[orderId]=tonumber(v.messageSentTime)/1000 -- in milliseconds
    end
  end
  local numOrders=0
  for k,v in pairs(orderIds) do
    numOrders=numOrders+1
  end
  print(numOrders,"orders from messages")
  --debugBuffer.print(orderIds)
  --debugBuffer.flush()
  return orderIds
end

function getLastDayOfPeriod(period)
  local year=string.match(period,"(%d%d%d%d)")
  local month=string.match(period,"-(%d%d)")
  --debugBuffer.print("getLastDayOfPeriod",period,year,month)
  if month == nil then
    month="12"
  end
  year=tonumber(year)
  month=tonumber(month)
  local day=const.daysByMonth[month]
  if month == 2 and (year%4) == 0 and ((year%400)==0 or (year%100)~=0) then
    day=29
  end
  return os.time{year=year,month=month,day=day}
end

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and "Amazon Orders" == bankCode:sub(1,#"Amazon Orders")
end

function endsWith(string,ending)
  return string:sub(-#ending) == ending
end

--- @function applyAccountAttribute
-- Applies one account note / patcher key to config/const.
-- allowConfigStrings: RefreshAccount also overwrites string config values.
function applyAccountAttribute(k, v, allowConfigStrings)
  if type(config[k]) == 'boolean' then
    local flag=(v == 'true')
    print("set config",k,"=", flag and "true" or "false")
    config[k]=flag
  end
  if type(config[k]) == 'number' then
    local n=tonumber(v)
    if n ~= nil then
      print("set config",k,n)
      config[k]=n
    else
      print("ignore non-numeric config",k,v)
    end
  end
  if allowConfigStrings and type(config[k]) == 'string' then
    print("set config",k,v)
    config[k]=v
  end
  if type(const[k]) == 'string' then
    print("const k=",v)
    const[k]=v
  end
end

function InitializeSession2 (protocol, bankCode, step, credentials, interactive)
  -- Login.
  if type(LocalStorage.patcher) == 'table' then
    for k,v in pairs(LocalStorage.patcher) do
      print("attribut",k,v)
      applyAccountAttribute(k, v, false)
    end
  end

  -- Resume Amazon sub-account switch MFA (returned as challenge after login success).
  if LocalStorage.subAccountScan ~= nil and LocalStorage.subAccountScan.phase == 'await_mfa' then
    local scanResult=continueSubAccountScan(credentials[1])
    if type(scanResult) == 'table' and scanResult.title ~= nil then
      return scanResult
    end
    if type(scanResult) == 'string' then
      return scanResult
    end
    return nil
  end

  if step==1 then
    if LocalStorage.getOrders == nil then
      LocalStorage.getOrders={}
    end
    rememberShopCredentials(credentials[1], credentials[2])
    captcha1run=true
    mfa1run=true
    aName=nil
    clearSubAccountScanState()

    if LocalStorage.loginCounter == nil then
      LocalStorage.loginCounter=0
    end
    LocalStorage.loginCounter=LocalStorage.loginCounter+1
    print("run=",LocalStorage.loginCounter)

    if config.debug then
      webCache=os.rename(webCacheFolder,webCacheFolder) and true or false
      if webCache then
        print("webcache on")
        config.limitOrders=1e99
        local temp=webCacheFolder.."/cleanLocalStorage"
        local cleanLocalStorage=os.rename(temp,temp) and true or false
        if cleanLocalStorage then
          print("clean LocalStorage")
          LocalStorage.OrderCache={}
          clearOrderFilterCaches()
          LocalStorage.newestMessage=0
          LocalStorage.balancesByPeriod={}
        end
      end
    end
    html = connectShop("GET",baseurl)
    enterOrderList()
  end

  local leaveLoginLoop
  local loginLoops=1
  repeat
    leaveLoginLoop=true
    webCacheState="login"..loginLoops
    print("login "..loginLoops..". try")

    -- $x('//div[@id="auth-error-message-box"]')
    local authError=html:xpath('//div[@id="auth-error-message-box"]'):text()

    if authError ~= '' then
      MM.printStatus(authError)
      print('login failed, clean cookies text')
      LocalStorage.cookies=nil
      return LoginFailed
    end



    -- authlink
    --
    -- $x('//form[@id="pollingForm"]')
    -- $x('//input[@name="transactionApprovalStatus"]')
    -- <input type="hidden" name="transactionApprovalStatus" value="TransactionPending">
    -- <input type="hidden" name="transactionApprovalStatus" value="TransactionCompleted">
    --

    local authLink=html:xpath('//form[@id="pollingForm"]')
    if authLink:attr('id') ~='' then
      print("auth link sended")
      local waitUntil=os.time()+300
      local poll
      repeat
        MM.printStatus("waiting for auth confirmation, "..math.floor(waitUntil-os.time()).." seconds left")
        MM.sleep(3)
        poll=connectShop(authLink:submit()):xpath('//input[@name="transactionApprovalStatus"]'):attr('value')
        print("poll="..poll)
      until( poll == 'TransactionCompleted' or waitUntil<os.time())
      enterOrderList()
    end



    -- Account selector
    -- https://www.amazon.de/ap/cvf/request.embed?arb=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&CVFVersion=0.1.0.0-2020-12-30&AUIVersion=3.19.8-2020-12-30
    -- arb= $x('//div[@data-arbtoken]')
    -- $x('//div[@id="authportal-main-section"]')
    --
    local arbToken=html:xpath('//div[@data-arbtoken]'):attr('data-arbtoken')
    if arbToken ~= '' then
      print("account selector")
      leaveLoginLoop=false
      print('Account selector arbToken='..arbToken)
      local embed=accountSwitcherEmbedUrl(arbToken, cvfEmbedVersionQuery(html))
      html=connectShop('GET', absoluteAmazonUrl(embed))
      leaveLoginLoop=false
      -- work-a-round simple add new login
      local signInLink=html:xpath('//a[@id="cvf-account-switcher-add-accounts-link"]'):attr('href')
      print('signInLink='..signInLink)
      if signInLink ~= '' then
        html=connectShop('GET',signInLink)
      end
    end

    -- auth select
    --

    local authSelect=html:xpath('//form[@id="auth-select-device-form"]')
    if authSelect:text() ~= ''  then
      print("auth selector")
      leaveLoginLoop=false
      -- name="otpDeviceContext"
      local otpDeviceContext=''
      local score=-1000
      authSelect:xpath('.//input[@type="radio"]'):each(function (index,element)
        local k=element:attr('value')
        local v=0
        if endsWith(k,'TOTP') then
          v=10
        end
        if endsWith(k,'VOICE') then
          v=-10
        end
        if endsWith(k,'SMS') then
          v=5
        end
        if score<v then
          otpDeviceContext=k
          score=v
        end
      end)
      authSelect:xpath('.//input[@type="radio"]'):each(function (index,element)
        if element:attr('value') == otpDeviceContext then
          element:attr('checked','checked')
          print("select "..element:xpath('..'):text())
        else
          element:attr('checked','')
        end
      end)
      html=connectShop(authSelect:submit())
    end

    -- new captcha?
    -- ('//form[@action="/errors/validateCaptcha"]')
    -- ('//form[@action="/errors/validateCaptcha"]//img')
    -- ('//input[@id="captchacharacters"]')

    -- local captcha=html:xpath('//form[@action="/errors/validateCaptcha"]')
    -- if captcha:text() ~= "" then
    --     leaveLoginLoop=false
    --   -- untested...
    --   print("untested ****************************")
    --   if config.debug then print("login new captcha") end
    --   if captcha1run then
    --     local pic=connectShopRaw("GET",captcha:xpath('.//img'):attr('src'))
    --     captcha1run=false
    --     return {
    --       title=captcha:xpath('.//label'):text(),
    --       challenge=pic,
    --       label=captcha:xpath('.//form//h4'):text()
    --     }
    --   else
    --     captcha:xpath('.//input[@id="captchacharacters"]'):attr("value",credentials[1])
    --     html=connectShop(captcha:submit())
    --     captcha1run=true
    --   end
    -- end
    --

    -- Captcha
    --
    local captcha=html:xpath('//img[@id="auth-captcha-image"]'):attr('src')
    --div id="image-captcha-section"
    if captcha ~= "" then
      print("captcha")
      leaveLoginLoop=false
      if config.debug then print("login captcha") end
      if captcha1run then
        local pic=connectShopRaw("GET",captcha)
        captcha1run=false
        return {
          title=html:xpath('//li'):text(),
          challenge=pic,
          label=html:xpath('//form//h4'):text()
        }
      else
        html:xpath('//*[@name="guess"]'):attr("value",credentials[1])
        -- checkbox
        html:xpath('//*[@name="rememberMe"]'):attr('checked','checked')
        html:xpath('//*[@name="password"]'):attr("value",secPassword)
        captcha1run=true
      end
    end

    -- passcode

    if html:xpath('//form[@name="claimspicker"]'):text() ~= ''  then
      print("passcode")
      leaveLoginLoop=false
      local text=''
      local number=0
      local passcode1run=true
      if config.debug then print("passcode 1. part") end
      html:xpath('//input[@type="radio"]'):each(function (index,element)
        text=text..index..". "..element:xpath('..'):text().."\n"
        number=index
        if  tonumber(index) == tonumber(credentials[1]) then
          element:attr('checked','checked')
          if config.debug then print("select",element:xpath('..'):text()) end
          passcode1run=false
        else
          element:attr('checked','')
        end
        --print(index,element:xpath('..'):text(),element:attr('checked'))
      end)
      if number == 0 then
        -- no selectable options
        html= connectShop(html:xpath('//form[@name="claimspicker"]'):submit())
        if html:xpath('//form[@action="verify"]'):text() ~= '' then
          return {
            title=html:xpath('//form[@action="verify"]//div[1]//div[1]'):text(),
            challenge=html:xpath('//form[@action="verify"]//div[1]//div[2]'):text(),
            label='Code'
          }
        end
      else
        if passcode1run then
          passcode1run=false
          -- ask for passcode methode, feature request select field when return value a table?
          return {
            title=html:xpath('//form[@action="claimspicker"]//div[1]'):text(),
            challenge=text,
            label='Please select 1-'..number
          }
        else
          html= connectShop(html:xpath('//form[@name="claimspicker"]'):submit())
          if html:xpath('//form[@action="verify"]'):text() ~= '' then
            return {
              title=html:xpath('//form[@action="verify"]//div[1]//div[1]'):text(),
              challenge=html:xpath('//form[@action="verify"]//div[1]//div[2]'):text(),
              label='Code'
            }
          end
        end
      end
    end

    -- passcode part 2
    if html:xpath('//form[@action="verify"]'):text() ~= '' then
      print("passcode part 2")
      leaveLoginLoop=false
      if config.debug then print("passcode 2. part") end
      html:xpath('//*[@name="code"]'):attr("value",credentials[1])
      html= connectShop(html:xpath('//form[@action="verify"]'):submit())
    end

    -- 2.FA
    local mfatext=html:xpath('//form[@id="auth-mfa-form"]//p'):text()
    if mfatext ~= "" then
      print("multi factor auth")
      leaveLoginLoop=false
      if config.debug then print("login mfa") end
      if mfa1run then
        -- print("mfa="..mfatext)
        mfa1run=false
        return {
          title='Two-factor authentication',
          challenge=mfatext,
          label='Code'
        }
      else
        html:xpath('//*[@name="otpCode"]'):attr("value",credentials[1])
        -- checkbox
        html:xpath('//*[@name="rememberDevice"]'):attr('checked','checked')
        html= connectShop(html:xpath('//*[@id="auth-mfa-form"]'):submit())
        mfa1run=true
      end
    end

    local xpform='//*[@name="signIn"]'
    if html:xpath(xpform):attr("name") ~= '' then
      leaveLoginLoop=false
      print("enter username/password")
      if config.forceCaptcha then
        print("force captcha with wrong password")
        html:xpath('//*[@name="email"]'):attr("value", secUsername.."a")
        config.forceCaptcha=false
      else
        html:xpath('//*[@name="email"]'):attr("value", secUsername)
      end
      html:xpath('//*[@name="password"]'):attr("value",secPassword)
      html= connectShop(html:xpath(xpform):submit())
    end

    if html:xpath('//a[@id="ap-account-fixup-phone-skip-link"]'):attr('id') ~= '' then
      print("skip phone dialog...")
      enterOrderList()
    end

    loginLoops=loginLoops+1
  until(leaveLoginLoop or loginLoops>10)

  if isLoggedInOrderLanding(html) then
    print('login success')
    aName=html:xpath('//span[@class="nav-shortened-name"]'):text()
    if aName == "" then
      aName=html:xpath('//span[@class="abnav-accountfor"]'):text()
      aName=string.gsub(aName,"Konto für ","")
    end
    if aName == "" then
      aName="Unkown"
      -- print("can't get username, new layout?")
    else
      print("name="..aName)
    end
  else
    print('login failed, clean cookies')
    LocalStorage.cookies=nil
    return LoginFailed
  end

  -- Account search: discover sub-accounts only (no order harvest / no Umsätze).
  -- Harvest runs later in RefreshAccount after the user chose mix and/or sub:*.
  discoverAmazonSubAccounts()
  return nil
end

function ListAccounts (knownAccounts)
  local name=aName
  if name == nil or name == "" then
    name=secUsername
  end
  if name == nil or name == "" then
    name="Orders"
  end
  if LocalStorage.getOrders == nil then
    LocalStorage.getOrders={}
  end
  local accounts={}
  -- Shared Amazon account always offered. Dedicated subs only when discovery
  -- found more than one Amazon identity — user picks mix and/or subs in MM.
  table.insert(accounts, {
    name="Amazon "..name,
    owner=secUsername or name,
    accountNumber="mix",
    type=AccountTypeOther,
  })
  markAccountNeedsInitialReload("mix", knownAccounts)

  local discovered=LocalStorage.discoveredSubAccounts
  if type(discovered) == 'table' and #discovered > 1 then
    for _,sub in ipairs(discovered) do
      table.insert(accounts, {
        name="Amazon "..sub.label,
        owner=secUsername or name,
        accountNumber=sub.accountNumber,
        type=AccountTypeOther,
      })
      markAccountNeedsInitialReload(sub.accountNumber, knownAccounts)
    end
  end
  return accounts
end

function RefreshAccount (account, since)
  local mixed=false
  local periodly=false
  local now=os.time()

  webCacheState='RefreshAccount'

  if type(account.attributes) == 'table' then
    LocalStorage.patcher={}
    for k,v in pairs(account.attributes) do
      print("attribut",k,v)
      LocalStorage.patcher[k]=v
      applyAccountAttribute(k, v, true)
      if k == 'resetCache' and v ~= LocalStorage.resetCache then
        LocalStorage.OrderCache={}
        clearOrderFilterCaches()
        LocalStorage.invalidCache={}
        LocalStorage.resetCache=v
        return {balance=0, transactions={[1]=
          {
            name="Cache reset, please reload!",
            amount = 0,
            bookingDate = now,
            purpose = "... and drink a coffee :)",
            booked = false,
          }
        }}
      end
    end
  end

  blackListOrders={}
  for order in string.gmatch(config.blackListOrders, "[D0-9-]+") do
    print("blacklist order=",order)
    blackListOrders[order]=true
  end

  local divisor=-100
  if account.accountNumber == "inverse" then
    divisor=100
  end

  -- Shared Amazon (mix) and dedicated sub-accounts use the mixed ledger.
  -- Legacy "normal"/"inverse" stay non-mixed for existing MoneyMoney accounts.
  if account.accountNumber == "mix"
      or account.accountNumber == "monthly"
      or account.accountNumber == "yearly"
      or not isCombinedMoneyMoneyAccount(account.accountNumber) then
    mixed=true
  end

  local periodFmt
  local periodContra
  if account.accountNumber == "monthly" then
    mixed=true
    periodly=true
    periodFmt="%Y-%m"
    periodContra=const.monthlyContra
  end
  if account.accountNumber == "yearly" then
    mixed=true
    periodly=true
    periodFmt="%Y"
    periodContra=const.yearlyContra
  end

  print("Refresh",account.accountNumber)

  if LocalStorage.txLayoutNotice then
    MM.printStatus("Amazon: name/purpose=Artikel, Referenz=Bestellnr, Umsatzart=Lieferadresse; bereits geladene Bestellungen werden nicht erneut importiert")
    LocalStorage.txLayoutNotice=false
  end

  if LocalStorage.getOrders[account.accountNumber] == false or LocalStorage.getOrders[account.accountNumber] == nil then
    LocalStorage.getOrders[account.accountNumber]=true

    return {balance=0, transactions={[1]=
      {
        name="Please reload!",
        amount = 0,
        bookingDate = now,
        purpose = "... and drink a coffee :)",
        booked = false,
      }
    }}
  end

  local transactions={}

  if shouldRunAccountHarvest(since, now) then

    LocalStorage.refreshSince=since
    logMoneyMoneyRefreshMode(since, now)

    html=connectShop("GET",baseurl)

    ensureOrderCache()
    ensureOrderFilterCacheRoot()
    if LocalStorage.invalidCache == nil then
      LocalStorage.invalidCache={}
    end

    local _, scanErr=scanAllAmazonSubAccounts()
    if scanErr ~= nil then
      return scanErr
    end

    -- modified orders? read messages
    if LocalStorage.newestMessage == nil then
      LocalStorage.newestMessage = now-(24*60*60)
    end

    local newestMessage=LocalStorage.newestMessage

    for orderCode,messageTime in pairs(getMessageList(LocalStorage.newestMessage)) do

      if newestMessage<messageTime then
        newestMessage=messageTime
      end
      if LocalStorage.OrderCache[orderCode] ~= nil then
        LocalStorage.OrderCache[orderCode].detailsDate=1
      end
    end
    LocalStorage.newestMessage = newestMessage

    if LocalStorage.OrderCache[config.rescanOrder] ~= nil then
      LocalStorage.OrderCache[config.rescanOrder].detailsDate=1
      print("rescan order="..config.rescanOrder)
    end

    -- count order details to get (only for this MoneyMoney account)

    local ordersCounter=0
    local ordersTotal=0

    for orderCode,order in pairs(LocalStorage.OrderCache) do
      if orderNeedsDetailsForAccount(order, now, account.accountNumber) then
        ordersTotal=ordersTotal+1
      end
    end

    if ordersTotal>config.limitOrders then
      ordersTotal=config.limitOrders
      table.insert(transactions,{
        name="There are still more orders left...",
        amount = 0,
        bookingDate = now,
        purpose = "Please reload...",
        booked = false,
      })
    end

    -- get order details from order details page

    for orderCode,order in pairs(LocalStorage.OrderCache) do
      if orderNeedsDetailsForAccount(order, now, account.accountNumber) and ordersCounter<config.limitOrders then
        ordersCounter=ordersCounter+1
        if not blackListOrders[orderCode] then
          MM.printStatus(ordersCounter.."/"..ordersTotal,"Get details for order",orderCode)
          getOrderDetails(order)
        else
          MM.printStatus(ordersCounter.."/"..ordersTotal,"Black listed order",orderCode)
          -- Defer so blacklisted stubs are not re-queued every refresh.
          -- Removing the order from blackListOrders + rescanOrder re-enables fetch.
          order.detailsDate=now+math.floor((math.random()*90+90)*24*60*60)
        end
      end
    end

    LocalStorage.lastLoginCounter = LocalStorage.loginCounter
    LocalStorage.lastHarvestSince=since
  else
    print("skip account scan")
  end

  local balance=0
  local balancesByPeriod={}
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    if not blackListOrders[orderCode] and orderMatchesMoneyMoneyAccount(order, account.accountNumber) then

      -- orderPositions,{purpose=purpose,amount=amount,qty=qty})
      if not mixed then
        balance=balance+order.orderTotal
      end
      if order.since == nil then
        order.since=now
      end

      local report=order.since >= since

      if periodly then
        local period=os.date(periodFmt,order.bookingDate)
        if balancesByPeriod[period] == nil then
          balancesByPeriod[period] = {report=true,balance=order.orderTotal}
        else
          balancesByPeriod[period].balance=balancesByPeriod[period].balance+order.orderTotal
        end
        if not report then
          balancesByPeriod[period].report=false
        end
      end


      if report then
        if type(order.orderPositions) == 'table' then
          for index,position in pairs(order.orderPositions) do
            table.insert(transactions, makeAccountTransaction(
              order,
              orderCode,
              position.purpose,
              position.amount/divisor*position.qty,
              order.bookingDate+1
            ))
          end
        end

        if order.orderSum ~= order.orderTotal then
          table.insert(transactions, makeAccountTransaction(
            order,
            orderCode,
            const.differenceText,
            (order.orderTotal-order.orderSum)/divisor,
            order.bookingDate
          ))
        end

        if mixed and order.orderTotal ~= 0 and not periodly then
          if order.since >= since then
            table.insert(transactions, makeAccountTransaction(
              order,
              orderCode,
              const.contra..orderCode,
              order.orderTotal/divisor*-1,
              order.bookingDate
            ))
          end
        end
      end

      -- makeBranch(order,{'refundTransactions',bookingDate,amount})
      if order.refundTransactions ~= nil then
        for bookingDate,v in pairs(order.refundTransactions) do

          local period=os.date(periodFmt,bookingDate)
          if balancesByPeriod[period] == nil then
            balancesByPeriod[period] = {report=true,balance=0}
          end
          for amount,v in pairs(v) do

            if not mixed then
              balance=balance-amount
            end

            if v.since== nil then
              v.since=now
            end

            if shouldSuppressFullRefundReimport(order, amount, since, mixed) then
              print("skip full-refund reimport (already booked with contra)", orderCode, amount)
              v.since=0
            end

            local report=v.since >= since

            if periodly then
              balancesByPeriod[period].balance=balancesByPeriod[period].balance-amount
              if not report then
                balancesByPeriod[period].report=false
              end
            end

            if report then
              table.insert(transactions, makeAccountTransaction(
                order,
                orderCode,
                const.refundTransaction..orderCode,
                amount/divisor*-1,
                bookingDate
              ))
              if mixed and not periodly then
                table.insert(transactions, makeAccountTransaction(
                  order,
                  orderCode,
                  const.refundTransactionContra..orderCode,
                  amount/divisor,
                  bookingDate
                ))
              end
            end
          end
        end
      end
    end

    -- makeBranch(order,{'returns',bookingDate,amount,purpose})
    if order.returns ~= nil then
      for bookingDate,v in pairs(order.returns) do
        for amount,v in pairs(v) do
          for purpose,v in pairs(v) do
            -- if not mixed then
            --   balance=balance-amount
            -- end
            if v.since== nil then
              v.since=now
            end
            if v.since >= since then
              table.insert(transactions, makeAccountTransaction(
                order,
                orderCode,
                const.returnText..purpose,
                amount/divisor*-1,
                bookingDate
              ))
              table.insert(transactions, makeAccountTransaction(
                order,
                orderCode,
                const.returnTextContra..purpose,
                amount/divisor,
                bookingDate
              ))
            end
          end
        end
      end
    end
  end

  if periodly then
    if LocalStorage.balancesByPeriod == nil then
      LocalStorage.balancesByPeriod={}
    end
    local lastPeriod=""

    for k,v in pairs(balancesByPeriod) do
      if lastPeriod<k then
        lastPeriod=k
      end
      -- debugBuffer.print(k)
    end

    -- debugBuffer.print("lastPeriod=",lastPeriod)

    for k,v in pairs(balancesByPeriod) do
      if v.report then
        if k == lastPeriod then
          LocalStorage.balancesByPeriod[k]={v.balance}
        else
          if LocalStorage.balancesByPeriod[k] == nil then
            LocalStorage.balancesByPeriod[k]={}
          end
          local sum=0
          for _,v in  ipairs(LocalStorage.balancesByPeriod[k]) do
            sum=sum+v
          end
          if sum ~= v.balance then
            table.insert(LocalStorage.balancesByPeriod[k],v.balance-sum)
          end
        end
        for _,v in  ipairs(LocalStorage.balancesByPeriod[k]) do
          table.insert(transactions,{
            name=k,
            amount = v/divisor*-1,
            bookingDate = getLastDayOfPeriod(k),
            purpose = periodContra,
            booked= k~=lastPeriod,
          })
          if k == lastPeriod then
            balance=v
          end
          -- debugBuffer.print(k,v,getLastDayOfPeriod(k))
        end
      end
    end
  end

  --print(balance)
  if config.debug then
    RegressionTest.run(transactions,account.accountNumber)
    if LocalStorage.OrderCache[config.rescanOrder] ~= nil then
      debugBuffer.print(LocalStorage.OrderCache[config.rescanOrder])
    end
  end
  debugBuffer.flush()

  if webCache then
    for _,v in pairs(transactions) do
      v.booked=false
    end
  end

  for _,v in pairs(transactions) do
    if v.accountNumber == nil then
      v.accountNumber=account.owner
    end
  end

  -- Return balance and array of transactions.
  return {balance=balance/divisor, transactions=transactions}
end

function EndSession ()
  -- Logout.
  if config.reallyLogout then
    local logoutElement=html:xpath('//a[contains(@id,"nav-item-signout") or contains(@href,"sign-out")]')
    if logoutElement ~= nil then
      print("Logout")
      if logoutElement:click() ~= nil then
        html= connectShop(logoutElement:click())
      end
    else
      print("error: logout link not found")
    end
  end
end

