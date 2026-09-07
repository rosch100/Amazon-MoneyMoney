-- Amazon Plugin for https://moneymoney-app.com
--
-- Plugin Homepage https://github.com/rosch100/Amazon-MoneyMoney
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
local captcha1run
local mfa1run
local claimsVerify1run
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

-- Keys persisted per Amazon login in LocalStorage.logins[loginKey] (multi-login).
local AMAZON_LOGIN_STATE_KEYS = {
  'OrderCache',
  'getOrders',
  'invalidCache',
  'cookies',
  'orderFilterCache',
  'orderFilterCacheByAccount',
  'offeredOrderFiltersByAccount',
  'orderListHarvestIncompleteByAccount',
  'floatingBalanceAnchorByAccount',
  'discoveredSubAccounts',
  'subAccountScan',
  'pendingInitialSync',
  'initialSyncHarvestDone',
  'initialSyncRefreshedAccounts',
  'accountSetupSession',
  'lastHarvestSince',
  'lastListHarvestAt',
  'refreshSince',
  'lastLoginCounter',
  'loginCounter',
  'requireFullReimport',
  'cacheVersion',
  'abaRollupHarvestIncomplete',
  'abaFullHarvestJobs',
  'abaFullHarvestJobIndex',
  'abaFullHarvestHasMore',
  'abaFullHarvestHarvestSince',
  'abaFullHarvestCompleteKey',
  'abaFullHarvestReplayRequired',
  'abaRollupPaginationVersion',
  'harvestPriorityKind',
  'patcher',
  'resetCache',
}

function normalizeAmazonLoginKey(username)
  if type(username) ~= 'string' then
    return ''
  end
  return (username:gsub('^%s*(.-)%s*$', '%1')):lower()
end

function hasAmazonLoginState(storage)
  if type(storage) ~= 'table' then
    return false
  end
  for _, key in ipairs(AMAZON_LOGIN_STATE_KEYS) do
    if storage[key] ~= nil then
      return true
    end
  end
  return false
end

function captureAmazonLoginState(storage)
  local bucket = {}
  if type(storage) ~= 'table' then
    return bucket
  end
  for _, key in ipairs(AMAZON_LOGIN_STATE_KEYS) do
    bucket[key] = storage[key]
  end
  return bucket
end

function applyAmazonLoginState(storage, bucket)
  if type(storage) ~= 'table' then
    return
  end
  bucket = bucket or {}
  for _, key in ipairs(AMAZON_LOGIN_STATE_KEYS) do
    storage[key] = bucket[key]
  end
end

function suspendAmazonLoginState(storage)
  if type(storage) ~= 'table' then
    return
  end
  local key = storage._activeLoginKey
  if type(key) ~= 'string' or key == '' then
    return
  end
  storage.logins = storage.logins or {}
  storage.logins[key] = captureAmazonLoginState(storage)
end

--- True when EndSession must keep cookies (no remote logout): another login
--- bucket already exists besides the active one (real multi-login).
function shouldPersistAmazonLoginSession(storage)
  if type(storage) ~= 'table' then
    return false
  end
  local active = storage._activeLoginKey
  if type(active) ~= 'string' or active == '' then
    return false
  end
  local logins = storage.logins
  if type(logins) ~= 'table' then
    return false
  end
  for key in pairs(logins) do
    if key ~= active then
      return true
    end
  end
  return false
end

--- Bind flat LocalStorage harvest/cache fields to one login identity.
function activateAmazonLoginStorage(username)
  if type(LocalStorage) ~= 'table' then
    return
  end
  local storage = LocalStorage
  local loginKey = normalizeAmazonLoginKey(username)
  if loginKey == '' then
    return
  end
  if storage._activeLoginKey == loginKey then
    return
  end

  storage.logins = storage.logins or {}
  if storage._activeLoginKey ~= nil then
    suspendAmazonLoginState(storage)
    connection = nil
  elseif hasAmazonLoginState(storage) and storage.logins[loginKey] == nil then
    storage.logins[loginKey] = captureAmazonLoginState(storage)
  end

  applyAmazonLoginState(storage, storage.logins[loginKey] or {})
  storage._activeLoginKey = loginKey
end

local html
local configDirty=false
local webCache=false
local webCacheFolder='webCache'
local webCacheHit=false
local webCacheState='start'
local invalidPrice=1e99
local invalidDate=1e99
local cacheVersion=23
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
  blacklistOrders='',
  keepStorno=false,
  nameMaxLength=0,
}

local daySeconds=24*60*60
local const={
  daySeconds=daySeconds,
  regexOrderCodeNew="([D%d]%d%d%-%d%d%d%d%d%d%d%-%d%d%d%d%d%d%d)",
  regexPriceOld="EUR%s+(%d+),(%d%d)",
  regexPriceNew="€(%d+),(%d%d)",
  -- 2024+ layout writes the currency after the amount, e.g. "169,98€" / "0,00 €"
  regexPriceEur="(%d+),(%d%d)%s*€",
  -- order details page; the order code is appended. The legacy /gp/css/... paths
  -- 301-redirect here. Overridable via the orderDetailsUrl account-setting.
  orderDetailsUrl="/your-orders/order-details?orderID=",
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
  -- Nicht "Amazon": kollidiert mit MoneyMoney’s eingebauter Amazon-Kreditkarte.
  -- Nicht "Amazon Orders": Beutlings signierte Extension. Alt-Zugänge mit diesen
  -- Namen bzw. Kontonummern mix/sub:*/normal/… werden nicht mehr bedient —
  -- Konten müssen unter diesem Service neu angelegt werden.
  services    = {"Amazon Bestellungen"},
  obsoleteAccountRecreateMessage=
    "Amazon: Alte Kontoanlage nicht mehr unterstützt. Bitte alle Amazon-Konten löschen und unter „Amazon Bestellungen“ neu anlegen.",
  description = "Give you an overview about your amazon orders.",
  returnText="Rückgabe: ",
  refundTransaction="Erstattung für Bestellung ",
  floatingBalanceName="Amazon Ausgleich",
  floatingBalancePurpose="Saldoausgleich (wird bei jedem Abruf aktualisiert)",
  floatingBalanceRef="AMAZON-AUSGLEICH",
  incompleteHarvestName="Es sind noch weitere Bestellungen offen…",
  incompleteHarvestPurposePrefix="Bitte erneut abrufen",
  incompleteHarvestRef="AMAZON-INCOMPLETE-HARVEST",
  fullReimportStatus="Amazon: Alle Umsätze dieses Kontos in MoneyMoney löschen, danach resetCache in den Notizen setzen und erneut abrufen.",
  htmlEncoding='UTF-8',
  residualText='Bestelldifferenz',
  partialReturnNetText='Rücksendekosten',
  stornoText='Storno',
  xpathOrderHistoryLink='//a[@id="nav-orders" or contains(@href,"/order-history")]',
  xpathOrderMonthForm="//form[contains(@action,'order')][.//option]",
  xpathOrderMonthSelect='//select[@name="orderFilter" or @name="timeFilter"]',
  -- Classic unified order history (form + GET orderFilter=).
  orderListLink='/gp/your-account/order-history?unifiedOrders=1',
  -- Retail-style list with explicit timeFilter (works for Business session without SPA XHR).
  yourOrdersTimeFilterPath='/your-orders/orders',
  yourOrdersTimeFilterRef='ppx_yo2ov_dt_b_filter_all',
  -- Server-rendered order cards on Amazon Business (nav SPA link is AB shell).
  cssOrderHistoryPath='/gp/css/order-history',
  cssOrderHistoryRef='nav_orders_first',
  businessHomepageAfterSwitch='/gp/css/homepage.html?ref_=nav_youraccount_switchacct',
  businessHomepageYourAccount='/gp/css/homepage.html?ref_=nav_youraccount_btn',
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
  abaFullHarvestJobsPerRefresh=6,
  abaEmptyCustomRangeHorizon=2,
  getFilterUnreadyHorizon=2,
  abaRollupPageSize=16,
  abaRollupMaxPages=250,
  abaRollupPaginationVersion=3,
  abaIncrementalMaxAgeSec=366 * daySeconds,
  -- After full harvest: list scan backstop before cutoff; refund-details watch window.
  incrementalListSafetySec=14 * daySeconds,
  incrementalRefundWatchMaxAgeSec=90 * daySeconds,
  -- Skip order-list harvest (and account switches) when a recent incremental
  -- list scan already covered the cutoff window; details/refund watch still run.
  incrementalListMinRescanSec=4 * 60 * 60,
  abaLandingMarkers={
    'reportType', 'items_report', 'dateSpanSelection',
    'Business Analytics', 'Geschäftsanalyse', 'Beschaffungsanalysen', 'dashboard',
  },
  abaCsvHeaders={
    'Bestellnummer', 'Order ID', 'Bestell-ID', 'Order Number', 'Amazon Order ID',
    'Bestellnummer ', 'Order Id',
  },
  combinedAccountListName="Amazon",
  subAccountListNamePersonal="Persönlich",
  subAccountListNameBusiness="Geschäftlich",
  -- MoneyMoney-Kontonummer = Prefix + customerId ohne führendes „A“.
  -- Nackte customerId und „AB-“+customerId enthalten die ID als Substring und
  -- sind obsolete. Encoding verhindert den Substring-Leak; die Kontoart setzt
  -- dennoch nur der Host (bekannter MoneyMoney-Bug: AccountTypeOther → oft KK).
  moneyMoneyCustomerIdAccountPrefix="AO.",
  daysByMonth={31,28,31,30,31,30,31,31,30,31,30,31},
  -- Obsolete MoneyMoney accountNumbers (pre email/customerId). Refresh rejects these.
  obsoleteMoneyMoneyAccountNumbers={"mix", "normal", "inverse", "monthly", "yearly"},
}

-- SSOT: account note keys (ListAccounts defaults + RefreshAccount).
local accountOptionKeys={
  'resetCache',
  'blacklistOrders',
  'rescanOrder',
  'keepStorno',
  'nameMaxLength',
}

-- Supported in notes but not pre-filled in ListAccounts.
local accountPowerUserKeys={
  'limitOrders',
  'scanFiltersMonths',
  'cookieLanguage',
  'orderDetailsUrl',
}

-- MoneyMoney note key aliases (read → canonical). Not OrderCache legacy.
local accountAttributeAliases={
  blackListOrders='blacklistOrders',
}

function canonicalAccountAttributeKey(key)
  if type(key) ~= 'string' then
    return nil
  end
  local alias=accountAttributeAliases[key]
  if alias ~= nil then
    return alias
  end
  return key
end

function isSupportedAccountAttributeKey(key)
  local canonical=canonicalAccountAttributeKey(key)
  if canonical == nil then
    return false
  end
  if canonical == 'resetCache' then
    return true
  end
  for _,optionKey in ipairs(accountOptionKeys) do
    if optionKey == canonical then
      return true
    end
  end
  for _,optionKey in ipairs(accountPowerUserKeys) do
    if optionKey == canonical then
      return true
    end
  end
  return false
end

function accountAttributeDefaultValue(key)
  local canonical=canonicalAccountAttributeKey(key) or key
  if canonical == 'resetCache' then
    return ''
  end
  if type(config[canonical]) == 'boolean' then
    return config[canonical] and 'true' or 'false'
  end
  if type(config[canonical]) == 'number' then
    return tostring(config[canonical])
  end
  if type(config[canonical]) == 'string' then
    return config[canonical]
  end
  if type(const[canonical]) == 'string' then
    return const[canonical]
  end
  return nil
end

function defaultAccountAttributes()
  local attrs={}
  for _,key in ipairs(accountOptionKeys) do
    local value=accountAttributeDefaultValue(key)
    if value ~= nil then
      attrs[key]=value
    end
  end
  return attrs
end

function mergeAccountAttributes(attrs, knownAttrs)
  if type(knownAttrs) ~= 'table' then
    return attrs
  end
  for k,v in pairs(knownAttrs) do
    if type(k) == 'string' and type(v) == 'string' then
      local canonical=canonicalAccountAttributeKey(k)
      if canonical ~= nil and isSupportedAccountAttributeKey(k) then
        attrs[canonical]=v
      end
    end
  end
  return attrs
end

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
  LocalStorage.offeredOrderFiltersByAccount={}
end

function clearAbaRollupHarvestIncomplete()
  if LocalStorage ~= nil then
    LocalStorage.abaRollupHarvestIncomplete=nil
  end
end

function clearAbaFullHarvestBatch()
  if LocalStorage == nil then
    return
  end
  LocalStorage.abaFullHarvestJobs=nil
  LocalStorage.abaFullHarvestJobIndex=nil
  LocalStorage.abaFullHarvestHasMore=nil
  LocalStorage.abaFullHarvestHarvestSince=nil
  clearAbaRollupHarvestIncomplete()
end

--- @function resetImportState
-- Drops order/import caches. requireFullReimport=true blocks emit until resetCache.
function resetImportState(requireFullReimport)
  if LocalStorage == nil then
    return
  end
  LocalStorage.OrderCache={}
  clearOrderFilterCaches()
  LocalStorage.invalidCache={}
  LocalStorage.lastHarvestSince=nil
  LocalStorage.lastListHarvestAt=nil
  LocalStorage.subAccountScan=nil
  LocalStorage.pendingInitialSync=nil
  LocalStorage.initialSyncHarvestDone=nil
  LocalStorage.initialSyncRefreshedAccounts=nil
  LocalStorage.floatingBalanceAnchorByAccount=nil
  clearAbaFullHarvestBatch()
  if requireFullReimport then
    LocalStorage.requireFullReimport=true
  else
    LocalStorage.requireFullReimport=nil
  end
end

--- @function applyImportSchemaUpgrade
-- Older or missing cacheVersion with any import state → wipe and require full reimport.
function applyImportSchemaUpgrade()
  if LocalStorage == nil then
    return false
  end
  if LocalStorage.cacheVersion == cacheVersion then
    return false
  end
  local from=LocalStorage.cacheVersion
  local hasOrders=type(LocalStorage.OrderCache) == 'table' and next(LocalStorage.OrderCache) ~= nil
  local hasGetOrders=type(LocalStorage.getOrders) == 'table' and next(LocalStorage.getOrders) ~= nil
  local wiped=false
  if from ~= nil or hasOrders or hasGetOrders then
    print("import schema", tostring(from), "->", cacheVersion, "full reimport required")
    resetImportState(true)
    LocalStorage.getOrders=nil
    wiped=true
  end
  LocalStorage.cacheVersion=cacheVersion
  return wiped
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

--- @function emitAccountKey
-- MoneyMoney accountNumber used as key in emittedAccounts maps.
-- Every spelling of the login email collapses onto the same combined key.
-- Sub-accounts: raw customerId and AB-<customerId> share one namespaced key.
function emitAccountKey(accountNumber)
  if accountNumber == nil or accountNumber == ''
      or matchesCombinedAccountEmail(accountNumber) then
    if type(secUsername) ~= 'string' or secUsername == '' then
      error("Amazon: emitAccountKey benötigt den Anmeldenamen (E-Mail)")
    end
    return secUsername
  end
  local customerId=amazonCustomerIdFromMoneyMoneyAccountNumber(accountNumber)
  if customerId == nil and isAmazonCustomerId(accountNumber) then
    customerId=accountNumber
  end
  if customerId ~= nil then
    return moneyMoneyAccountNumberForCustomerId(customerId)
  end
  return tostring(accountNumber)
end

function isOrderEmittedForAccount(owner, accountNumber)
  if type(owner) ~= 'table' or type(owner.emittedAccounts) ~= 'table' then
    return false
  end
  return owner.emittedAccounts[emitAccountKey(accountNumber)] == true
end

function markOrderEmittedForAccount(owner, accountNumber)
  if type(owner) ~= 'table' then
    return
  end
  if type(owner.emittedAccounts) ~= 'table' then
    owner.emittedAccounts={}
  end
  owner.emittedAccounts[emitAccountKey(accountNumber)]=true
end

--- @function clearOrderEmittedFlags
-- Clears emit tracking. keepDetailsParsed=true keeps a successful detailsParsed marker
-- (used when positions appear after an empty prior parse).
function clearOrderEmittedFlags(order, keepDetailsParsed)
  if type(order) ~= 'table' then
    return
  end
  order.emittedAccounts=nil
  if not keepDetailsParsed then
    order.detailsParsed=nil
  end
end

function clearAccountSetupState()
  if LocalStorage == nil then
    return
  end
  LocalStorage.accountSetupSession=nil
end

--- MoneyMoney "Konten einrichten": ListAccounts precedes RefreshAccount in the same login session.
function isAccountSetupSession()
  local session=LocalStorage and LocalStorage.accountSetupSession
  if type(session) ~= 'table' or session.active ~= true then
    return false
  end
  if type(session.loginCounter) == 'number' then
    return type(LocalStorage.loginCounter) == 'number'
      and session.loginCounter == LocalStorage.loginCounter
  end
  -- Setup before loginCounter exists: valid only until the first login assigns a counter.
  return type(LocalStorage.loginCounter) ~= 'number'
end

function beginAccountSetupSession(enableInitialSync)
  if LocalStorage == nil then
    return
  end
  local session={active=true}
  if type(LocalStorage.loginCounter) == 'number' then
    session.loginCounter=LocalStorage.loginCounter
  end
  LocalStorage.accountSetupSession=session
  if enableInitialSync then
    LocalStorage.pendingInitialSync=true
    LocalStorage.initialSyncHarvestDone=nil
    LocalStorage.initialSyncRefreshedAccounts=nil
  end
end

function recordInitialSyncAccountRefresh(accountNumber)
  if not isPendingInitialSync() or type(accountNumber) ~= 'string' or LocalStorage == nil then
    return
  end
  if type(LocalStorage.initialSyncRefreshedAccounts) ~= 'table' then
    LocalStorage.initialSyncRefreshedAccounts={}
  end
  LocalStorage.initialSyncRefreshedAccounts[emitAccountKey(accountNumber)]=accountNumber
end

function initialSyncRefreshedAccountNumbers()
  local refreshed=LocalStorage and LocalStorage.initialSyncRefreshedAccounts
  local accounts={}
  if type(refreshed) ~= 'table' then
    return accounts
  end
  for _,accountNumber in pairs(refreshed) do
    if type(accountNumber) == 'string' then
      accounts[#accounts+1]=accountNumber
    end
  end
  return accounts
end

function hasInitialSyncRefreshedAccounts()
  return #initialSyncRefreshedAccountNumbers() > 0
end

function shouldRecordInitialSyncAccountRefresh(harvest, scanErr, scanComplete)
  if not isPendingInitialSync() then
    return false
  end
  if harvest then
    return scanErr == nil and scanComplete
  end
  return isInitialSyncHarvestDone()
end

--- ListAccounts session: RefreshAccount is account discovery, not import.

--- First import after the user selected accounts: full harvest from the beginning (since=0).
function isPendingInitialSync()
  return LocalStorage ~= nil and LocalStorage.pendingInitialSync == true
end

function isInitialSyncHarvestDone()
  return LocalStorage ~= nil and LocalStorage.initialSyncHarvestDone == true
end

function clearPendingInitialSync()
  if LocalStorage ~= nil then
    LocalStorage.pendingInitialSync=nil
    LocalStorage.initialSyncHarvestDone=nil
    LocalStorage.initialSyncRefreshedAccounts=nil
  end
end

function markInitialSyncHarvestDone()
  if LocalStorage ~= nil then
    LocalStorage.initialSyncHarvestDone=true
  end
end

function ordersNeedingDetailsForInitialSync(now)
  if type(now) ~= 'number' then
    return false
  end
  local pending=ordersNeedingDetailsInCache(now)
  if #pending > 0 then
    return true, pending[1].orderCode
  end
  return false
end

function initialSyncSubAccountsNotYetRefreshed()
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  local refreshed=LocalStorage and LocalStorage.initialSyncRefreshedAccounts
  if type(discovered) ~= 'table' or #discovered <= 1 then
    return {}
  end
  if type(refreshed) ~= 'table' then
    return discovered
  end
  -- The combined MoneyMoney account harvests every discovered sub-account.
  -- It therefore satisfies the initial-sync requirement on its own.
  if refreshed[emitAccountKey(secUsername)] ~= nil then
    return {}
  end
  local missing={}
  for _,sub in ipairs(discovered) do
    if type(sub) == 'table' and type(sub.accountNumber) == 'string' then
      local key=emitAccountKey(sub.accountNumber)
      if refreshed[key] == nil then
        missing[#missing+1]=sub.accountNumber
      end
    end
  end
  return missing
end

function isSubAccountScanComplete()
  local state=LocalStorage and LocalStorage.subAccountScan
  if state == nil then
    return false
  end
  if state.phase ~= 'done' then
    return false
  end
  return state.incomplete ~= true
end

function tryCompleteInitialSync(now)
  if not isPendingInitialSync() or not isInitialSyncHarvestDone() then
    return
  end
  if isAccountSetupSession() then
    return
  end
  if not hasInitialSyncRefreshedAccounts() then
    return
  end
  local detailsPending, detailsLabel=ordersNeedingDetailsForInitialSync(now)
  if detailsPending then
    if type(detailsLabel) == 'string' then
      MM.printStatus("Amazon: Erstimport – Bestelldetails noch offen (z. B. "..detailsLabel..")")
    end
    return
  end
  local notRefreshed=initialSyncSubAccountsNotYetRefreshed()
  if #notRefreshed > 0 then
    print("Erstimport: Unterkonten noch nicht abgerufen:", table.concat(notRefreshed, ", "))
    MM.printStatus("Amazon: Erstimport – weitere Unterkonten beim ersten Abruf aktualisieren")
    return
  end
  clearPendingInitialSync()
end

function effectiveRefreshSince(since)
  if isPendingInitialSync() and not isAccountSetupSession() then
    return 0
  end
  if type(since) == 'number' then
    return since
  end
  return 0
end

function emptyRefreshResult()
  return {balance=0, transactions={}}
end

--- Finder RefreshAccount: empty success, no harvest, no emit.
--- MoneyMoney treats a returned error string as a bank failure.
--- Erstimport runs on the first RefreshAccount after EndSession (Kontenrundruf).
function accountDiscoveryRefreshResult()
  print("Konten einrichten: keine Umsätze laden")
  return emptyRefreshResult()
end

--- Early RefreshAccount exits: full reimport gate and finder (no emit).
function refreshAccountBlockedResult()
  if LocalStorage ~= nil and LocalStorage.requireFullReimport then
    MM.printStatus(const.fullReimportStatus)
    return emptyRefreshResult()
  end
  if isAccountSetupSession() then
    return accountDiscoveryRefreshResult()
  end
  return nil
end

--- @function orderDetailsCompleteForEmit
-- Details loaded and not queued for another fetch.
function orderDetailsCompleteForEmit(order, now, accountNumber)
  if type(order) ~= 'table' or type(now) ~= 'number' then
    return false
  end
  if type(order.detailsDate) ~= 'number' or order.detailsDate <= 1 then
    return false
  end
  if order.detailsParsed ~= true then
    return false
  end
  if type(order.bookingDate) ~= 'number' or order.bookingDate == invalidDate then
    return false
  end
  return not orderNeedsDetailsForAccount(order, now, accountNumber)
end

--- @function registerRefundTransaction
-- Stores refundTransactions[bookingDate][amount].
function registerRefundTransaction(order, bookingDate, amount)
  if type(order) ~= 'table' or type(bookingDate) ~= 'number' or type(amount) ~= 'number' then
    return
  end
  makeBranch(order, {'refundTransactions', bookingDate, amount})
end

function forEachRefundLeaf(order, fn)
  if type(order) ~= 'table' or type(fn) ~= 'function' or type(order.refundTransactions) ~= 'table' then
    return
  end
  for bookingDate,byAmount in pairs(order.refundTransactions) do
    if type(byAmount) == 'table' then
      for amount,leaf in pairs(byAmount) do
        if type(leaf) == 'table' then
          fn(leaf, bookingDate, amount)
        end
      end
    end
  end
end

function forEachReturnLeaf(order, fn)
  if type(order) ~= 'table' or type(fn) ~= 'function' or type(order.returns) ~= 'table' then
    return
  end
  for bookingDate,byAmount in pairs(order.returns) do
    if type(byAmount) == 'table' then
      for amount,byPurpose in pairs(byAmount) do
        if type(byPurpose) == 'table' then
          for purpose,leaf in pairs(byPurpose) do
            if type(leaf) == 'table' then
              fn(leaf, bookingDate, amount, purpose)
            end
          end
        end
      end
    end
  end
end

--- Refund and return leaves share the same emit/migrate shape; purpose is nil for refunds.
function forEachAdjustmentLeaf(order, fn)
  if type(order) ~= 'table' or type(fn) ~= 'function' then
    return
  end
  forEachRefundLeaf(order, fn)
  forEachReturnLeaf(order, fn)
end

if LocalStorage ~=nil then
  if applyImportSchemaUpgrade() then
    configDirty=true
  end

  if config.cleanOrdersCache then
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
  local configFile, configError=io.open(configFileName,"wb")
  if configFile == nil then
    error("cannot write config file: "..tostring(configError))
  end
  configFile:write(JSON():set(config):json())
  configFile:close()
end

-- print(((io == nil or io.open == nil) and 'signed ' or '')  .. const.services[1],"plugin loaded...")
-- if config.debug then print('debugging...') end
-- if debug ~= nil then
--   print("lua debug is usable")
-- end
local baseurl='https://www'..const.domain

-- NOTE: version must be a Lua number (no letters). To mark this as an
-- unofficial build the "(beta)" tag is added to the description instead.
WebBanking{version  = 2.00,
  url         = baseurl,
  services    = const.services,
  description = const.description.." (beta v2.00)"}

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

function parseAmazonHtml(content)
  return HTML(content, const.htmlEncoding)
end

function connectShop(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  return parseAmazonHtml(connectShopRaw(method, url, postContent, postContentType, headers))
end

function connectShopRaw(method, url, postContent, postContentType, headers)
  -- All string request URLs must stay on www.amazon.de (MoneyMoney whitelist).
  if type(url) == 'string' and url ~= '' then
    url = absoluteAmazonUrl(url)
  end
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
    if config.debug and type(postContent) == 'string' then
      for i in string.gmatch(postContent, "([^&]+)") do
        local name=i:match("^([^=]+)") or ""
        if name:lower():find("pass", 1, true) or name:lower():find("pwd", 1, true)
            or name:lower():find("otp", 1, true) or name:lower():find("secret", 1, true) then
          print("post='"..name.."=<redacted>'")
        else
          print("post='"..i.."'")
        end
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
      local metadataPath=webCacheFolder..'/'..webCacheLastId..'.json'
      local webFile, metadataError=io.open(metadataPath,"wb")
      if webFile == nil then
        error("cannot write web cache metadata: "..tostring(metadataError))
      end
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
      local contentPath=webCacheFolder..'/'..webCacheLastId..'.html'
      local contentError
      webFile, contentError=io.open(contentPath,"wb")
      if webFile == nil then
        error("cannot write web cache content: "..tostring(contentError))
      end
      webFile:write(content)
      webFile:close()
      print("webCache id="..webCacheLastId.." written.")
    end
  end

  if content ~= nil
      and not cached
      and baseurl == connection:getBaseURL():lower():sub(1,#baseurl) then
    -- work around for deleted cookies, prevent captcha
    connection:setCookie('a-ogbcbff=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    connection:setCookie('ap-fid=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/ap/; Secure')
    -- issue #28
    connection:setCookie('lc-acbde=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')

    if config.debug then
      if LocalStorage.cookies~=connection:getCookies() then
        print("store cookies=<redacted>")
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
      key=key..k.."="..tostring(transaction[k]).." "
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
      transFile:close()

      for _,v in pairs(transactions) do
        v.amount=tostring(v.amount)
      end
      local outputPath=regTestPre.."_transactions.json"
      local outputError
      transFile, outputError=io.open(outputPath,"wb")
      if transFile == nil then
        error("cannot write regression transactions: "..tostring(outputError))
      end
      transFile:write(JSON():set(transactions):json())
      transFile:close()

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
  local html=parseAmazonHtml(connectShopRaw(method, url, postContent, postContentType, headers))
  local xpform='//form[@name="signIn"]'
  if html:xpath(xpform):attr("name") ~= '' then
    removeWebCacheLastItem()
    print("Forced log out detect, enter username/password")
    html:xpath('//*[@name="email"]'):attr("value", secUsername)
    html:xpath('//*[@name="password"]'):attr("value",secPassword)
    html= connectShopForm(html:xpath(xpform))
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

function getOrderCode(text)
  if type(text)~='string' then
    return nil
  end
  local orderCode=string.match(text,const.regexOrderCodeNew)
  return orderCode
end

---@class orderPosition
---@field purpose string
---@field amount number
---@field qty number

---@class order
---@field orderCode string
---@field totalSum number?
---@field orderTotal number
---@field bookingDate number
---@field detailsUrl string?
---@field orderPositions orderPosition[]
---@field invalidArticles boolean?
---@field detailsDate number
---@field accountNumber string?
---@field shippingAddress string?
---@field mandateReference string?
---@field unbilledCancel boolean?
---@field summaryExtras table[]?

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
  if c >= 0xC2 and c <= 0xDF then
    len=2
  elseif c >= 0xE0 and c <= 0xEF then
    len=3
  elseif c >= 0xF0 and c <= 0xF4 then
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
  local second=text:byte(i+1)
  if (c == 0xE0 and second < 0xA0)
      or (c == 0xED and second >= 0xA0)
      or (c == 0xF0 and second < 0x90)
      or (c == 0xF4 and second >= 0x90) then
    return nil
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

function isValidUtf8(text)
  if type(text) ~= 'string' then
    return false
  end
  local i=1
  while i <= #text do
    local charLen=utf8CharLen(text, i)
    if charLen == nil then
      return false
    end
    i=i+charLen
  end
  return true
end

--- @function makeAccountTransaction
-- Maps plugin fields onto MoneyMoney transaction fields:
-- name = Artikelbezeichnung (optional config.nameMaxLength UTF-8 chars),
-- purpose = full Artikelbezeichnung,
-- endToEndReference = Bestellnummer (MoneyMoney UI "Referenz"),
-- bookingText = Lieferadresse (MoneyMoney UI "Umsatzart", visible in list line),
-- batchReference = Lieferadresse (Sammlerreferenz),
-- mandateReference = Zahlungsart,
-- accountNumber = Amazon-Unterkonto.
function encodeFormText(text)
  if not isValidUtf8(text) then
    error('MoneyMoney transaction text must be a UTF-8 string')
  end
  return text
end

function sortTransactionsNewestFirst(transactions)
  local indexed={}
  for index,transaction in ipairs(transactions) do
    if type(transaction.bookingDate) ~= 'number' then
      error('MoneyMoney transaction bookingDate must be a number')
    end
    table.insert(indexed, {
      index=index,
      transaction=transaction,
    })
  end
  table.sort(indexed, function(left, right)
    local leftDate=left.transaction.bookingDate
    local rightDate=right.transaction.bookingDate
    if leftDate == rightDate then
      return left.index < right.index
    end
    return leftDate > rightDate
  end)
  for index,entry in ipairs(indexed) do
    transactions[index]=entry.transaction
  end
end

--- @function orderRealAmount
-- Sum of real mix bookings for one order, in account currency.
function orderRealAmount(order, divisor)
  if type(order) ~= 'table' or type(divisor) ~= 'number' or divisor == 0 then
    return 0
  end
  if order.unbilledCancel then
    return 0
  end
  local sum=0
  if type(order.orderPositions) == 'table' then
    for _,position in pairs(order.orderPositions) do
      local amount=tonumber(position.amount)
      local qty=tonumber(position.qty)
      if amount ~= nil and qty ~= nil then
        sum=sum+amount/divisor*qty
      end
    end
  end
  local extras=resolvedSummaryExtras(order)
  for _,extra in ipairs(extras) do
    local extraAmount=tonumber(extra.amount)
    if extraAmount ~= nil then
      sum=sum+extraAmount/divisor
    end
  end
  local compact=compactPartialReturnCents(order)
  if compact ~= nil then
    sum=sum+compact.netExpenseCents/divisor
    if compact.excessRefundCents > 0 then
      sum=sum-compact.excessRefundCents/divisor
    end
    return sum
  end
  local function addCredit(_, _, amountCents)
    local amount=tonumber(amountCents)
    if amount ~= nil then
      sum=sum+amount/divisor*-1
    end
  end
  forEachAdjustmentLeaf(order, addCredit)
  return sum
end

function earliestOrderBookingDateForAccount(accountNumber)
  if LocalStorage == nil or type(LocalStorage.OrderCache) ~= 'table' then
    return nil
  end
  local earliest=nil
  for _,order in pairs(LocalStorage.OrderCache) do
    if type(order) == 'table' and orderMatchesMoneyMoneyAccount(order, accountNumber) then
      local booking=order.bookingDate
      if type(booking) == 'number' and (earliest == nil or booking < earliest) then
        earliest=booking
      end
    end
  end
  return earliest
end

function ensureFloatingAnchorRoot()
  if LocalStorage.floatingBalanceAnchorByAccount == nil then
    LocalStorage.floatingBalanceAnchorByAccount={}
  end
end

function storedMixFloatingAnchorDate(accountNumber)
  if type(accountNumber) ~= 'string' or LocalStorage == nil then
    return nil
  end
  ensureFloatingAnchorRoot()
  local stored=LocalStorage.floatingBalanceAnchorByAccount[emitAccountKey(accountNumber)]
  if type(stored) == 'number' then
    return stored
  end
  return nil
end

function persistMixFloatingAnchorDate(accountNumber, anchor)
  if type(accountNumber) ~= 'string' or type(anchor) ~= 'number' or LocalStorage == nil then
    return anchor
  end
  ensureFloatingAnchorRoot()
  LocalStorage.floatingBalanceAnchorByAccount[emitAccountKey(accountNumber)]=anchor
  return anchor
end

--- @function mixFloatingBookingDate
-- Anchor before the first booking (opening balance in the past). Persisted per account for stable pending identity.
function mixFloatingBookingDate(since, now, accountNumber)
  if type(now) ~= 'number' then
    now=os.time()
  end
  local stored=storedMixFloatingAnchorDate(accountNumber)
  if type(stored) == 'number' then
    return stored
  end
  local anchor=nil
  local earliest=earliestOrderBookingDateForAccount(accountNumber)
  if type(earliest) == 'number' then
    anchor=earliest - const.daySeconds
  else
    anchor=getLastDayOfPeriod(os.date("%Y-%m", now))
  end
  if type(since) == 'number' and since > 0 and anchor < since then
    anchor=since
  end
  if type(accountNumber) == 'string' and not isPendingInitialSync() then
    return persistMixFloatingAnchorDate(accountNumber, anchor)
  end
  return anchor
end

--- @function makeFloatingBalanceTransaction
-- One pending offset so mix bookings sum to zero and stay out of net worth.
function makeFloatingBalanceTransaction(amount, since, now, accountNumber)
  return {
    name=encodeFormText(const.floatingBalanceName),
    purpose=encodeFormText(const.floatingBalancePurpose),
    amount=amount,
    bookingDate=mixFloatingBookingDate(since, now, accountNumber),
    endToEndReference=const.floatingBalanceRef,
    booked=false,
  }
end

function isCombinedInitialSyncDetailsFetch(accountNumber)
  return isCombinedMoneyMoneyAccount(accountNumber)
    and isPendingInitialSync()
    and not isAccountSetupSession()
end

function pendingDetailsCountForRefresh(accountNumber, now)
  if isCombinedInitialSyncDetailsFetch(accountNumber) then
    return #ordersNeedingDetailsInCache(now)
  end
  return #ordersNeedingDetailsForAccount(accountNumber, now)
end

function hasActiveIncompleteSubAccountScan()
  local state=LocalStorage and LocalStorage.subAccountScan
  if type(state) ~= 'table' then
    return false
  end
  if state.incomplete == true then
    return true
  end
  return state.phase == 'running' or state.phase == 'await_mfa'
end

function detailsFetchWasTruncated(fetchState)
  return type(fetchState) == 'table'
    and type(fetchState.pendingAtStart) == 'number'
    and type(fetchState.counter) == 'number'
    and fetchState.pendingAtStart > fetchState.counter
end

function detailsFetchFailed(fetchState)
  return type(fetchState) == 'table'
    and type(fetchState.failed) == 'number'
    and fetchState.failed > 0
end

function incompleteRefreshNoticePurpose(accountNumber, now, harvest, fetchState)
  local parts={}
  local function note(condition, text)
    if condition then
      parts[#parts+1]=text
    end
  end
  if hasActiveIncompleteSubAccountScan() then
    note(true, "Abruf der Unterkonten unvollständig")
  elseif isPendingInitialSync() and not isAccountSetupSession()
      and not isInitialSyncHarvestDone()
      and not isSubAccountScanComplete() then
    note(true, "Erstimport: Bestellhistorie noch nicht vollständig abgerufen")
  end
  if harvest then
    note(abaFullHarvestBatchHasMore(), "Business-Berichte noch nicht vollständig")
    note(isAbaRollupHarvestIncomplete(), "Business-Bericht Pagination unvollständig")
  end
  local pendingDetails=pendingDetailsCountForRefresh(accountNumber, now)
  note(pendingDetails > 0
      and (detailsFetchWasTruncated(fetchState) or detailsFetchFailed(fetchState)),
    tostring(pendingDetails).." Bestelldetails offen")
  if #parts == 0 then
    return nil
  end
  return const.incompleteHarvestPurposePrefix
    .." – "..table.concat(parts, "; ")..". Bitte Konto erneut aktualisieren."
end

--- Dummy booking when harvest or details are incomplete (upstream Amazon-MoneyMoney pattern).
function makeIncompleteHarvestDummy(now, purpose)
  return {
    name=const.incompleteHarvestName,
    amount=0,
    bookingDate=now,
    purpose=purpose,
    endToEndReference=const.incompleteHarvestRef,
    booked=false,
  }
end

function appendIncompleteHarvestDummy(transactions, accountNumber, now, harvest, fetchState)
  if isAccountSetupSession() then
    return false
  end
  local purpose=incompleteRefreshNoticePurpose(accountNumber, now, harvest, fetchState)
  if purpose == nil then
    return false
  end
  table.insert(transactions, makeIncompleteHarvestDummy(now, purpose))
  return true
end

--- @function addMixFloatingBalance
-- Pending Ausgleich for the full emitted mix ledger (clean reimport, no legacy offset).
function addMixFloatingBalance(transactions, accountNumber, since, now, divisor)
  if type(transactions) ~= 'table' or type(divisor) ~= 'number' or divisor == 0 then
    return
  end
  if LocalStorage == nil or type(LocalStorage.OrderCache) ~= 'table' then
    return
  end
  local ledger=0
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    if type(orderBlacklist) == 'table' and orderBlacklist[orderCode] then
      -- skip
    elseif orderMatchesMoneyMoneyAccount(order, accountNumber)
        and isOrderEmittedForAccount(order, accountNumber) then
      ledger=ledger+orderRealAmount(order, divisor)
    end
  end
  if ledger ~= 0 then
    table.insert(transactions, makeFloatingBalanceTransaction(-ledger, since, now, accountNumber))
  end
end

function positionsCents(positions)
  if type(positions) ~= 'table' then
    return 0
  end
  local sum=0
  for _,position in ipairs(positions) do
    local amount=tonumber(position.amount)
    local qty=tonumber(position.qty)
    if amount ~= nil and qty ~= nil then
      sum=sum+amount*qty
    end
  end
  return sum
end

function returnedPositionsCents(order)
  if type(order) ~= 'table' then
    return 0
  end
  return positionsCents(order.returnedPositions)
end

function purchasePositionsCents(order)
  if type(order) ~= 'table' then
    return 0
  end
  return positionsCents(order.orderPositions)
end

--- Return/refund activity on the order (details page or returned items).
function orderHasReturnActivity(order)
  if type(order) ~= 'table' then
    return false
  end
  if order.returnActivity == true then
    return true
  end
  if returnedPositionsCents(order) > 0 then
    return true
  end
  if type(order.returns) == 'table' and next(order.returns) ~= nil then
    return true
  end
  return false
end

function orderDetailsHasReturnActivity(orderDetails)
  if orderDetails == nil then
    return false
  end
  if orderDetails:xpath('.//a[contains(@href,"return")]'):length() > 0 then
    return true
  end
  if orderDetails:xpath('.//*[contains(.,"Rücksendung") or contains(.,"Erstattung")]'):length() > 0 then
    return true
  end
  if orderDetails:xpath(
    './/div[contains(@class,"od-line-item-row")][.//*[contains(@class,"od-line-item-row-label")][contains(.,"Erstattung")]]'
  ):length() > 0 then
    return true
  end
  return false
end

--- Explicit full-return layout without returnedPositions: total zero implies full gross return.
function orderImpliesFullReturnGross(order)
  if type(order) ~= 'table' or order.returnActivity ~= true then
    return false
  end
  if returnedPositionsCents(order) > 0 then
    return false
  end
  local purchased=purchasePositionsCents(order)
  if purchased <= 0 then
    return false
  end
  local total=tonumber(order.orderTotal)
  -- The credit is inferred after this check from retained return costs.
  return total == 0
end

--- Gross value of returned goods (returnedPositions, else purchase lines on full-return layout only).
function effectiveReturnedCents(order)
  local returned=returnedPositionsCents(order)
  if returned > 0 then
    return returned
  end
  if orderImpliesFullReturnGross(order) then
    return purchasePositionsCents(order)
  end
  return 0
end

--- Kept purchase lines after a return (empty when all items were returned).
function orderHasKeptPurchaseItems(order)
  if not orderHasPositions(order) then
    return false
  end
  if not orderHasReturnActivity(order) then
    return true
  end
  local returned=effectiveReturnedCents(order)
  local purchased=purchasePositionsCents(order)
  if returned > 0 and purchased > 0 and returned >= purchased then
    return false
  end
  return true
end

--- Partial return without keepStorno: net expense (returned item gross minus refund).
-- @return table|nil { netExpenseCents, excessRefundCents } or nil when not applicable
function compactPartialReturnCents(order)
  if config.keepStorno then
    return nil
  end
  local returned=effectiveReturnedCents(order)
  local refund=adjustmentCreditCents(order)
  if returned <= 0 or refund <= 0 then
    return nil
  end
  local net=returned-refund
  return {
    netExpenseCents=net > 0 and net or 0,
    excessRefundCents=net < 0 and -net or 0,
  }
end

function adjustmentTransactionName(purpose, orderCode)
  if purpose then
    return const.returnText..purpose
  end
  return const.refundTransaction..orderCode
end

function markPartialReturnAdjustmentsOmitted(order, accountNumber)
  forEachAdjustmentLeaf(order, function(leaf)
    markOrderEmittedForAccount(leaf, accountNumber)
  end)
end

function emitPartialReturnExcessRefunds(ctx, order, orderCode, report, excessRefundCents)
  local remaining=tonumber(excessRefundCents)
  if remaining == nil or remaining <= 0 then
    return
  end
  forEachAdjustmentLeaf(order, function(leaf, bookingDate, amount, purpose)
    if remaining <= 0 then
      return
    end
    local credit=tonumber(amount)
    if credit == nil or credit <= 0 then
      return
    end
    if isOrderEmittedForAccount(leaf, ctx.accountNumber) then
      return
    end
    local emitAmount=math.min(credit, remaining)
    if emitAmount <= 0 then
      return
    end
    local name=adjustmentTransactionName(purpose, orderCode)
    emitAdjustmentLeaf(ctx, order, orderCode, leaf, bookingDate, emitAmount, name)
    remaining=remaining-emitAmount
  end)
end

function emitPartialReturnNetLine(ctx, order, orderCode, netExpenseCents, report)
  local net=tonumber(netExpenseCents)
  if not report or net == nil or net <= 0 then
    return
  end
  local bookingDate=order.bookingDate
  if bookingDate == nil or bookingDate == invalidDate then
    error("Amazon: Bestelldatum für Teilrückgabe fehlt oder ist ungültig.")
  end
  table.insert(ctx.transactions, makeAccountTransaction(
    order,
    orderCode,
    const.partialReturnNetText,
    net/ctx.divisor,
    bookingDate
  ))
end

function emitOrderAdjustments(ctx, order, orderCode, report)
  local compact=compactPartialReturnCents(order)
  if compact ~= nil then
    emitPartialReturnNetLine(ctx, order, orderCode, compact.netExpenseCents, report)
    if compact.excessRefundCents > 0 then
      emitPartialReturnExcessRefunds(ctx, order, orderCode, report, compact.excessRefundCents)
    end
    markPartialReturnAdjustmentsOmitted(order, ctx.accountNumber)
    return
  end
  forEachAdjustmentLeaf(order, function(leaf, bookingDate, amount, purpose)
    emitAdjustmentLeaf(
      ctx, order, orderCode, leaf, bookingDate, amount, adjustmentTransactionName(purpose, orderCode))
  end)
end

--- @function adjustmentCreditCents
-- Refund and return amounts in cents.
function adjustmentCreditCents(order)
  local sum=0
  forEachAdjustmentLeaf(order, function(_, _, amount)
    local n=tonumber(amount)
    if n ~= nil then
      sum=sum+n
    end
  end)
  return sum
end

--- @function billedOrderCents
-- Charged order total in cents (header total, else item sum).
function billedOrderCents(order)
  if type(order) ~= 'table' then
    return 0
  end
  local total=tonumber(order.orderTotal)
  if total ~= nil and total > 0 then
    return total
  end
  local sum=tonumber(order.orderSum)
  if sum ~= nil and sum > 0 then
    return sum
  end
  return 0
end

--- @function orderIsFullyReversed
-- Unbilled cancel or credits covering the billed total.
function orderIsFullyReversed(order)
  if type(order) ~= 'table' then
    return false
  end
  if order.unbilledCancel then
    return true
  end
  local billed=billedOrderCents(order)
  if billed <= 0 then
    return false
  end
  return adjustmentCreditCents(order) >= billed
end

--- @function shouldOmitReversedPair
-- Default: drop booking+storno together. keepStorno or already-emitted purchase keeps them.
function shouldOmitReversedPair(order, accountNumber)
  if config.keepStorno then
    return false
  end
  if not orderIsFullyReversed(order) then
    return false
  end
  return not isOrderEmittedForAccount(order, accountNumber)
end

function markReversedPairOmitted(order, accountNumber)
  markOrderEmittedForAccount(order, accountNumber)
  forEachAdjustmentLeaf(order, function(leaf)
    markOrderEmittedForAccount(leaf, accountNumber)
  end)
end

function emitAdjustmentLeaf(ctx, order, orderCode, leaf, bookingDate, amountCents, name)
  local amount=tonumber(amountCents)
  if type(leaf) ~= 'table' or amount == nil then
    return
  end
  local report=not isOrderEmittedForAccount(leaf, ctx.accountNumber)
  if not report then
    return
  end
  table.insert(ctx.transactions, makeAccountTransaction(
    order, orderCode, name, amount/ctx.divisor*-1, bookingDate))
  markOrderEmittedForAccount(leaf, ctx.accountNumber)
end

function emitPurchaseLines(ctx, order, orderCode)
  if order.unbilledCancel and not config.keepStorno then
    markOrderEmittedForAccount(order, ctx.accountNumber)
    return
  end
  local compact=compactPartialReturnCents(order)
  if compact ~= nil and not config.keepStorno and not orderHasKeptPurchaseItems(order) then
    markOrderEmittedForAccount(order, ctx.accountNumber)
    return
  end
  local didEmit=false
  local function emitPositions(positions)
    if type(positions) ~= 'table' then
      return
    end
    for _,position in pairs(positions) do
      local qty=tonumber(position.qty)
      local amount=tonumber(position.amount)
      if amount ~= nil and qty ~= nil then
        table.insert(ctx.transactions, makeAccountTransaction(
          order,
          orderCode,
          position.purpose,
          amount/ctx.divisor*qty,
          order.bookingDate+1
        ))
        didEmit=true
      end
    end
  end
  if config.keepStorno or orderHasKeptPurchaseItems(order) then
    emitPositions(order.orderPositions)
  end
  if config.keepStorno then
    emitPositions(order.returnedPositions)
  end
  if compact == nil then
    local extras, leftover=resolvedSummaryExtras(order)
    for _,extra in ipairs(extras) do
      if extra.amount ~= 0 then
        table.insert(ctx.transactions, makeAccountTransaction(
          order,
          orderCode,
          extra.name,
          extra.amount/ctx.divisor,
          order.bookingDate
        ))
        didEmit=true
      end
    end
    -- keepStorno on unbilled cancel: leftover offsets the item lines (not Bestelldifferenz).
    if leftover ~= 0 and order.unbilledCancel and config.keepStorno then
      table.insert(ctx.transactions, makeAccountTransaction(
        order,
        orderCode,
        const.stornoText,
        leftover/ctx.divisor,
        order.bookingDate
      ))
      didEmit=true
    end
  end
  if didEmit then
    markOrderEmittedForAccount(order, ctx.accountNumber)
  end
end

function appendOrderToRefresh(ctx, order, orderCode)
  if shouldOmitReversedPair(order, ctx.accountNumber) then
    markReversedPairOmitted(order, ctx.accountNumber)
    return
  end
  local report=not isOrderEmittedForAccount(order, ctx.accountNumber)
    and orderDetailsCompleteForEmit(order, ctx.now, ctx.accountNumber)
  if report then
    emitPurchaseLines(ctx, order, orderCode)
  end
  emitOrderAdjustments(ctx, order, orderCode, report)
end

function makeAccountTransaction(order, orderCode, name, amount, bookingDate, purpose)
  local fullName=name or ""
  local shortName=truncateUtf8(fullName, config.nameMaxLength)
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

--- @function normalizeSummaryLabel
-- Amazon Bestellübersicht label without trailing colon/space.
function normalizeSummaryLabel(label)
  return trim((trim(label)):gsub(':+$',''))
end

--- @function summaryLabelKind
-- skip = totals/VAT/refund; credit = coupon/promo; debit = shipping/gift.
function summaryLabelKind(name)
  if name == '' then
    return 'skip'
  end
  if name:find('Erstattung') then
    return 'skip'
  end
  if name:find('Gesamtsumme') or name:find('Grand Total') then
    return 'skip'
  end
  if name == 'Summe' or name:find('Summe ohne') or name:find('Gesamt vor') then
    return 'skip'
  end
  if name:find('Zwischensumme') or name:find('Subtotal') then
    return 'skip'
  end
  if name:find('MwSt') or name:find('USt') or name:find('VAT') or name:find('Mehrwertsteuer') then
    return 'skip'
  end
  if name:find('Werbeaktion') or name:find('Gutschein') or name:find('Rabatt')
      or name:find('Promotion') or name:find('[Cc]oupon') or name:find('[Dd]iscount') then
    return 'credit'
  end
  if name:find('Versand') or name:find('Verpackung') or name:find('Geschenk')
      or name:find('[Ss]hipping') or name:find('[Gg]ift wrap') then
    return 'debit'
  end
  return 'other'
end

--- @function signedSummaryAmount
-- Expense-positive cents (same sign as orderTotal-orderSum pieces).
function signedSummaryAmount(priceText, kind)
  local cents=getPrice(priceText)
  if cents == invalidPrice then
    return invalidPrice
  end
  cents=math.abs(cents)
  local negative=(priceText:find('%-') ~= nil) or (priceText:find('−') ~= nil)
  if kind == 'credit' or negative then
    return -cents
  end
  return cents
end

--- @function isUnbilledCancellation
-- Amazon: Storniert and explicitly not billed.
function isUnbilledCancellation(orderDetails)
  local status=trim(orderDetails:xpath('.//*[@data-component="shipmentStatus"]'):text())
  if status == '' then
    status=trim(orderDetails:xpath('.//*[contains(@class,"od-status-message")]'):text())
  end
  if status:find('Storniert') == nil and status:find('Cancelled') == nil then
    return false
  end
  return status:find('nicht in Rechnung') ~= nil
    or status:find('not billed') ~= nil
    or status:find('was not charged') ~= nil
end

--- True when a data-component node exists under the order-details root.
function orderDetailsHasDataComponent(orderDetails, componentName)
  if orderDetails == nil or type(componentName) ~= 'string' or componentName == '' then
    return false
  end
  return orderDetails:xpath('.//*[@data-component="'..componentName..'"]'):length() > 0
end

--- True when trimmed order-details text contains any of the needles (plain find).
function orderDetailsTextContainsAny(orderDetails, needles)
  if orderDetails == nil or type(needles) ~= 'table' then
    return false
  end
  local text=trim(orderDetails:text())
  if text == '' then
    return false
  end
  for _, needle in ipairs(needles) do
    if type(needle) == 'string' and needle ~= ''
        and text:find(needle, 1, true) ~= nil then
      return true
    end
  end
  return false
end

--- Component match, else any plain-text needle under order-details.
function orderDetailsMatchesMarker(orderDetails, componentName, textNeedles)
  if orderDetailsHasDataComponent(orderDetails, componentName) then
    return true
  end
  return orderDetailsTextContainsAny(orderDetails, textNeedles)
end

--- Cancelled order-details stub: SSR banner only, no orderDate/positions (2026+).
function isCancelledOrderDetailsStub(orderDetails)
  return orderDetailsMatchesMarker(orderDetails, 'cancelledOrderBanner', {
    'Diese Bestellung wurde storniert',
    'This order was cancelled',
  })
end

--- Amazon error shell: details cannot be loaded (wrong account / digital / transient).
function isUnloadableOrderDetailsPage(orderDetails)
  return orderDetailsMatchesMarker(orderDetails, 'errorbanner', {
    'Bestelldetails nicht laden',
    'cannot load your order details',
    "can't load your order details",
  })
end

--- True when cancelled stub text says the cancel was not billed.
function cancelledStubLooksUnbilled(orderDetails)
  return orderDetailsTextContainsAny(orderDetails, {
    'nicht in Rechnung',
    'not billed',
    'was not charged',
  })
end

--- Complete cancelled SSR stub so harvest does not loop; unbilled only when stated.
function completeCancelledOrderDetailsStub(order, now, orderDetails)
  if type(order) ~= 'table' then
    return
  end
  if type(now) ~= 'number' then
    now=os.time()
  end
  order.unbilledCancel=cancelledStubLooksUnbilled(orderDetails)
  order.orderTotal=0
  order.orderPositions={}
  order.returnedPositions={}
  order.orderSum=0
  order.summaryExtras={}
  -- Keep unknown bookingDate as invalidDate so stubs do not skew cutoff/refund windows.
  order.detailsParsed=true
  scheduleNextDetailsDate(order, now)
end

--- Handle Bestelldetails HTML that has a root but no parseable orderDate.
--- @return boolean true when the fetch counts as successfully resolved
function resolveOrderDetailsWithoutDate(order, orderDetails)
  local now=os.time()
  if isCancelledOrderDetailsStub(orderDetails) then
    completeCancelledOrderDetailsStub(order, now, orderDetails)
    return true
  end
  if isUnloadableOrderDetailsPage(orderDetails) then
    scheduleNextDetailsDate(order, now)
    debugBuffer.print("getOrderDetails unloadable page",order.orderCode)
    return false
  end
  debugBuffer.print("getOrderDetails missing order date",order.orderCode)
  return false
end

--- @function getSummaryExtrasFromDetails
-- Bookable Bestellübersicht rows (shipping, coupon, gift wrap, …), signed cents.
function getSummaryExtrasFromDetails(orderDetails)
  local extras={}
  local skipReturnCredits=orderDetailsHasReturnActivity(orderDetails)
  orderDetails:xpath('.//div[contains(@class,"od-line-item-row")]'):each(function(index,row)
    local name=normalizeSummaryLabel(row:xpath('.//*[contains(@class,"od-line-item-row-label")]'):text())
    local kind=summaryLabelKind(name)
    if kind == 'skip' then
      return
    end
    if skipReturnCredits and kind == 'credit' then
      return
    end
    local amount=signedSummaryAmount(row:xpath('.//*[contains(@class,"od-line-item-row-content")]'):text(), kind)
    if amount == invalidPrice or amount == 0 then
      return
    end
    table.insert(extras,{name=name,amount=amount})
  end)
  return extras
end

--- @function resolvedSummaryExtras
-- Named extras (shipping, coupon, …). VAT and leftover are not booked.
function resolvedSummaryExtras(order)
  local extras={}
  if type(order) == 'table' and type(order.summaryExtras) == 'table' then
    for _,extra in ipairs(order.summaryExtras) do
      local amount=tonumber(extra.amount)
      local name=extra.name
      if type(name) == 'string' and name ~= '' and amount ~= nil and amount ~= 0 then
        table.insert(extras,{name=name,amount=amount})
      end
    end
  end
  local leftover=0
  if type(order) == 'table' then
    local orderSum=tonumber(order.orderSum)
    local orderTotal=tonumber(order.orderTotal)
    if orderSum ~= nil and orderTotal ~= nil then
      leftover=orderTotal-orderSum
    end
  end
  for _,extra in ipairs(extras) do
    leftover=leftover-extra.amount
  end
  return extras, leftover
end

--- @function getTotalsFromDetails
-- Grand total in cents from the 2024+ order summary, or invalidPrice.
function getTotalsFromDetails(orderDetails)
  -- Anchor on "Gesamtsumme" / "Grand Total"; fall back to the last bold row.
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
    return labelTotal
  end
  return lastBold
end

--- @function isReturnedOrderItemRow
-- Returned items keep a return-status link; refund is booked via getRefundFromDetails.
function isReturnedOrderItemRow(item)
  if item == nil then
    return false
  end
  local grid=item:xpath('ancestor::div[contains(concat(" ",normalize-space(@class)," ")," a-fixed-left-grid-inner ")][1]')
  if grid:length() == 0 then
    return false
  end
  if grid:xpath('.//a[contains(@href,"return")]'):length() > 0 then
    return true
  end
  return grid:xpath('.//a[contains(.,"Rücksendung") or contains(.,"Erstattung")]'):length() > 0
end

--- @function getPositionsFromDetails
-- 2024+ layout: each purchased item is a "purchasedItemsRightGrid" block holding
-- data-component itemTitle / unitPrice / quantity. Fills order.orderPositions
-- and order.orderSum. Returned items are omitted (refund line covers them).
-- @param #table orderDetails
-- @param #order order
function getPositionsFromDetails(orderDetails,order)
  order.orderPositions={}
  order.returnedPositions={}
  order.orderSum=0
  orderDetails:xpath('.//*[@data-component="purchasedItemsRightGrid"]'):each(function(index,item)
    local purpose=trim(item:xpath('.//*[@data-component="itemTitle"]'):text())
    local priceText=item:xpath('.//*[@data-component="unitPrice"]//*[contains(@class,"a-offscreen")]'):text()
    if priceText == '' then
      priceText=item:xpath('.//*[@data-component="unitPrice"]'):text()
    end
    local amount=getPrice(priceText)
    local qtyText=item:xpath('ancestor::div[contains(concat(" ",normalize-space(@class)," ")," a-fixed-left-grid-inner ")][1]//div[contains(@class,"od-item-view-qty")]'):text()
    if qtyText == '' then
      qtyText=item:xpath('.//*[@data-component="quantity"]'):text()
    end
    local qty=getQtyNew(qtyText)
    if purpose == '' or amount == invalidPrice then
      order.invalidArticles=true
      return
    end
    local position={purpose=purpose,amount=amount,qty=qty}
    if isReturnedOrderItemRow(item) then
      table.insert(order.returnedPositions,position)
    else
      table.insert(order.orderPositions,position)
      order.orderSum=order.orderSum+amount*qty
    end
  end)
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

--- Infer refund from return credit rows (e.g. Gutschein = retained return shipping) when
--- Amazon omits "Summe der Erstattung".
function inferReturnRefundFromDetails(orderDetails, order, bookingDate)
  if adjustmentCreditCents(order) > 0 then
    return
  end
  local returned=effectiveReturnedCents(order)
  if returned <= 0 then
    return
  end
  orderDetails:xpath('.//div[contains(@class,"od-line-item-row")]'):each(function(index,row)
    local name=normalizeSummaryLabel(row:xpath('.//*[contains(@class,"od-line-item-row-label")]'):text())
    local kind=summaryLabelKind(name)
    if kind ~= 'credit' then
      return
    end
    local credit=getPrice(row:xpath('.//*[contains(@class,"od-line-item-row-content")]'):text())
    if credit == invalidPrice or credit <= 0 or credit >= returned then
      return
    end
    registerRefundTransaction(order, bookingDate, returned-credit)
  end)
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
    error("Amazon: Bestelldatum für Erstattung fehlt oder ist ungültig.")
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
  if orderDetailsHasReturnActivity(orderDetails) then
    inferReturnRefundFromDetails(orderDetails, order, bookingDate)
  end
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
  local parsed=false
  if order.detailsUrl == nil or order.detailsUrl == "" then
    order.detailsUrl=buildDetailsUrl(order.orderCode)
  end
  local html=connectShopWithCheck("GET",order.detailsUrl)
  if html == nil then
    debugBuffer.print("getOrderDetails request failed",order.orderCode)
    debugBuffer.context=''
    return false
  end
  local orderDetails=html:xpath('//div[contains(@id,"orderDetails")]')
  if orderDetails:text() ~= "" then
    local hadPositionsBeforeParse=orderHasPositions(order)
    local date=getDate(orderDetails:xpath('.//*[@data-component="orderDate"]'):text())
    if date == invalidDate then
      local resolved=resolveOrderDetailsWithoutDate(order, orderDetails)
      debugBuffer.context=''
      return resolved
    end
    order.bookingDate=date

    if isUnbilledCancellation(orderDetails) then
      order.unbilledCancel=true
    else
      order.unbilledCancel=nil
    end

    local orderTotal=getTotalsFromDetails(orderDetails)
    if order.unbilledCancel then
      order.orderTotal=0
    elseif orderTotal ~= invalidPrice then
      order.orderTotal=orderTotal
    end

    getPositionsFromDetails(orderDetails,order)
    if order.invalidArticles ~= nil then
      order.orderPositions={}
      order.returnedPositions={}
      order.orderSum=0
      order.invalidArticles=nil
    end
    order.returnActivity=orderDetailsHasReturnActivity(orderDetails)
    order.summaryExtras=getSummaryExtrasFromDetails(orderDetails)
    if not hadPositionsBeforeParse and orderHasPositions(order) then
      -- Empty/failed parse must not permanently block a later real position emit.
      clearOrderEmittedFlags(order, true)
    end
    if not order.unbilledCancel then
      getRefundFromDetails(orderDetails,order)
    end
    getOrderaddress(orderDetails,order)
    order.mandateReference=getPaymentMethod(orderDetails)
    order.detailsParsed=true
    scheduleNextDetailsDate(order, os.time())
    parsed=true
  else
    debugBuffer.print("getOrderDetails no details",order.orderCode)
  end
  debugBuffer.context=''
  return parsed
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
        bookingDate=invalidDate,
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
-- Short windows re-scanned often. months-3 is only "recent" when the scan window
-- is at least 3 months (or unlimited); otherwise last30 covers incremental cutoffs.
-- Business B2B UI uses German values like "Letzte 30.Tage" / "Letzte 3.Monate".
function isRecentOrderFilter(filterVal, scanMonths)
  if type(filterVal) ~= 'string' then
    return false
  end
  local monthsLimit=tonumber(scanMonths)
  local includeThreeMonth=monthsLimit == nil or monthsLimit <= 0 or monthsLimit >= 3
  if string.match(filterVal, "^last") ~= nil then
    return true
  end
  if filterVal == const.recentMonthsFilter or filterVal == "yoPast3months"
      or filterVal == "last_3_months" then
    return includeThreeMonth
  end
  if string.find(filterVal, "30.Tage", 1, true) or string.find(filterVal, "30 Tage", 1, true)
      or filterVal == "yoLast30Days" or filterVal == "last_30_days" then
    return true
  end
  if includeThreeMonth and (
      string.find(filterVal, "3.Monate", 1, true) or string.find(filterVal, "3 Monate", 1, true)) then
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
  if isRecentOrderFilter(filterVal, months) then
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

--- @function scheduleKnownOrderDetailsRefresh
-- Incremental harvest: known Bestellnummer reappearing in the window re-queues details
-- so refunds/returns are picked up without the obsolete message-center scrape.
function scheduleKnownOrderDetailsRefresh(order)
  if type(order) ~= 'table' or LocalStorage == nil then
    return false
  end
  local refreshSince=LocalStorage.refreshSince
  local now=os.time()
  if not isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return false
  end
  if type(order.detailsDate) == 'number' and order.detailsDate <= 1 then
    return false
  end
  order.detailsDate=1
  return true
end

--- Incremental refresh: re-queue details for already-emitted orders in the harvest window
-- (refund/return pickup without the obsolete message-center scrape).
function incrementalRefundWatchSince(now)
  if type(now) ~= 'number' then
    return nil
  end
  return now - const.incrementalRefundWatchMaxAgeSec
end

function scheduleIncrementalRefundWatch(accountNumber, refreshSince, now)
  if type(LocalStorage) ~= 'table' or type(LocalStorage.OrderCache) ~= 'table' then
    return 0
  end
  if not isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return 0
  end
  local watchSince=incrementalRefundWatchSince(now)
  if watchSince == nil then
    return 0
  end
  local n=0
  for _,order in pairs(LocalStorage.OrderCache) do
    if type(order) ~= 'table' or not orderMatchesMoneyMoneyAccount(order, accountNumber) then
      -- skip
    elseif not orderMayNeedIncrementalRefundWatch(order, now) then
      -- outside 90d window, unbilled, or refund fully settled
    elseif type(order.bookingDate) ~= 'number' or order.bookingDate < watchSince then
      -- skip (belt-and-suspenders vs orderMayNeedIncrementalRefundWatch)
    elseif type(order.detailsDate) == 'number' and order.detailsDate <= 1 then
      -- already queued
    elseif type(order.detailsDate) == 'number' and order.detailsDate > now then
      -- respect scheduleNextDetailsDate; do not re-fetch before rescan is due
    elseif isOrderEmittedForAccount(order, accountNumber) then
      order.detailsDate=1
      n=n+1
    end
  end
  return n
end

--- Inserts a new order or refreshes sub-account meta on an existing one.
-- When orderStub is nil, builds a minimal stub from orderCode.
-- @return true if newly inserted
function upsertOrderInCache(orderCache, orderCode, orderStub, subAccountLabel, kind)
  if type(orderCache) ~= 'table' or type(orderCode) ~= 'string' or orderCode == '' then
    return false
  end
  local existing=orderCache[orderCode]
  if existing ~= nil then
    assignSubAccountMeta(existing, subAccountLabel, kind)
    scheduleKnownOrderDetailsRefresh(existing)
    return false
  end
  local order=orderStub
  if type(order) ~= 'table' then
    order={
      orderCode=orderCode,
      orderPositions={},
      orderSum=0,
      orderTotal=0,
      refund=0,
      bookingDate=invalidDate,
      detailsDate=0,
      detailsUrl=buildDetailsUrl(orderCode),
    }
  end
  assignSubAccountMeta(order, subAccountLabel, kind)
  orderCache[orderCode]=order
  return true
end

--- @function mergeOrdersFromPage
-- Merges getOrdersFromSummary(html) into orderCache.
-- @param subAccountLabel optional Amazon-Unterkonto label stored on new orders
-- @param kind optional "personal"|"business" for ListAccounts filtering
-- @return foundOrders, foundNewOrders, newCount
function mergeOrdersFromPage(htmlNode, orderCache, subAccountLabel, kind)
  if type(orderCache) ~= 'table' then
    error("mergeOrdersFromPage: orderCache must be a table")
  end
  local foundOrders=false
  local foundNewOrders=false
  local newCount=0
  for orderCode,order in pairs(getOrdersFromSummary(htmlNode)) do
    foundOrders=true
    if upsertOrderInCache(orderCache, orderCode, order, subAccountLabel, kind) then
      foundNewOrders=true
      newCount=newCount+1
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

function setOrderListHarvestIncomplete(subAccountLabel, incomplete)
  if LocalStorage == nil or type(subAccountLabel) ~= 'string' or subAccountLabel == '' then
    return
  end
  if type(LocalStorage.orderListHarvestIncompleteByAccount) ~= 'table' then
    LocalStorage.orderListHarvestIncompleteByAccount={}
  end
  if incomplete then
    LocalStorage.orderListHarvestIncompleteByAccount[subAccountLabel]=true
  else
    LocalStorage.orderListHarvestIncompleteByAccount[subAccountLabel]=nil
  end
end

function isOrderListHarvestIncomplete(subAccountLabel)
  local states=LocalStorage and LocalStorage.orderListHarvestIncompleteByAccount
  return type(states) == 'table' and states[subAccountLabel] == true
end

--- @function scanOrderFilterPages
-- Walks the current order-list page and its "next" links (no filter submit).
-- Mutates global html when paginating. May mark orderFilterCache[filterVal].
-- @return foundOrders, foundNewOrders, newCount, paginationComplete
function scanOrderFilterPages(orderFilterVal, orderCache, orderFilterCache, subAccountLabel, kind)
  local foundOrders=false
  local foundNewOrders=false
  local newCountTotal=0
  if html == nil then
    print("scanOrderFilterPages: html is nil, skip filter", tostring(orderFilterVal))
    setOrderListHarvestIncomplete(subAccountLabel, true)
    return foundOrders, foundNewOrders, newCountTotal, false
  end
  local foundEnd=false
  local paginationComplete=true
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
        setOrderListHarvestIncomplete(subAccountLabel, true)
        paginationComplete=false
        foundEnd=true
      else
        html=nextHtml
      end
    else
      foundEnd=true
    end
  until foundEnd
  if paginationComplete then
    markOrderFilterCacheIfComplete(orderFilterCache, orderFilterVal, foundNewOrders)
  end
  return foundOrders, foundNewOrders, newCountTotal, paginationComplete
end

function absoluteAmazonUrl(url)
  if type(url) ~= 'string' or url == '' then
    return url
  end
  if string.match(url, "^https?://") then
    if not string.match(url, "^https://") then
      error("absoluteAmazonUrl: only https allowed")
    end
    local host = string.match(url, "^https://([^/?#]+)")
    if not host then
      error("absoluteAmazonUrl: invalid absolute URL")
    end
    host = string.lower(host)
    -- Ignore explicit default ports when comparing to baseurl origin.
    host = string.gsub(host, ":443$", "")
    host = string.gsub(host, ":80$", "")
    local allowedHost = string.lower(string.match(baseurl, "^https?://([^/?#]+)"))
    if host ~= allowedHost then
      error("absoluteAmazonUrl: host not allowed: " .. host)
    end
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

function parseAmazonCustomerIdFromHtml(htmlOrText)
  local text=htmlOrText
  if type(text) == 'table' and type(text.html) == 'function' then
    text=text:html()
  end
  if type(text) ~= 'string' or text == '' then
    return nil
  end
  local id=string.match(text, "[\"']?customer[Ii][Dd][\"']?%s*[:=]%s*[\"'](A[A-Z0-9]+)[\"']")
  if type(id) == 'string' and id ~= '' then
    return id
  end
  return nil
end

function inferSubAccountKindFromAmazonType(accountType)
  if type(accountType) ~= 'string' or accountType == '' then
    return nil
  end
  local normalized=string.lower(accountType)
  if string.find(normalized, "business", 1, true)
      or string.find(normalized, "geschäft", 1, true)
      or string.find(normalized, "geschaeft", 1, true)
      or string.find(normalized, "gewerbe", 1, true) then
    return "business"
  end
  if string.find(normalized, "personal", 1, true)
      or string.find(normalized, "persönlich", 1, true)
      or string.find(normalized, "persoenlich", 1, true)
      or string.find(normalized, "privat", 1, true) then
    return "personal"
  end
  return nil
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
    else
      local kindFromType=inferSubAccountKindFromAmazonType(accountType)
      if kindFromType ~= nil then
        kind=kindFromType
      end
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
  local returnTo=MM.urlencode(baseurl..const.businessHomepageAfterSwitch)
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
  local ya=connectShop("GET", absoluteAmazonUrl(const.businessHomepageYourAccount))
  local switchHref=findAccountSwitcherHref(ya)
  if switchHref == '' then
    switchHref=defaultAccountSwitcherSigninUrl()
    print("account switcher link not in DOM, using OpenID picker URL")
  end
  local signin=connectShop("GET", absoluteAmazonUrl(switchHref))
  if signin == nil then
    print("account switcher sign-in page unavailable")
    return nil
  end
  if signin:xpath('//form[contains(@class,"cvf-widget-form-account-switcher")]'):length() > 0 then
    return signin
  end
  local embedSrc=signin:xpath('//*[contains(@src,"cvf/request.embed")]'):attr('src')
  if embedSrc == '' then
    local arb=signin:xpath('//div[@data-arbtoken]'):attr('data-arbtoken')
    embedSrc=accountSwitcherEmbedUrl(arb, cvfEmbedVersionQuery(signin)) or ''
  end
  if embedSrc == '' then
    if switchAuthBlockReason(signin) ~= nil then
      return signin
    end
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

--- Amazon login/switch auth challenges (priority for enterable codes):
-- 1) Enterable OTP: classic auth-mfa-form, CVF verification-code-form (SMS/TOTP/Email/WhatsApp)
-- 2) Claims channel picker: claimspicker
-- 3) Claims verify OTP: form[@action="verify"] (field name=code)
-- 4) Device select: auth-select-device-form (TOTP/SMS/WhatsApp/EMAIL/VOICE)
-- 5) App approval polling: pollingForm without enterable OTP (Amazon-App-Freigabe)
-- 6) Captcha / password (handled in login loop)

local AMAZON_DEFAULT_OTP_PROMPT='Bitte den Bestätigungscode eingeben.'
local AMAZON_LOGIN_OTP_TITLE='Zwei-Faktor-Authentifizierung'
local AMAZON_SWITCH_OTP_TITLE='Amazon Konto wechseln – 2FA'

function isCvfVerificationCodeOtpPage(htmlNode)
  return htmlNode ~= nil
    and htmlNode:xpath('//form[@id="verification-code-form"]'):length() > 0
end

--- SSOT: form that accepts an otpCode typed in MoneyMoney.
function amazonEnterableOtpForm(htmlNode)
  if htmlNode == nil then
    return nil
  end
  local classic=htmlNode:xpath('//form[@id="auth-mfa-form"]')
  if classic:length() > 0 then
    return classic
  end
  if isCvfVerificationCodeOtpPage(htmlNode) then
    return htmlNode:xpath('//form[@id="verification-code-form"]')
  end
  return htmlNode:xpath('//form[.//*[@name="otpCode"]]')
end

function isAmazonEnterableOtpPage(htmlNode)
  local form=amazonEnterableOtpForm(htmlNode)
  return form ~= nil and form:length() > 0
end

function isAmazonMfaPage(htmlNode)
  return isAmazonEnterableOtpPage(htmlNode)
end

function isAmazonClaimsVerifyPage(htmlNode)
  return htmlNode ~= nil
    and htmlNode:xpath('//form[@action="verify"]'):length() > 0
end

function isAmazonClaimsPickerPage(htmlNode)
  return htmlNode ~= nil
    and htmlNode:xpath('//form[@name="claimspicker"]'):length() > 0
end

function isAmazonAuthDeviceSelectPage(htmlNode)
  return htmlNode ~= nil
    and htmlNode:xpath('//form[@id="auth-select-device-form"]'):length() > 0
end

--- App notification approval only when no enterable OTP is offered on the same page.
function isAmazonAppApprovalPollingPage(htmlNode)
  if htmlNode == nil or isAmazonEnterableOtpPage(htmlNode) then
    return false
  end
  return htmlNode:xpath('//form[@id="pollingForm"]'):length() > 0
end

function isAmazonPasswordSignInPage(htmlNode)
  return htmlNode ~= nil
    and htmlNode:xpath('//form[contains(@name,"signIn")]//*[@name="password"]'):length() > 0
end

--- Interactive auth walls that are *not* enterable OTP/code (switch blocks / discovery).
function isAmazonAuthenticationChallengePage(htmlNode)
  if htmlNode == nil
      or isAmazonEnterableOtpPage(htmlNode)
      or isAmazonClaimsVerifyPage(htmlNode) then
    return false
  end
  return isAmazonAppApprovalPollingPage(htmlNode)
    or isAmazonAuthDeviceSelectPage(htmlNode)
    or htmlNode:xpath('//img[@id="auth-captcha-image"]'):length() > 0
    or isAmazonClaimsPickerPage(htmlNode)
end

--- Prefer channels MoneyMoney can complete with a typed code.
-- TOTP > SMS > WhatsApp > EMAIL > VOICE > unknown (suffix match, case-insensitive).
function amazonAuthDeviceChannelScore(deviceValue)
  if type(deviceValue) ~= 'string' or deviceValue == '' then
    return 0
  end
  local upper=deviceValue:upper()
  if endsWith(upper, 'TOTP') then
    return 30
  end
  -- WHATSAPP before SMS: avoid any future suffix ambiguity.
  if endsWith(upper, 'WHATSAPP') then
    return 18
  end
  if endsWith(upper, 'SMS') then
    return 20
  end
  if endsWith(upper, 'EMAIL') then
    return 15
  end
  if endsWith(upper, 'VOICE') then
    return 5
  end
  return 0
end

--- Selects the best otpDeviceContext radio on auth-select-device-form.
-- @return selected device value (may be '')
function applyPreferredAmazonAuthDeviceSelection(authSelectForm)
  if authSelectForm == nil or authSelectForm:length() == 0 then
    return ''
  end
  local otpDeviceContext=''
  local score=-1000
  authSelectForm:xpath('.//input[@type="radio"]'):each(function(_, element)
    local k=element:attr('value')
    local v=amazonAuthDeviceChannelScore(k)
    if score < v then
      otpDeviceContext=k
      score=v
    end
  end)
  authSelectForm:xpath('.//input[@type="radio"]'):each(function(_, element)
    if element:attr('value') == otpDeviceContext then
      element:attr('checked', 'checked')
      print("select device channel "..tostring(otpDeviceContext))
    else
      element:attr('checked', '')
    end
  end)
  return otpDeviceContext
end

--- MoneyMoney interactive challenge table (OTP / claims verify).
function moneyMoneyOtpChallenge(title, challengeText)
  local prompt=challengeText
  if type(prompt) ~= 'string' or prompt == '' then
    prompt=AMAZON_DEFAULT_OTP_PROMPT
  end
  local challengeTitle=title
  if type(challengeTitle) ~= 'string' or challengeTitle == '' then
    challengeTitle=AMAZON_LOGIN_OTP_TITLE
  end
  return {
    title=challengeTitle,
    challenge=prompt,
    label='Code'
  }
end

--- Challenge text for classic MFA, CVF SMS/OTP, or authenticator pages.
function amazonMfaChallengePrompt(htmlNode)
  if htmlNode == nil then
    return AMAZON_DEFAULT_OTP_PROMPT
  end
  local classic=htmlNode:xpath('//form[@id="auth-mfa-form"]//p'):text()
  if classic ~= '' then
    return classic
  end
  local raw=htmlNodeRaw(htmlNode)
  if type(raw) ~= 'string' then
    raw=''
  end
  local phoneDe=string.match(raw, "Zu deiner Sicherheit haben wir den Code an dein Telefon[^<]*")
  if type(phoneDe) == 'string' and phoneDe ~= '' then
    return phoneDe
  end
  local phoneEn=string.match(raw, "[Ww]e[^<]{0,40}sent[^<]{0,40}code[^<]{0,40}phone[^<]*")
  if type(phoneEn) == 'string' and phoneEn ~= '' then
    return phoneEn
  end
  local emailDe=string.match(raw, "Code an [^<]*[Ee]-?[Mm]ail[^<]*")
  if type(emailDe) == 'string' and emailDe ~= '' then
    return emailDe
  end
  if string.find(raw, "Authenticator", 1, true) ~= nil
    or string.find(raw, "Zwei-Schritt-App", 1, true) ~= nil
    or string.find(raw, "authenticator app", 1, true) ~= nil then
    return 'Bitte den Code aus der Authenticator-App eingeben.'
  end
  local rawLower=raw:lower()
  if string.find(rawLower, "whatsapp", 1, true) ~= nil then
    return 'Bitte den Bestätigungscode aus WhatsApp eingeben.'
  end
  return AMAZON_DEFAULT_OTP_PROMPT
end

function enterableOtpChallengeFromHtml(htmlNode, title)
  if not isAmazonEnterableOtpPage(htmlNode) then
    return nil
  end
  return moneyMoneyOtpChallenge(title, amazonMfaChallengePrompt(htmlNode))
end

function loginOtpChallengeFromHtml(htmlNode)
  return enterableOtpChallengeFromHtml(htmlNode, AMAZON_LOGIN_OTP_TITLE)
end

function mfaChallengeFromHtml(htmlNode)
  return enterableOtpChallengeFromHtml(htmlNode, AMAZON_SWITCH_OTP_TITLE)
end

--- MoneyMoney challenge table for Amazon claims verify (field name=code).
-- @param titleOverride optional; when set, replaces the page title (switch MFA).
function claimsVerifyChallengeFromHtml(htmlNode, titleOverride)
  if htmlNode == nil or not isAmazonClaimsVerifyPage(htmlNode) then
    return nil
  end
  local title=titleOverride
  if type(title) ~= 'string' or title == '' then
    title=htmlNode:xpath('//form[@action="verify"]//div[1]//div[1]'):text()
  end
  return moneyMoneyOtpChallenge(
    title,
    htmlNode:xpath('//form[@action="verify"]//div[1]//div[2]'):text())
end

--- Present claims-verify challenge once; next login step submits the code.
-- @return challengeTable | nil, failLabel
function takeClaimsVerifyChallengeForLogin(htmlNode)
  claimsVerify1run=false
  local ch=claimsVerifyChallengeFromHtml(htmlNode)
  if ch == nil then
    return nil, "Bestätigungscode"
  end
  return ch, nil
end

--- Login helper: claims-verify challenge or failMissingLoginPage result.
function returnClaimsVerifyChallengeOrFail(htmlNode)
  local ch, failLabel=takeClaimsVerifyChallengeForLogin(htmlNode)
  if ch == nil then
    return failMissingLoginPage(failLabel)
  end
  return ch
end

function submitAmazonClaimsPicker(htmlNode)
  if htmlNode == nil then
    return nil, "claimspicker page missing"
  end
  local form=htmlNode:xpath('//form[@name="claimspicker"]')
  if form:length() == 0 then
    return nil, "claimspicker form missing"
  end
  local nextPage=connectShopForm(form)
  if nextPage == nil then
    return nil, "claimspicker submit failed"
  end
  return nextPage, nil
end

function submitAmazonMfa(htmlNode, otpCode)
  if htmlNode == nil then
    return nil, "MFA page missing"
  end
  if type(otpCode) ~= 'string' or otpCode == '' then
    return nil, "MFA code missing"
  end
  local form=amazonEnterableOtpForm(htmlNode)
  if form == nil or form:length() == 0 then
    return nil, "MFA form missing"
  end
  htmlNode:xpath('//*[@name="otpCode"]'):attr("value", otpCode)
  -- CVF JS copies the visible field into otpCodeHidden before submit.
  local otpHidden=htmlNode:xpath('//*[@name="otpCodeHidden"]')
  if otpHidden:length() > 0 then
    otpHidden:attr("value", otpCode)
  end
  htmlNode:xpath('//*[@name="rememberDevice"]'):attr('checked', 'checked')
  local nextPage=connectShopForm(form)
  if nextPage == nil then
    return nil, "MFA submit failed"
  end
  return nextPage, nil
end

function submitAmazonClaimsVerify(htmlNode, code)
  if htmlNode == nil then
    return nil, "verify page missing"
  end
  if type(code) ~= 'string' or code == '' then
    return nil, "verify code missing"
  end
  local form=htmlNode:xpath('//form[@action="verify"]')
  if form:length() == 0 then
    return nil, "verify form missing"
  end
  htmlNode:xpath('//*[@name="code"]'):attr("value", code)
  local nextPage=connectShopForm(form)
  if nextPage == nil then
    return nil, "verify submit failed"
  end
  return nextPage, nil
end

--- OTP challenge during sub-account switch (classic/CVF otpCode or claims verify).
function switchOtpChallengeFromHtml(htmlNode)
  return mfaChallengeFromHtml(htmlNode)
    or claimsVerifyChallengeFromHtml(htmlNode, AMAZON_SWITCH_OTP_TITLE)
end

--- Submit whatever enterable OTP form the switch landing currently shows.
function submitAmazonSwitchOtp(htmlNode, otpCode)
  if isAmazonEnterableOtpPage(htmlNode) then
    return submitAmazonMfa(htmlNode, otpCode)
  end
  if isAmazonClaimsVerifyPage(htmlNode) then
    return submitAmazonClaimsVerify(htmlNode, otpCode)
  end
  return nil, "MFA form missing"
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
  local nextPage=connectShopForm(form)
  if nextPage == nil then
    return nil, "auth_prompt submit failed"
  end
  return nextPage, nil
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
  local mfa=switchOtpChallengeFromHtml(htmlNode)
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
  if isAmazonMfaPage(htmlNode) or isAmazonClaimsVerifyPage(htmlNode) then
    return "MFA"
  end
  if isAmazonPasswordSignInPage(htmlNode) then
    return "interactive login"
  end
  if isAmazonAuthenticationChallengePage(htmlNode) then
    return "authentication challenge"
  end
  if isAkamaiInterstitial(htmlNode) then
    return "security challenge"
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

--- Parse pow / bm-verify / meta-refresh from an Akamai interstitial HTML body.
function parseAkamaiInterstitialChallenge(raw)
  if type(raw) ~= 'string' or raw == '' then
    return nil
  end
  local iVal=tonumber(string.match(raw, "var%s+i%s*=%s*(%d+)"))
  local n1, n2=string.match(raw, 'Number%s*%(%s*"(%d+)"%s*%+%s*"(%d+)"%s*%)')
  -- Prefer the JSON.stringify payload token (not the distinct meta-refresh URL token).
  local bmVerify=string.match(raw, 'JSON%.stringify%(%s*{%s*"bm%-verify"%s*:%s*"([^"]+)"')
  if bmVerify == nil then
    local last
    for tok in string.gmatch(raw, '"bm%-verify"%s*:%s*"([^"]+)"') do
      last=tok
    end
    bmVerify=last
  end
  local refresh=string.match(raw, "[Uu][Rr][Ll]%s*=%s*'([^']+)'")
    or string.match(raw, '[Uu][Rr][Ll]%s*=%s*"([^"]+)"')
  local pow=nil
  if iVal ~= nil and n1 ~= nil and n2 ~= nil then
    pow=iVal + tonumber(n1..n2)
  end
  return {
    bmVerify=bmVerify,
    pow=pow,
    refresh=refresh,
  }
end

function absoluteAmazonShopUrl(pathOrUrl)
  if type(pathOrUrl) ~= 'string' or pathOrUrl == '' then
    return nil
  end
  local url=pathOrUrl:gsub("&amp;", "&")
  if string.sub(url, 1, 1) == '/' then
    return baseurl..url
  end
  if string.match(url, "^https?://") == nil then
    return baseurl.."/"..url
  end
  return url
end

--- Follow noscript/meta-refresh bm-verify URL (safe when POST verify returns HTTP 400).
function followAkamaiMetaRefresh(challenge)
  if type(challenge) ~= 'table' or type(challenge.refresh) ~= 'string' or challenge.refresh == '' then
    return nil, "Akamai meta-refresh missing"
  end
  local refresh=absoluteAmazonShopUrl(challenge.refresh)
  if refresh == nil then
    return nil, "Akamai meta-refresh missing"
  end
  print("Akamai interstitial: follow meta-refresh")
  return connectShop("GET", refresh), nil
end

--- POST /_sec/verify; may be aborted by MoneyMoney on HTTP 400 — callers must prefer meta-refresh.
function postAkamaiInterstitialVerify(challenge)
  if type(challenge) ~= 'table'
      or type(challenge.bmVerify) ~= 'string' or challenge.bmVerify == ''
      or type(challenge.pow) ~= 'number' then
    return nil, "Akamai verify payload incomplete"
  end
  local body='{"bm-verify":'..jsonQuote(challenge.bmVerify)..',"pow":'..tostring(challenge.pow)..'}'
  local ok, content=pcall(function()
    return connectShopRaw("POST", baseurl.."/_sec/verify?provider=interstitial", body,
      "application/json", {
        ["Accept"]="application/json",
      })
  end)
  if not ok then
    return nil, "Akamai verify request failed: "..tostring(content)
  end
  return content, nil
end

function followAkamaiVerifyResponse(content)
  if type(content) ~= 'string' then
    return nil
  end
  local location=string.match(content, '"location"%s*:%s*"([^"]+)"')
  if location ~= nil and location ~= '' then
    location=location:gsub("\\/", "/")
    location=absoluteAmazonShopUrl(location)
    print("Akamai interstitial: follow location")
    return connectShop("GET", location)
  end
  if string.find(content, '"reload"%s*:%s*true') then
    print("Akamai interstitial: reload after verify")
    return connectShop("GET", baseurl.."/")
  end
  return nil
end

function clearAkamaiViaVerifyPost(challenge)
  local content, postErr=postAkamaiInterstitialVerify(challenge)
  if content == nil then
    return nil, postErr
  end
  local followed=followAkamaiVerifyResponse(content)
  if followed ~= nil then
    return followed, nil
  end
  return nil, "Akamai verify response incomplete"
end

function refreshAkamaiChallengeAfterStickyPage(challenge, page)
  if page == nil or not isAkamaiInterstitial(page) then
    return challenge
  end
  return parseAkamaiInterstitialChallenge(htmlNodeRaw(page)) or challenge
end

function firstClearedAkamaiPage(page)
  if page ~= nil and not isAkamaiInterstitial(page) then
    return page
  end
  return nil
end

function metaRefreshOrKeepSticky(challenge, page, refreshErr)
  if page ~= nil then
    return page, refreshErr
  end
  return followAkamaiMetaRefresh(challenge)
end

function resolveParsedAkamaiChallenge(challenge)
  local page, refreshErr=followAkamaiMetaRefresh(challenge)
  if firstClearedAkamaiPage(page) then
    return page, nil
  end
  challenge=refreshAkamaiChallengeAfterStickyPage(challenge, page)
  local cleared, postErr=clearAkamaiViaVerifyPost(challenge)
  if cleared ~= nil then
    return cleared, nil
  end
  page, refreshErr=metaRefreshOrKeepSticky(challenge, page, refreshErr)
  if firstClearedAkamaiPage(page) then
    return page, nil
  end
  return nil, postErr or refreshErr or "Akamai interstitial incomplete"
end

--- @function completeAkamaiInterstitial
-- Completes Amazon/Akamai interstitial without a browser JS engine.
-- Prefer meta-refresh GET first: MoneyMoney may abort the whole session on HTTP 400
-- from POST /_sec/verify (see MoneyMoney-202609051525.log).
function completeAkamaiInterstitial(htmlNode)
  local raw=htmlNodeRaw(htmlNode)
  print("Akamai interstitial: completing challenge")
  local challenge=parseAkamaiInterstitialChallenge(raw)
  if challenge == nil then
    return nil, "Akamai interstitial incomplete"
  end
  return resolveParsedAkamaiChallenge(challenge)
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

--- Amazon timeFilter options actually offered for a sub-account (from the order-list select).
-- hasMore must not invent years back to 2000 that the account UI never lists.
function rememberOfferedOrderFilters(subAccountLabel, filterVals)
  if LocalStorage == nil or type(subAccountLabel) ~= 'string' or subAccountLabel == '' then
    return
  end
  if type(filterVals) ~= 'table' then
    return
  end
  if type(LocalStorage.offeredOrderFiltersByAccount) ~= 'table' then
    LocalStorage.offeredOrderFiltersByAccount={}
  end
  local offered={}
  for _, val in ipairs(filterVals) do
    if type(val) == 'string' and val ~= '' then
      offered[val]=true
    end
  end
  if next(offered) == nil then
    return
  end
  LocalStorage.offeredOrderFiltersByAccount[subAccountLabel]=offered
end

function offeredOrderFiltersForSubAccount(subAccountLabel)
  local byAccount=LocalStorage and LocalStorage.offeredOrderFiltersByAccount
  if type(byAccount) ~= 'table' or type(subAccountLabel) ~= 'string' or subAccountLabel == '' then
    return nil
  end
  local offered=byAccount[subAccountLabel]
  if type(offered) ~= 'table' or next(offered) == nil then
    return nil
  end
  return offered
end

function ensureOrderCache()
  if LocalStorage.OrderCache == nil then
    LocalStorage.OrderCache={}
  end
  return LocalStorage.OrderCache
end

function ensureInvalidCache()
  if LocalStorage == nil then
    return
  end
  if LocalStorage.invalidCache == nil then
    LocalStorage.invalidCache={}
  end
end

function shouldHarvestOrderFilter(orderFilterVal, orderFilterCache, numbersOfNewOrders, refreshSince, now)
  now=now or os.time()
  local scanMonths=effectiveScanFiltersMonths(refreshSince, now)
  if not orderFilterWithinScanMonths(orderFilterVal, scanMonths, os.date('*t', now)) then
    return false
  end
  return isRecentOrderFilter(orderFilterVal, scanMonths)
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
-- Active Amazon Business identity (e.g. after switch to a business account).
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
-- Extracts Bestellnummern from arbitrary HTML/CSV/text (ABA report).
-- @return foundOrders, foundNewOrders, newCount
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
      if upsertOrderInCache(orderCache, orderCode, nil, subAccountLabel, kind) then
        foundNewOrders=true
        newCount=newCount+1
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

--- Newest plausible bookingDate in OrderCache (any sub-account).
function newestOrderBookingDate()
  if LocalStorage == nil or type(LocalStorage.OrderCache) ~= 'table' then
    return nil
  end
  local newest=nil
  for _,order in pairs(LocalStorage.OrderCache) do
    if type(order) == 'table'
        and type(order.bookingDate) == 'number'
        and order.bookingDate ~= invalidDate then
      if newest == nil or order.bookingDate > newest then
        newest=order.bookingDate
      end
    end
  end
  return newest
end

--- Cutoff C: max(MoneyMoney since, newest cache booking) minus list safety window.
function incrementalHarvestCutoff(refreshSince, now)
  if type(now) ~= 'number' then
    return nil
  end
  local base=nil
  if type(refreshSince) == 'number' and refreshSince > 0 then
    base=refreshSince
  end
  local newest=newestOrderBookingDate()
  if type(newest) == 'number' and (base == nil or newest > base) then
    base=newest
  end
  if base == nil then
    return nil
  end
  return base - const.incrementalListSafetySec
end

function registeredRefundCents(order)
  local total=0
  forEachRefundLeaf(order, function(_, _, amount)
    if type(amount) == 'number' and amount > 0 then
      total=total + amount
    end
  end)
  return total
end

--- True when return goods are fully covered by registered refund leaves.
function orderRefundFullySettled(order)
  if not orderHasReturnActivity(order) then
    return false
  end
  local returned=effectiveReturnedCents(order)
  if returned <= 0 then
    return false
  end
  return registeredRefundCents(order) >= returned
end

function orderBookingInRefundWatchWindow(order, now)
  if type(order) ~= 'table' or type(now) ~= 'number' then
    return false
  end
  if type(order.bookingDate) ~= 'number' or order.bookingDate == invalidDate then
    return false
  end
  return order.bookingDate >= now - const.incrementalRefundWatchMaxAgeSec
end

--- Selective refund-watch candidate (90d window; skip unbilled / fully settled).
function orderMayNeedIncrementalRefundWatch(order, now)
  if order == nil or order.unbilledCancel == true then
    return false
  end
  if not orderBookingInRefundWatchWindow(order, now) then
    return false
  end
  if orderRefundFullySettled(order) then
    return false
  end
  return true
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

function addCalendarMonths(unixTime, deltaMonths)
  local parts=os.date('*t', unixTime)
  if parts == nil then
    return nil
  end
  local month=parts.month + deltaMonths
  local year=parts.year
  while month > 12 do
    month=month - 12
    year=year + 1
  end
  while month < 1 do
    month=month + 12
    year=year - 1
  end
  local day=parts.day
  local maxDay=const.daysByMonth[month] or 28
  if month == 2 and (year%4) == 0 and ((year%400) == 0 or (year%100) ~= 0) then
    maxDay=29
  end
  if day > maxDay then
    day=maxDay
  end
  return os.time({year=year, month=month, day=day, hour=parts.hour, min=parts.min, sec=parts.sec})
end

--- Full Business harvest: PAST_12_MONTHS plus older 12-month CUSTOM_RANGE windows.
function enumerateAbaFullHarvestJobs(now)
  now=now or os.time()
  local jobs={{
    reportType=const.abaItemsReportType,
    span=const.abaFullHarvestSpan,
  }}
  local minUnix=os.time({year=2000, month=1, day=1})
  local windowEnd=addCalendarMonths(now, -const.abaCoverageMonths)
  while windowEnd > minUnix do
    local windowStart=addCalendarMonths(windowEnd, -const.abaCoverageMonths)
    if windowStart < minUnix then
      windowStart=minUnix
    end
    local fromParts=unixToAbaDateParts(windowStart)
    local toParts=unixToAbaDateParts(windowEnd)
    if fromParts ~= nil and toParts ~= nil then
      table.insert(jobs, {
        reportType=const.abaItemsReportType,
        span=const.abaCustomRangeSpan,
        fromDate=fromParts,
        toDate=toParts,
        fromUnix=windowStart,
        toUnix=windowEnd,
      })
    end
    if windowStart <= minUnix then
      break
    end
    windowEnd=windowStart
  end
  return jobs
end

function completeAbaFullHarvestBatch(refreshSince)
  if LocalStorage == nil then
    return
  end
  LocalStorage.abaFullHarvestHasMore=false
  LocalStorage.abaFullHarvestJobs=nil
  LocalStorage.abaFullHarvestJobIndex=nil
  LocalStorage.abaFullHarvestReplayRequired=nil
  clearAbaRollupHarvestIncomplete()
  markAbaFullHarvestCompleteForRefresh(refreshSince or LocalStorage.abaFullHarvestHarvestSince)
end

function ensureAbaRollupPaginationUpgrade()
  if LocalStorage == nil then
    return
  end
  if LocalStorage.abaRollupPaginationVersion == const.abaRollupPaginationVersion then
    return
  end
  print("ABA rollup pagination upgrade: restart full harvest batch from PAST_12_MONTHS")
  clearAbaFullHarvestBatch()
  LocalStorage.abaRollupPaginationVersion=const.abaRollupPaginationVersion
  LocalStorage.abaFullHarvestReplayRequired=true
  LocalStorage.abaFullHarvestCompleteKey=nil
end

function abaFullHarvestCompleteKey(refreshSince)
  return tostring(refreshSince)..':'..tostring(const.abaRollupPaginationVersion)
end

function isAbaFullHarvestCompleteForRefresh(refreshSince)
  if LocalStorage == nil or type(refreshSince) ~= 'number' then
    return false
  end
  return LocalStorage.abaFullHarvestCompleteKey == abaFullHarvestCompleteKey(refreshSince)
end

function markAbaFullHarvestCompleteForRefresh(refreshSince)
  if LocalStorage == nil or type(refreshSince) ~= 'number' then
    return
  end
  LocalStorage.abaFullHarvestCompleteKey=abaFullHarvestCompleteKey(refreshSince)
end

function clearAbaFullHarvestReplayIfComplete()
  if LocalStorage == nil then
    return
  end
  if LocalStorage.abaFullHarvestReplayRequired
      and not abaFullHarvestBatchHasMore()
      and type(LocalStorage.abaFullHarvestJobs) ~= 'table' then
    LocalStorage.abaFullHarvestReplayRequired=nil
    clearAbaRollupHarvestIncomplete()
    markAbaFullHarvestCompleteForRefresh(LocalStorage.abaFullHarvestHarvestSince)
    print("ABA full harvest replay complete, business orders in cache=", countBusinessOrdersInCache())
  end
end

function abaFullHarvestBatchHasMore()
  return LocalStorage ~= nil and LocalStorage.abaFullHarvestHasMore == true
end

function abaHarvestStillOpen()
  return abaFullHarvestBatchHasMore() or isAbaRollupHarvestIncomplete()
end

function isFullAccountHarvestComplete()
  return isSubAccountScanComplete() and not abaHarvestStillOpen()
end

function countBusinessOrdersWhere(predicate, now)
  local cache=LocalStorage and LocalStorage.OrderCache
  if type(cache) ~= 'table' then
    return 0
  end
  local businessAccount=subAccountNumberForKind('business')
  local count=0
  for _,order in pairs(cache) do
    if type(order) == 'table' then
      if order.subAccountKind == 'business' and predicate(order, now, businessAccount) then
        count=count+1
      end
    end
  end
  return count
end

function countBusinessOrdersInCache()
  return countBusinessOrdersWhere(function()
    return true
  end)
end

function countEmitReadyBusinessOrdersInCache(now)
  if type(now) ~= 'number' then
    return 0
  end
  return countBusinessOrdersWhere(function(order, refreshNow, accountNumber)
    return orderDetailsCompleteForEmit(order, refreshNow, accountNumber)
  end, now)
end

--- True when the persisted job list is corrupt (PAST_12_MONTHS missing as first job).
function abaFullHarvestBatchCorrupt()
  local jobs=LocalStorage and LocalStorage.abaFullHarvestJobs
  if type(jobs) ~= 'table' or #jobs == 0 then
    return false
  end
  local firstJob=jobs[1]
  return type(firstJob) ~= 'table' or firstJob.span ~= const.abaFullHarvestSpan
end

function markAbaRollupHarvestIncomplete(reason)
  if LocalStorage == nil then
    return
  end
  LocalStorage.abaRollupHarvestIncomplete=reason or true
end

function isAbaRollupHarvestIncomplete()
  return LocalStorage ~= nil and LocalStorage.abaRollupHarvestIncomplete ~= nil
end

function shouldRestartAbaFullHarvestBatch(refreshSince, now)
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return false
  end
  if isAbaFullHarvestCompleteForRefresh(refreshSince) then
    return false
  end
  if abaFullHarvestBatchCorrupt() then
    return true
  end
  if LocalStorage ~= nil and LocalStorage.abaFullHarvestReplayRequired then
    return false
  end
  local idx=LocalStorage and LocalStorage.abaFullHarvestJobIndex
  if type(idx) ~= 'number' or idx <= 1 then
    return false
  end
  -- Stale persisted index without any business orders harvested (e.g. jumped past PAST_12_MONTHS).
  return countBusinessOrdersInCache() == 0
end

function initAbaFullHarvestBatch(refreshSince, now)
  LocalStorage.abaFullHarvestHarvestSince=refreshSince
  LocalStorage.abaFullHarvestJobs=enumerateAbaFullHarvestJobs(now)
  LocalStorage.abaFullHarvestJobIndex=1
end

function beginAbaFullHarvestBatch(refreshSince, now)
  clearAbaFullHarvestBatch()
  initAbaFullHarvestBatch(refreshSince, now)
end

function restartAbaFullHarvestBatch(refreshSince, now)
  print("ABA full harvest batch reset: retry from PAST_12_MONTHS")
  beginAbaFullHarvestBatch(refreshSince, now)
end

function ensureAbaFullHarvestBatch(refreshSince, now)
  if LocalStorage == nil then
    return
  end
  ensureAbaRollupPaginationUpgrade()
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) and not abaHarvestStillOpen() then
    clearAbaFullHarvestBatch()
    return
  end
  if abaHarvestStillOpen()
      and type(LocalStorage.abaFullHarvestJobs) == 'table'
      and type(LocalStorage.abaFullHarvestHarvestSince) == 'number' then
    return
  end
  if type(LocalStorage.abaFullHarvestHarvestSince) ~= 'number'
      or LocalStorage.abaFullHarvestHarvestSince ~= refreshSince then
    beginAbaFullHarvestBatch(refreshSince, now)
    return
  end
  if isAbaFullHarvestCompleteForRefresh(refreshSince) then
    LocalStorage.abaFullHarvestHasMore=false
    return
  end
  if shouldRestartAbaFullHarvestBatch(refreshSince, now) then
    restartAbaFullHarvestBatch(refreshSince, now)
    return
  end
  if type(LocalStorage.abaFullHarvestJobs) ~= 'table' then
    initAbaFullHarvestBatch(refreshSince, now)
  end
end

function takeAbaFullHarvestJobBatch(refreshSince, now)
  ensureAbaFullHarvestBatch(refreshSince, now)
  local all=LocalStorage.abaFullHarvestJobs
  if type(all) ~= 'table' or #all == 0 then
    LocalStorage.abaFullHarvestHasMore=false
    return {}
  end
  local idx=LocalStorage.abaFullHarvestJobIndex or 1
  local batch={}
  local limit=const.abaFullHarvestJobsPerRefresh
  for i=idx, math.min(idx+limit-1, #all) do
    batch[#batch+1]=all[i]
  end
  LocalStorage.abaFullHarvestJobIndex=idx+#batch
  LocalStorage.abaFullHarvestHasMore=LocalStorage.abaFullHarvestJobIndex <= #all
  if not LocalStorage.abaFullHarvestHasMore then
    LocalStorage.abaFullHarvestJobs=nil
    LocalStorage.abaFullHarvestJobIndex=nil
  end
  if #batch > 0 and LocalStorage.abaFullHarvestHasMore then
    MM.printStatus("Amazon Business: Berichte werden stapelweise geladen (Fortsetzung beim nächsten Abruf)")
  end
  clearAbaFullHarvestReplayIfComplete()
  return batch
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

function buildAbaRollupTablePostBody(reportType, span, fromParts, toParts, pageMarker)
  pageMarker=pageMarker or 0
  local body='{"reportType":'..jsonQuote(reportType)
    ..',"reportId":"","dateSpanSelection":'..jsonQuote(span)
  if type(fromParts) == 'table' and type(toParts) == 'table' then
    body=body..',"fromDate":'..abaDatePartsJson(fromParts)
      ..',"toDate":'..abaDatePartsJson(toParts)
  end
  return body
    ..',"groupColumn":"obfCustGroupId","pageMarker":'..tostring(pageMarker)..',"reportName":""'
    ..',"columns":[{"text":"Bestellnummer","value":"ordId","visible":true,"frozen":false}]'
    ..',"groups":[],"localFilters":[],"tableFilters":[],"globalFilters":[],"pageSize":'
    ..tostring(const.abaRollupPageSize)..'}'
end

function effectiveScanFiltersMonths(refreshSince, now)
  local configured=tonumber(config.scanFiltersMonths)
  if not isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return configured
  end
  local cutoff=incrementalHarvestCutoff(refreshSince, now)
  local since=refreshSince
  if type(cutoff) == 'number' then
    since=cutoff
  end
  local days=math.ceil((now - since) / const.daySeconds)
  local months=math.max(1, math.ceil(days / 31))
  if configured == nil or configured <= 0 then
    return months
  end
  return math.min(configured, months)
end

function hasMoreOrderListFiltersToHarvest(subAccountLabel, refreshSince, now)
  now=now or os.time()
  if isOrderListHarvestIncomplete(subAccountLabel) then
    return true
  end
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  local offered=offeredOrderFiltersForSubAccount(subAccountLabel)
  if offered ~= nil then
    for val, _ in pairs(offered) do
      if not isRecentOrderFilter(val)
          and shouldHarvestOrderFilter(val, orderFilterCache, 0, refreshSince, now) then
        return true
      end
    end
    return false
  end
  for _,item in ipairs(enumerateYourOrdersGetFilters(refreshSince, now)) do
    if not isRecentOrderFilter(item.val)
        and shouldHarvestOrderFilter(item.val, orderFilterCache, 0, refreshSince, now) then
      return true
    end
  end
  return false
end

function hasMoreBusinessOrdersToHarvest(subAccountLabel, refreshSince, now)
  now=now or os.time()
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    return false
  end
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  for _,item in ipairs(enumerateYourOrdersGetFiltersForAbaGap(now)) do
    if shouldHarvestOrderFilter(item.val, orderFilterCache, 0, refreshSince, now) then
      return true
    end
  end
  return false
end

function subAccountHarvestHasMore(label, kind, refreshSince, now)
  if kind == 'business' then
    return isOrderListHarvestIncomplete(label)
      or hasMoreBusinessOrdersToHarvest(label, refreshSince, now)
  end
  return hasMoreOrderListFiltersToHarvest(label, refreshSince, now)
end

function anyOrderListHarvestIncomplete()
  local byAccount=LocalStorage and LocalStorage.orderListHarvestIncompleteByAccount
  if type(byAccount) ~= 'table' then
    return false
  end
  for _, incomplete in pairs(byAccount) do
    if incomplete then
      return true
    end
  end
  return false
end

--- True when the last list scan wall-clock is older than the periodic rescan window.
function listHarvestDueForPeriodicRescan(lastListHarvestAt, now)
  if type(now) ~= 'number' then
    return true
  end
  if type(lastListHarvestAt) ~= 'number' or lastListHarvestAt <= 0 then
    return true
  end
  return now - lastListHarvestAt >= const.incrementalListMinRescanSec
end

--- True when MoneyMoney since moved past the last scan watermark by more than the list safety window.
function listHarvestStaleVersusRefreshSince(refreshSince, lastHarvestSince)
  return type(refreshSince) == 'number'
      and type(lastHarvestSince) == 'number'
      and refreshSince - lastHarvestSince > const.incrementalListSafetySec
end

--- True when incremental refresh still needs order-list / ABA harvest (not details-only).
function incrementalListHarvestNeeded(refreshSince, now)
  if anyOrderListHarvestIncomplete() or abaHarvestStillOpen() then
    return true
  end
  local lastListAt=LocalStorage and LocalStorage.lastListHarvestAt
  if listHarvestDueForPeriodicRescan(lastListAt, now) then
    return true
  end
  local lastHarvestSince=LocalStorage and LocalStorage.lastHarvestSince
  return listHarvestStaleVersusRefreshSince(refreshSince, lastHarvestSince)
end

function shouldRunAccountHarvest(refreshSince, now)
  if config.noRefresh then
    return false
  end
  if isAccountSetupSession() then
    return false
  end
  if isPendingInitialSync() and not isInitialSyncHarvestDone() then
    return true
  end
  if abaHarvestStillOpen() then
    return true
  end
  if isPendingInitialSync() then
    return false
  end
  -- Details-only wins over a fresh login when the last list scan is still warm.
  if isIncrementalMoneyMoneyRefresh(refreshSince, now)
      and not incrementalListHarvestNeeded(refreshSince, now) then
    print("skip incremental list harvest (details-only; last list scan still fresh)")
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

function logHarvestMode(refreshSince, now, incrementalMsg, fullMsg)
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    print(incrementalMsg)
    return
  end
  print(fullMsg)
end

function logMoneyMoneyRefreshMode(refreshSince, now)
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    local cutoff=incrementalHarvestCutoff(refreshSince, now)
    if type(cutoff) == 'number' then
      print("incremental refresh since "..formatAbaDateLabel(refreshSince)
        .." (list cutoff "..formatAbaDateLabel(cutoff)..")")
      return
    end
  end
  logHarvestMode(refreshSince, now,
    "incremental refresh since "..formatAbaDateLabel(refreshSince),
    "full refresh: harvest all order history (empty cache, since=0, or since > 366 days)")
end

function logAbaHarvestMode(refreshSince, now)
  logHarvestMode(refreshSince, now,
    "Business ABA harvest: CUSTOM_RANGE since "..formatAbaDateLabel(refreshSince),
    "Business ABA harvest: "..const.abaFullHarvestSpan.." (max preset window, no overlapping spans)")
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

function isAbaRollupTableJson(content)
  if type(content) ~= 'string' or content == '' then
    return false
  end
  if isAbaHtmlDocument(content) then
    return false
  end
  return string.find(content, "rollupTableView", 1, true) ~= nil
    or string.find(content, '"rollupTable"', 1, true) ~= nil
end

--- Amazon rollupTable POST uses CUSTOM_RANGE in the JSON body but PAST_12_MONTHS in the URL
--- (live ABA UI pattern; CUSTOM_RANGE in both places breaks older date windows).
function abaRollupTableQuerySpan(span)
  if span == const.abaCustomRangeSpan then
    return const.abaFullHarvestSpan
  end
  return span
end

function parseAbaRollupTableNextPageMarker(raw)
  if type(raw) ~= 'string' or raw == '' then
    return nil
  end
  local nextMarker=string.match(raw, '"nextPageMarker"%s*:%s*(%-?%d+)')
  if nextMarker == nil then
    return nil
  end
  return tonumber(nextMarker)
end

function fetchAbaRollupTablePage(reportType, span, csrf, referer, fromParts, toParts, pageMarker)
  local postBody=buildAbaRollupTablePostBody(reportType, span, fromParts, toParts, pageMarker)
  local url=buildAbaAjaxUrl(const.abaRollupTablePath, reportType, abaRollupTableQuerySpan(span))
  return fetchAbaAjaxContent(url, csrf, referer, postBody)
end

--- @return 'ok' | 'fatal' | 'incomplete'
function classifyAbaRollupPageContent(content, pageNum)
  local invalid=content == nil
    or isAmazonSignInPageHtml(content)
    or isAbaHtmlDocument(content)
  if not invalid then
    return 'ok'
  end
  return pageNum == 1 and 'fatal' or 'incomplete'
end

function countUniqueOrdersInAbaRollupContent(content, seenOrders)
  local pageOrders=0
  for orderCode in content:gmatch(const.regexOrderCodeNew) do
    if isPlausibleAmazonOrderCode(orderCode) and not seenOrders[orderCode] then
      seenOrders[orderCode]=true
      pageOrders=pageOrders+1
    end
  end
  return pageOrders
end

function logAbaRollupPageFailure(logPrefix, pageNum, message, err)
  local suffix=err ~= nil and (' '..tostring(err)) or ''
  if pageNum == 1 then
    print(logPrefix, message..suffix)
    return
  end
  print(logPrefix, "rollupTable page", pageNum, message..suffix)
end

function abaRollupMessageForPage(pageNum, fullMessage, shortMessage)
  return pageNum == 1 and fullMessage or shortMessage
end

function abaRollupPageFailureMessage(content, pageNum)
  if content == nil then
    return abaRollupMessageForPage(pageNum, "rollupTable failed:", "failed:")
  end
  if isAmazonSignInPageHtml(content) then
    return abaRollupMessageForPage(pageNum, "rollupTable redirected to sign-in", "redirected to sign-in")
  end
  return abaRollupMessageForPage(pageNum, "rollupTable returned HTML error page", "returned HTML error page")
end

function logAbaRollupPageProblem(logPrefix, pageNum, content, err)
  logAbaRollupPageFailure(logPrefix, pageNum, abaRollupPageFailureMessage(content, pageNum), err)
end

function logAbaRollupHarvestSummary(logPrefix, pageNum, totalOrders, truncatedByLimit)
  if truncatedByLimit then
    print(logPrefix, "rollupTable truncated at page limit,", totalOrders, "unique orders (incomplete)")
    return
  end
  if pageNum > 1 then
    print(logPrefix, "rollupTable paginated", pageNum, "pages,", totalOrders, "unique orders")
    return
  end
  print(logPrefix, "rollupTable orders found,", totalOrders, "unique orders")
end

function finalizeAbaRollupTableResult(logPrefix, span, combined, totalOrders, pageNum, paginationFailed, truncatedByLimit)
  if paginationFailed then
    markAbaRollupHarvestIncomplete("rollupTable pagination failed")
    print(logPrefix, "rollupTable pagination incomplete, discarding partial result")
    return nil
  end
  if truncatedByLimit then
    markAbaRollupHarvestIncomplete("rollupTable page limit")
    if totalOrders < 1 then
      return nil
    end
  end
  if totalOrders < 1 then
    if span == const.abaCustomRangeSpan then
      print(logPrefix, "rollupTable empty order list")
      return combined or '{"rollupTableView":[]}'
    end
    print(logPrefix, "rollupTable no orders in response")
    return nil
  end
  logAbaRollupHarvestSummary(logPrefix, pageNum, totalOrders, truncatedByLimit)
  return combined
end

function fetchAbaRollupTable(reportType, span, csrf, referer, logPrefix, fromParts, toParts)
  -- MoneyMoney aborts the whole refresh on HTTP 400. ABA rollupTable rejects GET
  -- (Bad Request); the UI always POSTs JSON. scheduler GET with CUSTOM_RANGE also
  -- returns 400 — never fall back to it for custom date windows.
  print(logPrefix, "try rollupTable POST")
  local combined=nil
  local seenOrders={}
  local totalOrders=0
  local pageMarker=0
  local pageNum=0
  local paginationFailed=false
  local truncatedByLimit=false
  while pageNum < const.abaRollupMaxPages do
    pageNum=pageNum+1
    local content, err=fetchAbaRollupTablePage(
      reportType, span, csrf, referer, fromParts, toParts, pageMarker)
    local pageKind=classifyAbaRollupPageContent(content, pageNum)
    if pageKind ~= 'ok' then
      logAbaRollupPageProblem(logPrefix, pageNum, content, err)
      if pageKind == 'fatal' then
        return nil
      end
      paginationFailed=true
      break
    end
    local pageOrders=countUniqueOrdersInAbaRollupContent(content, seenOrders)
    totalOrders=totalOrders+pageOrders
    if pageOrders > 0 then
      combined=combined and (combined..content) or content
    elseif pageNum == 1 then
      if span == const.abaCustomRangeSpan and isAbaRollupTableJson(content) then
        print(logPrefix, "rollupTable empty order list")
        return content
      end
      print(logPrefix, "rollupTable no orders in response")
      return nil
    end
    local nextMarker=parseAbaRollupTableNextPageMarker(content)
    if nextMarker == nil or nextMarker == 0 or nextMarker == pageMarker then
      break
    end
    if pageNum >= const.abaRollupMaxPages then
      truncatedByLimit=true
      print(logPrefix, "rollupTable pagination limit reached at", const.abaRollupMaxPages, "pages")
      break
    end
    pageMarker=nextMarker
    print(logPrefix, "rollupTable page", pageNum, "orders=", pageOrders, "nextPageMarker=", nextMarker)
  end
  return finalizeAbaRollupTableResult(
    logPrefix, span, combined, totalOrders, pageNum, paginationFailed, truncatedByLimit)
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
  if span == const.abaCustomRangeSpan then
    print(logPrefix, "scheduler skipped for CUSTOM_RANGE (Amazon returns HTTP 400)")
    return nil
  end
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
  if span == const.abaCustomRangeSpan then
    print(logPrefix, "CUSTOM_RANGE harvest finished with 0 orders (no scheduler fallback)")
    return nil
  end
  return scheduleAndDownloadAbaReport(reportType, span, csrf, referer, logPrefix)
end

function isAmazonSignInPageHtml(raw)
  if type(raw) ~= 'string' or raw == '' then
    return false
  end
  local page=parseAmazonHtml(raw)
  return isAmazonMfaPage(page) or isAmazonPasswordSignInPage(page)
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
  -- Require '/' immediately after the host so www.amazon.de.evil… cannot match.
  for abs in raw:gmatch('"(https://www%.amazon%.de/[^"]*b2b/aba/[^"]+download[^"]*)"') do
    local ok, validated=pcall(absoluteAmazonUrl, abs)
    if ok and not seen[validated] and isAbaDownloadUrl(validated) then
      seen[validated]=true
      table.insert(urls, validated)
    end
  end
  return urls
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

function abaPrimaryReportJob(refreshSince, now, reportType)
  now=now or os.time()
  reportType=reportType or const.abaItemsReportType
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    local fromUnix=refreshSince
    local cutoff=incrementalHarvestCutoff(refreshSince, now)
    if type(cutoff) == 'number' then
      fromUnix=cutoff
    end
    local fromParts=unixToAbaDateParts(fromUnix)
    local toParts=unixToAbaDateParts(now)
    if fromParts == nil or toParts == nil then
      return nil
    end
    return {
      reportType=reportType,
      span=const.abaCustomRangeSpan,
      fromDate=fromParts,
      toDate=toParts,
      fromUnix=fromUnix,
      toUnix=now,
    }
  end
  return {
    reportType=reportType,
    span=const.abaFullHarvestSpan,
  }
end

--- ABA jobs: incremental CUSTOM_RANGE; full harvest adds older 12-month windows.
function enumerateAbaReportJobs(refreshSince, now)
  now=now or os.time()
  if isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    local job=abaPrimaryReportJob(refreshSince, now, const.abaItemsReportType)
    if job == nil then
      return {}
    end
    return { job }
  end
  return takeAbaFullHarvestJobBatch(refreshSince, now)
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
    return 0, false
  end
  MM.printStatus('Amazon Business Bericht: '..job.reportType..' / '..abaJobStatusLabel(job))
  local logPrefix="ABA report "..job.reportType.." "..job.span
  local pageHtml=type(landing) == 'string' and landing or ''
  local content=tryHarvestAbaCsvFromHtmlPage(
    pageHtml, job.reportType, job.span, landing, logPrefix, job.fromDate, job.toDate)
  if content == nil then
    print("ABA no orders for", job.reportType, job.span)
    return 0, false
  end
  local foundOrders, _, n=mergeOrdersFromRawText(content, orderCache, subAccountLabel, kind)
  if n > 0 then
    print("ABA harvest", job.reportType, job.span, "new=", n)
  end
  return n, foundOrders
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
  local reportsUrl=buildAbaReportUrl(const.abaItemsReportType, const.abaFullHarvestSpan, true)
  local reportsPage=fetchAbaGetContent(reportsUrl)
  if type(reportsPage) == 'string' and reportsPage ~= ''
      and not isAmazonSignInPageHtml(reportsPage)
      and extractAbaCsrfToken(reportsPage) ~= nil then
    landing=reportsPage
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
  local totalNew=0
  local foundOrders=false
  local emptyCustomRangeStreak=0
  for _, job in ipairs(enumerateAbaReportJobs(refreshSince, now)) do
    local n, found=harvestAbaReportJob(job, landing, orderCache, subAccountLabel, kind)
    totalNew=totalNew+n
    if found then
      foundOrders=true
    end
    if job.span == const.abaCustomRangeSpan and not found then
      emptyCustomRangeStreak=emptyCustomRangeStreak+1
      if emptyCustomRangeStreak >= const.abaEmptyCustomRangeHorizon then
        print("ABA CUSTOM_RANGE empty horizon: skip remaining older windows")
        completeAbaFullHarvestBatch(refreshSince)
        break
      end
    else
      emptyCustomRangeStreak=0
    end
  end
  if totalNew == 0 then
    if foundOrders then
      print("ABA harvest: 0 new order ids (already in OrderCache)")
    else
      MM.printStatus("Amazon Business: keine Bestellnummern in ABA-Berichten gefunden")
    end
  else
    print("ABA harvest total new=", totalNew)
  end
  return totalNew, nil
end

--- @function collectBusinessSpaOrders
-- Business: ABA items_report (12-month windows); full harvest also GET year filters when available.
-- ABA session failure aborts (no Gap-GET pretending the last 12 months were covered).
-- @return newCount, errString
function collectBusinessSpaOrders(subAccountLabel, kind, refreshSince)
  print("Business SPA harvest: ABA items_report windows; GET years when order list is scrapable")
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
    if tryEnterOrderListGet(buildOrderHistoryUrl('css')) then
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
  if tryEnterOrderListGet(buildOrderHistoryUrl('css')) then
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
  return connectShopForm(form)
end

--- @function buildOrderHistoryUrl
-- kind: "css" | "yourOrders" | "classic". Optional timeFilter/orderFilter.
function buildOrderHistoryUrl(kind, filterVal)
  if kind == 'css' then
    local url=baseurl..const.cssOrderHistoryPath..'?ref_='..const.cssOrderHistoryRef
    if type(filterVal) == 'string' and filterVal ~= '' then
      url=url..'&timeFilter='..MM.urlencode(filterVal)
    end
    return url
  end
  if kind == 'yourOrders' then
    if type(filterVal) ~= 'string' or filterVal == '' then
      return nil
    end
    return baseurl..const.yourOrdersTimeFilterPath
      ..'?timeFilter='..MM.urlencode(filterVal)
      ..'&ref_='..const.yourOrdersTimeFilterRef
  end
  if kind == 'classic' then
    if type(filterVal) ~= 'string' or filterVal == '' then
      return nil
    end
    return baseurl..const.orderListLink
      ..'&orderFilter='..MM.urlencode(filterVal)
  end
  return nil
end

function recentYourOrdersGetFilters(scanMonths)
  local list={
    {val='last30', label='den letzten 30 Tagen'},
  }
  local monthsLimit=tonumber(scanMonths)
  if monthsLimit == nil or monthsLimit <= 0 or monthsLimit >= 3 then
    table.insert(list, {val=const.recentMonthsFilter, label='den letzten 3 Monaten'})
  end
  return list
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
  local list=recentYourOrdersGetFilters(scanMonths)
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
    buildOrderHistoryUrl('css', filterVal),
    buildOrderHistoryUrl('yourOrders', filterVal),
    buildOrderHistoryUrl('classic', filterVal),
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

function activeAmazonSubAccountKind()
  if sessionMatchesSubAccountKind('business') then
    return 'business'
  end
  if sessionMatchesSubAccountKind('personal') then
    return 'personal'
  end
  return nil
end

function businessGetHarvestBlockedBySpaShell()
  local cssPage=connectShop('GET', buildOrderHistoryUrl('css', 'last30'))
  if cssPage ~= nil then
    local resolved=resolveAkamaiInterstitial(cssPage)
    if resolved ~= nil and orderListPageReady(resolved) then
      return false
    end
  end
  local probe=loadYourOrdersFilterPage('last30')
  return probe ~= nil and isAmazonBusinessOrdersSpa(probe) and not orderListPageReady(probe)
end

--- @function runOrderFilterHarvest
-- Shared status + optional page load + readiness check + scan.
-- opts.loadPage(filterVal) → html | nil; opts.requireReady marks incomplete filters.
function runOrderFilterHarvest(orderFilterVal, statusLabel, orderFilterCache, subAccountLabel, kind, opts)
  opts=type(opts) == 'table' and opts or {}
  MM.printStatus('Amazon Bestellübersicht: "'..statusLabel..'"')
  if type(opts.loadPage) == 'function' then
    local page=opts.loadPage(orderFilterVal)
    if page == nil then
      print(opts.failLog or "filter load failed", orderFilterVal)
      setOrderListHarvestIncomplete(subAccountLabel, true)
      return 0
    end
    html=page
  end
  if opts.requireReady and not orderListPageReady(html) then
    print(opts.notReadyLog or "filter not ready", orderFilterVal)
    if not opts.skipIncompleteOnNotReady then
      setOrderListHarvestIncomplete(subAccountLabel, true)
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

--- Mark GET year filters done after SSR years stay unready (fullHarvest only).
function markGetYearFiltersAbandoned(orderFilterCache, filters)
  if type(filters) ~= 'table' or type(orderFilterCache) ~= 'table' then
    return
  end
  for _, item in ipairs(filters) do
    local val=type(item) == 'table' and item.val or nil
    if type(val) == 'string' and val ~= '' then
      markOrderFilterCacheIfComplete(orderFilterCache, val, false)
    end
  end
end

--- After SSR year filters stay unready, stop sticky incomplete harvest loops.
function abandonUnreadyGetYearFilters(subAccountLabel, orderFilterCache, filters)
  markGetYearFiltersAbandoned(orderFilterCache, filters)
  setOrderListHarvestIncomplete(subAccountLabel, false)
end

--- @function collectOrdersViaYourOrdersGet
-- Harvest orders with GET timeFilter URLs. Used when Business lands on the SPA
-- shell: POST /ab/your-orders/orderHistory returns Forbidden in MoneyMoney and
-- aborts the whole refresh.
-- last30 is often SPA-only; year-YYYY pages can still have scrapable order cards.
function collectOrdersViaYourOrdersGet(subAccountLabel, kind, refreshSince, opts)
  opts=type(opts) == 'table' and opts or {}
  print("SPA/Business shell: harvest via GET timeFilter (css order-history first)")
  ensureOrderCache()
  local now=os.time()
  local filters
  if opts.abaGapOnly then
    print("GET harvest: year filters outside ABA window only")
    filters=enumerateYourOrdersGetFiltersForAbaGap(now)
  else
    filters=enumerateYourOrdersGetFilters(refreshSince, now)
  end
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  local newCount=0
  local readyCount=0
  local unreadyStreak=0
  local abandonedUnready=false
  local getHarvestOpts={
    loadPage=loadYourOrdersFilterPage,
    requireReady=true,
    skipIncompleteOnNotReady=opts.fullHarvest == true,
    failLog="GET timeFilter failed",
    notReadyLog="GET timeFilter not ready",
  }
  for i, item in ipairs(filters) do
    if shouldHarvestOrderFilter(item.val, orderFilterCache, newCount, refreshSince, now) then
      newCount=newCount
        + runOrderFilterHarvest(item.val, item.label, orderFilterCache, subAccountLabel, kind, getHarvestOpts)
      if orderListPageReady(html) then
        readyCount=readyCount+1
        unreadyStreak=0
      else
        unreadyStreak=unreadyStreak+1
        if unreadyStreak >= const.getFilterUnreadyHorizon then
          print("GET timeFilter unready horizon; skip remaining year filters")
          abandonedUnready=true
          break
        end
      end
    else
      unreadyStreak=0
    end
  end
  if opts.fullHarvest then
    if readyCount == 0 then
      MM.printStatus("Amazon Business: Bestellübersicht online nicht verfügbar – ältere Bestellungen nur über Business Analytics")
      -- No ready year: abandon SSR years and clear sticky incomplete from this path.
      abandonUnreadyGetYearFilters(subAccountLabel, orderFilterCache, filters)
    elseif abandonedUnready then
      -- Keep incomplete if a ready year set it (e.g. pagination); only mark remaining filters done.
      markGetYearFiltersAbandoned(orderFilterCache, filters)
    end
  end
  return newCount
end

--- @function collectOrdersFromOrderList
-- Scrapes order-history filters for the currently active Amazon sub-account.
-- @return newCount, errString
function collectOrdersFromOrderList(subAccountLabel, kind, refreshSince)
  setOrderListHarvestIncomplete(subAccountLabel, false)
  local now=os.time()
  -- Incremental Business: skip SPA order-history probes; ABA uses the cutoff window.
  if kind == 'business' and isIncrementalMoneyMoneyRefresh(refreshSince, now) then
    print("Business incremental: ABA cutoff harvest (skip order-list SPA probes)")
    return collectBusinessSpaOrders(subAccountLabel, kind, refreshSince)
  end
  enterOrderList()
  if html == nil then
    print("collectOrdersFromOrderList: no order list html for", tostring(subAccountLabel))
    setOrderListHarvestIncomplete(subAccountLabel, true)
    return 0, nil
  end
  if isAmazonBusinessOrdersSpa(html) and not orderListPageReady(html) then
    return collectBusinessSpaOrders(subAccountLabel, kind, refreshSince)
  end
  local orderFilterCache=filterCacheForSubAccount(subAccountLabel)
  local orderFilterSelect=html:xpath(const.xpathOrderMonthSelect):children()
  local newCount=0
  local scannedFilters={}
  local scanMonths=effectiveScanFiltersMonths(refreshSince, now)
  if scanMonths ~= nil and scanMonths > 0 then
    print("scanFiltersMonths=", scanMonths)
  end

  local offeredVals={}
  local selectedFilterVal=getSelectedOrderFilter(html)
  if selectedFilterVal ~= '' then
    offeredVals[#offeredVals+1]=selectedFilterVal
  end
  orderFilterSelect:each(function(_, element)
    local val=element:attr('value')
    if type(val) == 'string' and val ~= '' then
      offeredVals[#offeredVals+1]=val
    end
  end)
  rememberOfferedOrderFilters(subAccountLabel, offeredVals)

  local function harvestFilter(orderFilterVal, statusLabel, submitFilter)
    if scannedFilters[orderFilterVal]
        or not shouldHarvestOrderFilter(orderFilterVal, orderFilterCache, newCount, refreshSince, now) then
      return
    end
    scannedFilters[orderFilterVal]=true
    local n=runOrderFilterHarvest(orderFilterVal, statusLabel, orderFilterCache, subAccountLabel, kind, {
      loadPage=submitFilter and function(val)
        return submitOrderTimeFilter(html, val)
      end or nil,
      failLog="skip filter (submit failed or no form)",
    })
    newCount=newCount+n
  end

  if selectedFilterVal ~= '' then
    harvestFilter(selectedFilterVal, getSelectedOrderFilterLabel(html, selectedFilterVal), false)
  end

  orderFilterSelect:each(function(index,element)
    harvestFilter(element:attr('value'), element:text(), true)
    return true
  end)

  return newCount, nil
end

function findSubAccountByKind(options, kind)
  for _,opt in ipairs(options) do
    if opt.kind == kind then
      return opt
    end
  end
  return nil
end

--- Switch Amazon web session to the given sub-account kind before order-detail fetches.
--- @return nil on success, error string on failure
function ensureAmazonSubAccountSession(kind)
  if type(kind) ~= 'string' or kind == '' then
    return nil
  end
  if sessionMatchesSubAccountKind(kind) then
    return nil
  end
  local page=openAccountSwitcherEmbed()
  if page == nil then
    return "Kontenwechsel nicht verfügbar"
  end
  local options=parseAccountSwitcher(page)
  local match=findSubAccountByKind(options, kind)
  if match == nil then
    return "Unterkonto nicht im Switcher: "..subAccountKindDisplayLabel(kind)
  end
  local result=switchAmazonSubAccount(match)
  if type(result) == 'table' and result.needsMfa then
    return "2FA beim Kontenwechsel erforderlich – bitte abmelden und erneut anmelden"
  end
  if type(result) == 'table' and result.error then
    return "Kontowechsel fehlgeschlagen ("..tostring(match.label).."): "..result.error
  end
  MM.printStatus("Amazon: Unterkonto \""..match.label.."\"")
  return nil
end

function subAccountNumberForKind(kind)
  if type(kind) ~= 'string' or kind == '' then
    return nil
  end
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) == 'table' then
    for _,sub in ipairs(discovered) do
      if type(sub) == 'table' and sub.kind == kind and type(sub.accountNumber) == 'string' and sub.accountNumber ~= '' then
        if isAmazonCustomerId(sub.accountNumber) then
          return moneyMoneyAccountNumberForCustomerId(sub.accountNumber)
        end
        return sub.accountNumber
      end
    end
  end
  return nil
end

function subAccountKindDisplayLabel(kind)
  if kind == 'personal' then
    return const.subAccountListNamePersonal
  end
  if kind == 'business' then
    return const.subAccountListNameBusiness
  end
  if type(kind) == 'string' and kind ~= '' then
    return kind
  end
  return 'Unterkonto'
end

function combinedAccountListLabel()
  return const.combinedAccountListName
end

--- @function isAmazonCustomerId
-- Raw Amazon session customerId (A…), as stored in discovery — not the MM accountNumber.
function isAmazonCustomerId(customerId)
  return type(customerId) == 'string'
    and string.match(customerId, "^A[A-Z0-9]+$") ~= nil
end

--- @function moneyMoneyAccountNumberForCustomerId
-- MoneyMoney accountNumber for a sub-account. Encodes customerId so the raw
-- A… string is not a contiguous substring (Amazon-Kreditkarte host override).
function moneyMoneyAccountNumberForCustomerId(customerId)
  if not isAmazonCustomerId(customerId) then
    error("Amazon: moneyMoneyAccountNumberForCustomerId erwartet eine Amazon-customerId")
  end
  return const.moneyMoneyCustomerIdAccountPrefix..string.sub(customerId, 2)
end

--- @function amazonCustomerIdFromMoneyMoneyAccountNumber
-- Decodes AO.<body> → A<body>; nil if not a current namespaced sub-account number.
function amazonCustomerIdFromMoneyMoneyAccountNumber(accountNumber)
  if type(accountNumber) ~= 'string' then
    return nil
  end
  local prefix=const.moneyMoneyCustomerIdAccountPrefix
  if string.sub(accountNumber, 1, #prefix) ~= prefix then
    return nil
  end
  local body=string.sub(accountNumber, #prefix+1)
  if body == '' or string.match(body, "^[A-Z0-9]+$") == nil then
    return nil
  end
  local customerId="A"..body
  if not isAmazonCustomerId(customerId) then
    return nil
  end
  return customerId
end

--- @function isAmazonCustomerIdAccountNumber
-- MoneyMoney sub-account numbers are encoded customerIds (AO.<ohne führendes A>).
function isAmazonCustomerIdAccountNumber(accountNumber)
  return amazonCustomerIdFromMoneyMoneyAccountNumber(accountNumber) ~= nil
end

function discoveredSubAccountDisplayName(discoveredSub)
  if type(discoveredSub) ~= 'table' then
    return ''
  end
  if discoveredSub.kind == "personal" then
    return trim(type(discoveredSub.customerName) == 'string' and discoveredSub.customerName or '')
  end
  if discoveredSub.kind == "business" then
    return trim(type(discoveredSub.businessName) == 'string' and discoveredSub.businessName or '')
  end
  return ''
end

function isCompleteDiscoveredSubAccount(discoveredSub)
  if type(discoveredSub) ~= 'table' then
    return false
  end
  if discoveredSub.kind ~= "personal" and discoveredSub.kind ~= "business" then
    return false
  end
  if not isAmazonCustomerId(discoveredSub.accountNumber) then
    return false
  end
  return discoveredSubAccountDisplayName(discoveredSub) ~= ''
end

--- @function accountNumberForLog
-- Avoid writing the login email (or full customerId) into MoneyMoney logs.
function accountNumberForLog(accountNumber)
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return "combined"
  end
  local kind=moneyMoneyAccountKind(accountNumber)
  if kind ~= nil then
    return kind
  end
  local customerId=amazonCustomerIdFromMoneyMoneyAccountNumber(accountNumber)
  if customerId ~= nil then
    return "customerId:"..string.sub(customerId, 1, 4).."…"
  end
  if type(accountNumber) == 'string' and accountNumber ~= '' then
    return accountNumber
  end
  return "?"
end

function listAccountDisplayLabel(accountNumber, discoveredSub)
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return combinedAccountListLabel()
  end
  if type(discoveredSub) == 'table' then
    local displayName=discoveredSubAccountDisplayName(discoveredSub)
    if displayName ~= '' then
      return displayName
    end
  end
  local kind=harvestPriorityKindFromAccountNumber(accountNumber)
  if kind ~= nil then
    return subAccountKindDisplayLabel(kind)
  end
  if type(accountNumber) == 'string' and accountNumber ~= '' then
    return accountNumber
  end
  return const.combinedAccountListName
end

function rememberDiscoveredSubAccounts(options)
  LocalStorage.discoveredSubAccounts={}
  if type(options) ~= 'table' then
    return
  end
  for _,opt in ipairs(options) do
    if type(opt) == 'table' and type(opt.kind) == 'string' and opt.kind ~= '' then
      local accountNumber=opt.accountNumber or opt.customerId
      local displayName=opt.kind == "personal" and opt.customerName
        or opt.kind == "business" and opt.businessName
      if type(accountNumber) == 'string' and accountNumber ~= ''
          and type(displayName) == 'string' and displayName ~= '' then
      local entry={
        kind=opt.kind,
        label=opt.label,
        accountType=opt.accountType,
        businessName=opt.businessName,
        customerName=opt.customerName,
        accountNumber=accountNumber,
      }
      if isAmazonCustomerId(accountNumber) then
        entry.customerId=accountNumber
      elseif type(opt.customerId) == 'string' and isAmazonCustomerId(opt.customerId) then
        entry.customerId=opt.customerId
      end
      table.insert(LocalStorage.discoveredSubAccounts, entry)
      end
    end
  end
end

--- @function normalizeAccountEmail
-- Comparable form of an email used as MoneyMoney accountNumber: MoneyMoney and
-- Amazon may differ in case and padding, the mailbox is still the same.
function normalizeAccountEmail(value)
  if type(value) ~= 'string' then
    return ''
  end
  return string.lower(trim(value))
end

--- @function matchesCombinedAccountEmail
-- True when accountNumber addresses the login email of the combined account.
function matchesCombinedAccountEmail(accountNumber)
  local login=normalizeAccountEmail(secUsername)
  if login == '' then
    return false
  end
  return normalizeAccountEmail(accountNumber) == login
end

function isCombinedMoneyMoneyAccount(accountNumber)
  if accountNumber == nil or accountNumber == '' then
    return true
  end
  return matchesCombinedAccountEmail(accountNumber)
end

--- @function isObsoleteMoneyMoneyAccountNumber
-- Alt-Kontonummern vor E-Mail/AO.-Encoding: kein Refresh mehr, nur Neu-Anlage.
-- nil/"" sind kein Obsolete (Combined-Sentinel), sondern isCombinedMoneyMoneyAccount.
-- Bare customerId und AB-<customerId> enthalten die ID als Substring → obsolete.
function isObsoleteMoneyMoneyAccountNumber(accountNumber)
  if type(accountNumber) ~= 'string' or accountNumber == '' then
    return false
  end
  if string.match(accountNumber, "^sub:") then
    return true
  end
  for _,key in ipairs(const.obsoleteMoneyMoneyAccountNumbers) do
    if accountNumber == key then
      return true
    end
  end
  if isAmazonCustomerId(accountNumber) then
    return true
  end
  if string.match(accountNumber, "^AB%-A[A-Z0-9]+$") then
    return true
  end
  return false
end

function assertCurrentMoneyMoneyAccountNumber(accountNumber)
  if isObsoleteMoneyMoneyAccountNumber(accountNumber) then
    error(const.obsoleteAccountRecreateMessage)
  end
end

function moneyMoneyAccountKind(accountNumber)
  if type(accountNumber) ~= 'string' or accountNumber == '' then
    return nil
  end
  local customerId=amazonCustomerIdFromMoneyMoneyAccountNumber(accountNumber)
  if customerId == nil then
    return nil
  end
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) == 'table' then
    for _,sub in ipairs(discovered) do
      if type(sub) == 'table' and sub.accountNumber == customerId
          and (sub.kind == "personal" or sub.kind == "business") then
        return sub.kind
      end
    end
  end
  return nil
end

function orderMatchesMoneyMoneyAccount(order, accountNumber)
  if type(order) ~= 'table' then
    return false
  end
  if isObsoleteMoneyMoneyAccountNumber(accountNumber) then
    return false
  end
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return true
  end
  local wantKind=moneyMoneyAccountKind(accountNumber)
  if wantKind == nil then
    return false
  end
  return order.subAccountKind == wantKind
end

--- Current MoneyMoney accounts always use the mixed ledger (Ausgleich).
function refreshAccountLedgerProfile(_accountNumber)
  return { divisor=-100 }
end

--- @function detailsRescanDelaySec
-- min, jitter for the next details fetch, based on order age.
function detailsRescanDelaySec(age)
  local day=const.daySeconds
  if type(age) ~= 'number' or age < 0 then
    age=0
  end
  if age < 90*day then
    return 7*day, 7*day
  end
  if age < const.abaIncrementalMaxAgeSec then
    return 21*day, 21*day
  end
  return 90*day, 90*day
end

--- @function scheduleNextDetailsDate
-- Next details fetch: recent orders sooner so refunds/returns are seen; old orders stay rare.
-- Positions already in emittedAccounts are not re-emitted; new refund/return leaves still are.
function scheduleNextDetailsDate(order, now)
  if type(order) ~= 'table' then
    return
  end
  if type(now) ~= 'number' then
    now=os.time()
  end
  local booking=order.bookingDate
  if type(booking) ~= 'number' or booking == invalidDate then
    booking=now
  end
  local minSec, jitterSec=detailsRescanDelaySec(now-booking)
  order.detailsDate=now+math.floor(minSec+math.random()*jitterSec)
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

--- Stable list of orders needing details for one MoneyMoney account (avoids double OrderCache scan).
function sortPendingOrdersForDetails(pending)
  if type(pending) ~= 'table' or #pending < 2 then
    return pending
  end
  local oldestFirst=isPendingInitialSync()
  table.sort(pending, function(a, b)
    local orderA=a.order
    local orderB=b.order
    local dateA=(type(orderA) == 'table' and type(orderA.bookingDate) == 'number') and orderA.bookingDate or 0
    local dateB=(type(orderB) == 'table' and type(orderB.bookingDate) == 'number') and orderB.bookingDate or 0
    if oldestFirst then
      return dateA < dateB
    end
    return dateA > dateB
  end)
  return pending
end

function collectOrdersNeedingDetails(predicate)
  local pending={}
  if type(predicate) ~= 'function' then
    error("collectOrdersNeedingDetails requires a predicate")
  end
  if type(LocalStorage) ~= 'table' or type(LocalStorage.OrderCache) ~= 'table' then
    return pending
  end
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    if predicate(order) then
      pending[#pending+1]={orderCode=orderCode, order=order}
    end
  end
  return sortPendingOrdersForDetails(pending)
end

function ordersNeedingDetailsInCache(now)
  return collectOrdersNeedingDetails(function(order)
    return type(order) == 'table'
      and type(order.detailsDate) == 'number'
      and order.detailsDate < now
  end)
end

function ordersNeedingDetailsForAccount(accountNumber, now)
  return collectOrdersNeedingDetails(function(order)
    return orderNeedsDetailsForAccount(order, now, accountNumber)
  end)
end

function clearSubAccountScanState()
  if LocalStorage ~= nil then
    LocalStorage.subAccountScan=nil
  end
end

function shouldPreserveSubAccountScanOnLogin()
  local state=LocalStorage and LocalStorage.subAccountScan
  if type(state) ~= 'table' then
    return false
  end
  if state.phase == 'await_mfa' then
    return true
  end
  return state.phase == 'running' and state.incomplete == true
end

function syncSubAccountScanLoginCounter()
  local state=LocalStorage and LocalStorage.subAccountScan
  if type(state) == 'table' and type(LocalStorage.loginCounter) == 'number' then
    state.loginCounter=LocalStorage.loginCounter
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
  local refreshSince=LocalStorage.refreshSince
  local now=os.time()
  local n, err=collectOrdersFromOrderList(label, kind, refreshSince)
  local hasMore=subAccountHarvestHasMore(label, kind, refreshSince, now)
  return n, err, hasMore
end

function addHarvestedOrders(state, label, kind)
  local n, err, hasMore=harvestSubAccountPlanEntry(label, kind)
  if err ~= nil then
    clearSubAccountScanState()
    return err
  end
  state.totalNew=state.totalNew+(n or 0)
  state.harvestHasMore=hasMore and true or false
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
  if abaHarvestStillOpen() then
    print("sub-account scan done; ABA harvest continues on next refresh")
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
    return switchOtpChallengeFromHtml(html) or moneyMoneyOtpChallenge(
      AMAZON_SWITCH_OTP_TITLE,
      'Bitte den Bestätigungscode für den Amazon-Kontenwechsel eingeben.')
  end
  local want=state.plan[state.index]
  if type(want) ~= 'table' then
    clearSubAccountScanState()
    return "Amazon: Kein Unterkonto nach der Zwei-Faktor-Authentifizierung"
  end
  local nextHtml, err=submitAmazonSwitchOtp(html, otpCode)
  if err ~= nil or nextHtml == nil then
    clearSubAccountScanState()
    return "Amazon 2FA fehlgeschlagen: "..tostring(err or "empty response")
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
  local advance, harvestErr=harvestAndAdvanceSubAccountScan(state, want.label, want.kind)
  if harvestErr ~= nil then
    return harvestErr
  end
  if advance == 'pause' then
    state.incomplete=true
    state.phase='running'
    print("sub-account harvest batch paused after MFA; more orders for", tostring(want.label))
    return nil
  end
  if advance == 'done' then
    completeSubAccountScan(state, false)
    print("sub-account scan done, new orders=", state.totalNew)
    return nil
  end
  state.phase='running'
  return runSubAccountScanLoop()
end

function harvestPriorityKindFromAccountNumber(accountNumber)
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return nil
  end
  return moneyMoneyAccountKind(accountNumber)
end

function reportEmptyEmitIfMisaligned(accountNumber, transactions, now)
  if not isPendingInitialSync() or isAccountSetupSession() then
    return
  end
  if type(transactions) ~= 'table' or #transactions > 0 then
    return
  end
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return
  end
  local wantKind=harvestPriorityKindFromAccountNumber(accountNumber)
  if wantKind == nil or type(now) ~= 'number' then
    return
  end
  local cache=LocalStorage and LocalStorage.OrderCache
  if type(cache) ~= 'table' then
    return
  end
  local hasEmitReady=false
  local hasOtherKind=false
  for _,order in pairs(cache) do
    if type(order) == 'table' then
      if order.subAccountKind == wantKind
          and orderDetailsCompleteForEmit(order, now, accountNumber) then
        hasEmitReady=true
        break
      end
      if type(order.subAccountKind) == 'string'
          and order.subAccountKind ~= ''
          and order.subAccountKind ~= wantKind then
        hasOtherKind=true
      end
    end
  end
  if hasEmitReady then
    return
  end
  if hasOtherKind then
    MM.printStatus("Amazon: Erstimport – "
      ..subAccountKindDisplayLabel(wantKind).." noch nicht abgerufen – bitte erneut aktualisieren")
    return
  end
  local scan=LocalStorage.subAccountScan
  if type(scan) == 'table' and scan.incomplete == true then
    MM.printStatus("Amazon: Erstimport – Abruf für "
      ..subAccountKindDisplayLabel(wantKind).." unvollständig – bitte erneut aktualisieren")
  end
end

function reorderSubAccountPlanByPriority(plan, priorityKind)
  if priorityKind == nil or type(plan) ~= 'table' or #plan < 2 then
    return plan
  end
  local prioritized={}
  local rest={}
  for _,entry in ipairs(plan) do
    if type(entry) == 'table' and entry.kind == priorityKind then
      prioritized[#prioritized+1]=entry
    else
      rest[#rest+1]=entry
    end
  end
  for _,entry in ipairs(rest) do
    prioritized[#prioritized+1]=entry
  end
  return prioritized
end

function beginSubAccountScanPlan(options, priorityKind)
  local plan={}
  for _,opt in ipairs(options) do
    table.insert(plan, {kind=opt.kind, label=opt.label})
  end
  plan=reorderSubAccountPlanByPriority(plan, priorityKind)
  LocalStorage.subAccountScan={
    phase='running',
    plan=plan,
    index=1,
    totalNew=0,
    incomplete=false,
    loginCounter=LocalStorage.loginCounter,
    harvestedPlanThisRefresh={},
  }
end

function isSubAccountPlanEntryDone(entry)
  return type(entry) == 'table' and entry.done == true
end

function firstOpenSubAccountPlanIndex(state)
  if type(state) ~= 'table' or type(state.plan) ~= 'table' then
    return 1
  end
  for i, entry in ipairs(state.plan) do
    if not isSubAccountPlanEntryDone(entry) then
      return i
    end
  end
  return #state.plan + 1
end

function shouldRoundRobinSubAccountBatches()
  return LocalStorage ~= nil and LocalStorage.harvestPriorityKind == nil
end

function nextRoundRobinPlanIndex(state, harvestedThisRefresh)
  if not shouldRoundRobinSubAccountBatches() then
    return nil
  end
  if type(state) ~= 'table' or type(state.plan) ~= 'table' or #state.plan < 2 then
    return nil
  end
  if type(harvestedThisRefresh) ~= 'table' then
    harvestedThisRefresh={}
  end
  local n=#state.plan
  local idx=state.index
  if type(idx) ~= 'number' or idx < 1 then
    idx=1
  end
  for step=1, n-1 do
    local i=((idx - 1 + step) % n) + 1
    if not isSubAccountPlanEntryDone(state.plan[i]) and harvestedThisRefresh[i] ~= true then
      return i
    end
  end
  return nil
end

--- After one harvest batch: continue another sub-account, pause, or finish the plan.
function advanceSubAccountScanAfterBatch(state, harvestedThisRefresh)
  if type(state) ~= 'table' then
    return 'pause'
  end
  if type(harvestedThisRefresh) ~= 'table' then
    harvestedThisRefresh={}
  end
  if type(state.index) == 'number' then
    harvestedThisRefresh[state.index]=true
  end
  if state.harvestHasMore then
    state.incomplete=true
    local nextIndex=nextRoundRobinPlanIndex(state, harvestedThisRefresh)
    if nextIndex == nil then
      state.index=firstOpenSubAccountPlanIndex(state)
      return 'pause'
    end
    state.index=nextIndex
    return 'continue'
  end
  local current=state.plan and state.plan[state.index]
  if type(current) == 'table' then
    current.done=true
  end
  state.index=firstOpenSubAccountPlanIndex(state)
  if type(state.plan) ~= 'table' or state.index > #state.plan then
    return 'done'
  end
  if harvestedThisRefresh[state.index] == true then
    state.incomplete=true
    return 'pause'
  end
  return 'continue'
end

function harvestAndAdvanceSubAccountScan(state, label, kind)
  local harvestErr=addHarvestedOrders(state, label, kind)
  if harvestErr ~= nil then
    return nil, harvestErr
  end
  if type(state.harvestedPlanThisRefresh) ~= 'table' then
    state.harvestedPlanThisRefresh={}
  end
  return advanceSubAccountScanAfterBatch(state, state.harvestedPlanThisRefresh), nil
end

--- @function runSubAccountScanLoop
-- Switches+scrapes remaining plan entries. May return an MFA challenge table.
-- Hard switch / ABA failures return an error string (no silent skip).
-- Mix (no harvestPriorityKind): one batch per sub-account per refresh, then pause.
function runSubAccountScanLoop()
  local state=LocalStorage.subAccountScan
  if state == nil then
    return "Amazon: Abruf der Unterkonten ohne Status"
  end
  while state.index <= #state.plan do
    local want=state.plan[state.index]
    local page=openAccountSwitcherEmbed()
    if page == nil then
      clearSubAccountScanState()
      return "Amazon: Kontenwechsel nicht verfügbar – Unterkonto \""
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
    local advance, harvestErr=harvestAndAdvanceSubAccountScan(
      state, match.label, match.kind)
    if harvestErr ~= nil then
      return harvestErr
    end
    if advance == 'pause' then
      local open=state.plan[state.index]
      local openLabel=(type(open) == 'table' and open.label) or match.label
      print("sub-account harvest batch paused; more orders for", tostring(openLabel))
      return nil
    end
    if advance == 'continue' and state.harvestHasMore then
      print("sub-account harvest batch paused; more orders for", tostring(match.label),
        "; continuing other sub-accounts")
    elseif advance == 'done' then
      break
    end
  end
  completeSubAccountScan(state, false)
  print("sub-account scan done, new orders=", state.totalNew)
  return nil
end

--- @function continueSubAccountScan
-- Drives personal+business harvest. otpCode required when phase=await_mfa.
-- @return nil on success, challenge table for MFA, or error string
function subAccountScanCurrentKind(state)
  if type(state) ~= 'table' or type(state.plan) ~= 'table' then
    return nil
  end
  local idx=state.index
  if type(idx) ~= 'number' or idx < 1 then
    idx=1
  end
  local entry=state.plan[idx]
  if type(entry) == 'table' then
    return entry.kind
  end
  return nil
end

--- Drop a preserved/running scan when RefreshAccount targets another sub-account.
function realignSubAccountScanForHarvestPriority(priorityKind)
  if priorityKind == nil then
    return
  end
  local state=LocalStorage and LocalStorage.subAccountScan
  if type(state) ~= 'table' or state.phase ~= 'running' then
    return
  end
  if subAccountScanCurrentKind(state) == priorityKind then
    return
  end
  print("sub-account scan realigned for priority", priorityKind)
  clearSubAccountScanState()
end

function continueSubAccountScan(otpCode)
  realignSubAccountScanForHarvestPriority(LocalStorage.harvestPriorityKind)
  local state=LocalStorage.subAccountScan
  if state ~= nil and state.phase == 'done' then
    return nil
  end
  if state ~= nil and state.phase == 'await_mfa' then
    return continueMfaSubAccountSwitch(state, otpCode)
  end
  if state == nil or state.phase ~= 'running' then
    local priorityKind=LocalStorage.harvestPriorityKind
    return startSubAccountScan(priorityKind)
  end
  return runSubAccountScanLoop()
end

--- @function readAmazonCustomerIdForSession
-- customerId of the active session. Sub-account switches can land on pages that
-- do not embed it, so retry on the css order-history landing page. Without a
-- timeFilter that page only serves the shell, it does not harvest orders.
function readAmazonCustomerIdForSession()
  local customerId=parseAmazonCustomerIdFromHtml(html)
  if customerId ~= nil then
    return customerId
  end
  local probe=connectShop('GET', buildOrderHistoryUrl('css'))
  if probe == nil then
    return nil
  end
  local resolved, akamaiErr=resolveAkamaiInterstitial(probe)
  if akamaiErr ~= nil then
    print("Akamai on customerId probe:", akamaiErr)
  end
  return parseAmazonCustomerIdFromHtml(resolved)
end

--- @function storedCustomerIdForKind
-- customerId already stored for a switcher kind, if complete.
function storedCustomerIdForKind(kind)
  if type(kind) ~= 'string' or kind == '' then
    return nil
  end
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) ~= 'table' then
    return nil
  end
  for _,sub in ipairs(discovered) do
    if type(sub) == 'table' and sub.kind == kind and isCompleteDiscoveredSubAccount(sub) then
      return sub.accountNumber
    end
  end
  return nil
end

--- @function canReuseStoredCustomerIds
-- Harvest refresh can skip ID-switch enrichment when every switcher option
-- already has a stored customerId for its kind.
function canReuseStoredCustomerIds(options)
  if type(options) ~= 'table' or #options < 2 then
    return false
  end
  for _,option in ipairs(options) do
    if type(option) ~= 'table' or type(option.kind) ~= 'string'
        or storedCustomerIdForKind(option.kind) == nil then
      return false
    end
  end
  return true
end

function attachStoredCustomerIds(options)
  if type(options) ~= 'table' then
    return
  end
  for _,option in ipairs(options) do
    if type(option) == 'table' then
      local customerId=storedCustomerIdForKind(option.kind)
      option.customerId=customerId
      option.accountNumber=customerId
    end
  end
end

--- True when LocalStorage already has a complete personal+business discovery set.
function canReuseDiscoveredSubAccountsWithoutSwitcher()
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) ~= 'table' or #discovered < 2 then
    return false
  end
  local kinds={}
  for _,sub in ipairs(discovered) do
    if not isCompleteDiscoveredSubAccount(sub) then
      return false
    end
    kinds[sub.kind]=true
  end
  return kinds.personal == true and kinds.business == true
end

function optionsFromDiscoveredSubAccounts()
  local discovered=LocalStorage.discoveredSubAccounts
  local options={}
  if type(discovered) ~= 'table' then
    return options
  end
  for _,sub in ipairs(discovered) do
    if type(sub) == 'table' then
      local customerId=sub.customerId or sub.accountNumber
      table.insert(options, {
        kind=sub.kind,
        label=sub.label,
        customerId=customerId,
        accountNumber=customerId or sub.accountNumber,
        accountType=sub.accountType,
        businessName=sub.businessName,
        customerName=sub.customerName,
      })
    end
  end
  return options
end

--- @function discoverAmazonSubAccounts
-- ListAccounts / "Nach neuen Konten suchen": read each sub-account customerId
-- via short session switches, then restore the session active at entry.
-- Does not harvest orders (no Umsätze); the customerId fallback loads the
-- order-history shell only.
-- opts.reuseCustomerIds: when true, skip switcher+enrichment if LocalStorage
-- already holds complete personal+business customerIds.
-- @return #table|nil switcher options (may be empty), error string on failure
function discoverAmazonSubAccounts(statusText, opts)
  opts=type(opts) == 'table' and opts or {}
  local msg=statusText
  if type(msg) ~= 'string' or msg == '' then
    msg="Amazon: Unterkonten werden ermittelt…"
  end

  if opts.reuseCustomerIds and canReuseDiscoveredSubAccountsWithoutSwitcher() then
    local options=optionsFromDiscoveredSubAccounts()
    print("discovered Amazon sub-accounts=", #options, "(reused, no switcher)")
    return options, nil
  end

  MM.printStatus(msg)
  local switcherHtml=openAccountSwitcherEmbed()
  local authBlock=switchAuthBlockReason(switcherHtml or html)
  if authBlock ~= nil then
    if authBlock == "MFA" then
      authBlock="2FA"
    end
    return nil, "Amazon-Unterkonto-Ermittlung erfordert "..authBlock
  end
  local options={}
  if switcherHtml ~= nil then
    options=parseAccountSwitcher(switcherHtml)
  end
  if #options < 2 then
    rememberDiscoveredSubAccounts(options)
    print("discovered Amazon sub-accounts=0")
    return options, nil
  end

  if opts.reuseCustomerIds and canReuseStoredCustomerIds(options) then
    attachStoredCustomerIds(options)
    rememberDiscoveredSubAccounts(options)
    print("discovered Amazon sub-accounts=", #LocalStorage.discoveredSubAccounts, "(reused)")
    return options, nil
  end

  local startingKind=activeAmazonSubAccountKind()
  if startingKind == nil then
    return nil, "Amazon-Ausgangskonto konnte für die Unterkonto-Ermittlung nicht erkannt werden"
  end

  local discoveryErr=nil
  for _,option in ipairs(options) do
    local switchErr=ensureAmazonSubAccountSession(option.kind)
    if switchErr ~= nil then
      discoveryErr="Amazon-Unterkonto-Ermittlung fehlgeschlagen: "..switchErr
      break
    end
    local customerId=readAmazonCustomerIdForSession()
    option.customerId=customerId
    option.accountNumber=customerId
  end

  local restoreErr=ensureAmazonSubAccountSession(startingKind)
  if restoreErr ~= nil then
    return nil, "Amazon-Ausgangskonto konnte nicht wiederhergestellt werden: "..restoreErr
  end
  if discoveryErr ~= nil then
    return nil, discoveryErr
  end

  rememberDiscoveredSubAccounts(options)
  local n=0
  if type(LocalStorage.discoveredSubAccounts) == 'table' then
    n=#LocalStorage.discoveredSubAccounts
  end
  print("discovered Amazon sub-accounts=", n)
  return options, nil
end

function startSubAccountScan(priorityKind)
  local options, discoveryErr=discoverAmazonSubAccounts(
    "Amazon: Bestellhistorie wird geladen…",
    {reuseCustomerIds=true})
  if discoveryErr ~= nil then
    return discoveryErr
  end
  if #options == 0 then
    print("no switchable Amazon sub-accounts, scraping current session")
    local n, err, hasMore=harvestSubAccountPlanEntry("", nil)
    if err ~= nil then
      return err
    end
    LocalStorage.subAccountScan=newSubAccountScanDoneState(n or 0, hasMore and true or false)
    return nil
  end
  beginSubAccountScanPlan(options, priorityKind)
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
  local existing=LocalStorage and LocalStorage.subAccountScan
  if type(existing) == 'table' then
    existing.harvestedPlanThisRefresh={}
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

function getLastDayOfPeriod(period)
  local year=string.match(period,"(%d%d%d%d)")
  local month=string.match(period,"-(%d%d)")
  --debugBuffer.print("getLastDayOfPeriod",period,year,month)
  if month == nil then
    month="12"
  end
  year=tonumber(year)
  month=tonumber(month)
  if year == nil or month == nil then
    error("invalid period: "..tostring(period))
  end
  local day=const.daysByMonth[month]
  if day == nil then
    error("invalid period month: "..tostring(period))
  end
  if month == 2 and (year%4) == 0 and ((year%400)==0 or (year%100)~=0) then
    day=29
  end
  return os.time{year=year,month=month,day=day}
end

function SupportsBank (protocol, bankCode)
  if protocol ~= ProtocolWebBanking then
    return false
  end
  if type(bankCode) ~= 'string' then
    return false
  end
  -- Nur der aktuelle Service. "Amazon Orders" (Beutling), "Amazon" (Fork-Alt /
  -- Kreditkarten-Kollision) und sonstige Namen werden bewusst nicht bedient.
  return bankCode == const.services[1]
end

function endsWith(string,ending)
  return string:sub(-#ending) == ending
end

--- @function applyAccountAttribute
-- Applies one account note / patcher key to config/const.
-- allowConfigStrings: RefreshAccount also overwrites string config values.
function applyAccountAttribute(k, v, allowConfigStrings)
  local canonical=canonicalAccountAttributeKey(k)
  if canonical == nil or not isSupportedAccountAttributeKey(k) then
    print("ignore unknown account attribute", k, v)
    return
  end
  if type(config[canonical]) == 'boolean' then
    local flag=(v == 'true')
    print("set config",canonical,"=", flag and "true" or "false")
    config[canonical]=flag
  end
  if type(config[canonical]) == 'number' then
    local n=tonumber(v)
    if n ~= nil then
      print("set config",canonical,n)
      config[canonical]=n
    else
      print("ignore non-numeric config",canonical,v)
    end
  end
  if allowConfigStrings and type(config[canonical]) == 'string' then
    print("set config",canonical,v)
    config[canonical]=v
  end
  if type(const[canonical]) == 'string' then
    print("const k=",v)
    if canonical == 'orderDetailsUrl' and type(v) == 'string' and v:match("^https?://") then
      absoluteAmazonUrl(v) -- reject foreign hosts for account-note overrides
    end
    const[canonical]=v
  end
end

function connectShopForm(formNode)
  if formNode == nil or formNode:length() == 0 then
    return nil
  end
  local action = formNode:attr("action")
  if type(action) == 'string' and action ~= '' then
    absoluteAmazonUrl(action)
  end
  return connectShop(formNode:submit())
end

function failMissingLoginPage(stage)
  local message="Amazon: Anmeldung ohne Antwortseite"
  if type(stage) == 'string' and stage ~= '' then
    message=message.." ("..stage..")"
  end
  MM.printStatus(message)
  print(message)
  return message
end

function isCredentialRejectionMessage(message)
  if type(message) ~= 'string' then
    return false
  end
  local lower=message:lower()
  local markers={
    "incorrect password",
    "password is incorrect",
    "invalid user id or password",
    "invalid username or password",
    "wrong password",
    "falsches passwort",
    "passwort ist falsch",
    "ungültige anmeldedaten",
    "ungueltige anmeldedaten",
  }
  for _,marker in ipairs(markers) do
    if lower:find(marker,1,true) then
      return true
    end
  end
  return false
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
    activateAmazonLoginStorage(credentials[1])
    rememberShopCredentials(credentials[1], credentials[2])
    captcha1run=true
    mfa1run=true
    claimsVerify1run=true
    aName=nil
    if not shouldPreserveSubAccountScanOnLogin() then
      clearSubAccountScanState()
    end
    clearAccountSetupState()

    if LocalStorage.loginCounter == nil then
      LocalStorage.loginCounter=0
    end
    LocalStorage.loginCounter=LocalStorage.loginCounter+1
    syncSubAccountScanLoginCounter()
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
        end
      end
    end
    html = connectShop("GET",baseurl)
    local resolvedHtml, akamaiError = resolveAkamaiInterstitial(html)
    if akamaiError ~= nil then
      return "Amazon: "..akamaiError
    end
    html = resolvedHtml
    enterOrderList()
  end

  local leaveLoginLoop
  local loginLoops=1
  repeat
    leaveLoginLoop=true
    webCacheState="login"..loginLoops
    print("login "..loginLoops..". try")

    if html == nil then
      return failMissingLoginPage("Start")
    end

    -- $x('//div[@id="auth-error-message-box"]')
    local authError=html:xpath('//div[@id="auth-error-message-box"]'):text()

    if authError ~= '' then
      MM.printStatus(authError)
      if isCredentialRejectionMessage(authError) then
        print('login failed, clean cookies text')
        LocalStorage.cookies=nil
        return LoginFailed
      end
      return "Amazon: "..authError
    end



    -- Enterable OTP (classic MFA / CVF SMS-TOTP) before app-approval polling.
    -- Amazon CVF approval pages often include both on the same HTML.
    if isAmazonEnterableOtpPage(html) then
      print("multi factor auth")
      leaveLoginLoop=false
      if config.debug then print("login mfa") end
      if mfa1run then
        mfa1run=false
        local otpChallenge=loginOtpChallengeFromHtml(html)
        if otpChallenge == nil then
          return failMissingLoginPage("Zwei-Faktor-Authentifizierung")
        end
        return otpChallenge
      else
        local mfaPage, mfaErr=submitAmazonMfa(html, credentials[1])
        if mfaErr ~= nil or mfaPage == nil then
          return failMissingLoginPage("Zwei-Faktor-Authentifizierung")
        end
        html=mfaPage
        mfa1run=true
      end
    end

    -- Channel picker (SMS / email / …) before waiting on app approval.
    if isAmazonClaimsPickerPage(html) then
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
      end)
      if number == 0 then
        local pickerPage=submitAmazonClaimsPicker(html)
        if pickerPage == nil then
          return failMissingLoginPage("Bestätigungscode")
        end
        html=pickerPage
        if isAmazonClaimsVerifyPage(html) then
          return returnClaimsVerifyChallengeOrFail(html)
        end
      else
        if passcode1run then
          passcode1run=false
          return {
            title=html:xpath('//form[@action="claimspicker"]//div[1]'):text(),
            challenge=text,
            label='Please select 1-'..number
          }
        else
          local pickerPage=submitAmazonClaimsPicker(html)
          if pickerPage == nil then
            return failMissingLoginPage("Bestätigungsmethode")
          end
          html=pickerPage
          if isAmazonClaimsVerifyPage(html) then
            return returnClaimsVerifyChallengeOrFail(html)
          end
        end
      end
    end

    -- Claims verify OTP (field name=code) after channel selection.
    if isAmazonClaimsVerifyPage(html) then
      print("passcode part 2")
      leaveLoginLoop=false
      if config.debug then print("passcode 2. part") end
      if claimsVerify1run then
        return returnClaimsVerifyChallengeOrFail(html)
      else
        local verifyPage, verifyErr=submitAmazonClaimsVerify(html, credentials[1])
        if verifyErr ~= nil or verifyPage == nil then
          return failMissingLoginPage("Bestätigungscode")
        end
        html=verifyPage
        claimsVerify1run=true
      end
    end

    -- Device select (TOTP / SMS / WhatsApp / EMAIL / VOICE) before app-approval polling.
    if isAmazonAuthDeviceSelectPage(html) then
      print("auth selector")
      leaveLoginLoop=false
      local authSelect=html:xpath('//form[@id="auth-select-device-form"]')
      applyPreferredAmazonAuthDeviceSelection(authSelect)
      html=connectShopForm(authSelect)
      if html == nil then
        return failMissingLoginPage("Authentifizierungsmethode")
      end
    end

    -- App approval polling only when no enterable OTP is on the page.
    if isAmazonAppApprovalPollingPage(html) then
      print("auth link sended")
      local authLink=html:xpath('//form[@id="pollingForm"]')
      local waitUntil=os.time()+300
      local poll
      repeat
        MM.printStatus("Bitte in der Amazon-App freigeben, noch "
          ..tostring(math.floor(waitUntil-os.time())).." Sekunden")
        MM.sleep(3)
        local pollPage=connectShopForm(authLink)
        if pollPage == nil then
          return failMissingLoginPage("Anmeldebestätigung")
        end
        poll=pollPage:xpath('//input[@name="transactionApprovalStatus"]'):attr('value')
        print("poll="..poll)
      until( poll == 'TransactionCompleted' or waitUntil<os.time())
      if poll ~= 'TransactionCompleted' then
        return "Amazon: Anmeldebestätigung in der App nicht rechtzeitig erfolgt"
      end
      leaveLoginLoop=false
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
      print('Account selector arbToken=<redacted>')
      local embed=accountSwitcherEmbedUrl(arbToken, cvfEmbedVersionQuery(html))
      html=connectShop('GET', absoluteAmazonUrl(embed))
      if html == nil then
        return failMissingLoginPage("Kontowahl")
      end
      leaveLoginLoop=false
      -- work-a-round simple add new login
      local signInLink=html:xpath('//a[@id="cvf-account-switcher-add-accounts-link"]'):attr('href')
      if type(signInLink) == 'string' and signInLink ~= '' then
        local logPath=signInLink:match("^([^?#]+)") or signInLink
        print('signInLink='..logPath)
        html=connectShop('GET',signInLink)
        if html == nil then
          return failMissingLoginPage("Zusätzliches Konto")
        end
      end
    end

    -- Captcha
    local captcha=html:xpath('//img[@id="auth-captcha-image"]'):attr('src')
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
      html= connectShopForm(html:xpath(xpform))
      if html == nil then
        return failMissingLoginPage("Benutzername und Passwort")
      end
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
    return failMissingLoginPage("Unerwartete Antwort")
  end

  -- Account search: discover sub-accounts only (no order harvest / no Umsätze).
  -- Harvest runs later in RefreshAccount after the user chose an account.
  local _, discoveryErr=discoverAmazonSubAccounts(nil, {reuseCustomerIds=true})
  if discoveryErr ~= nil then
    return discoveryErr
  end
  return nil
end

function resolveListAccountsDisplayName()
  local name=aName
  if name == nil or name == "" then
    name=secUsername
  end
  if name == nil or name == "" then
    name="Orders"
  end
  return name
end

function findKnownAccountAttributes(knownAccounts, accountNumber)
  if type(knownAccounts) ~= 'table' then
    return nil
  end
  for _,entry in ipairs(knownAccounts) do
    if entry == accountNumber then
      return nil
    end
    if type(entry) == 'table' and entry.accountNumber == accountNumber then
      return entry.attributes
    end
  end
  return nil
end

function buildListAccountAttributes(knownAccounts, accountNumber)
  -- MoneyMoney ListAccounts accepts either a pure string array (field names only,
  -- BoA pattern) or a pure string-key table (name → default value). A hybrid
  -- table with both array indices and string keys is ignored and leaves the Notes
  -- UI empty.
  return mergeAccountAttributes(defaultAccountAttributes(),
    findKnownAccountAttributes(knownAccounts, accountNumber))
end

function buildAccountAttributes(knownAccounts, accountNumber)
  return buildListAccountAttributes(knownAccounts, accountNumber)
end

function makeListAccountEntry(name, owner, accountNumber, knownAccounts)
  -- Explizit Sonstige über Host-Konstante AccountTypeOther.
  -- MoneyMoney setzt die Kontoart nur bei Neu-Anlage; Refresh ändert sie nicht.
  -- Bekannter Host-Bug: trotz AccountTypeOther werden Konten oft als Kreditkarte
  -- angelegt (siehe docs/bug-reports/…). Unterkonten: AO.<customerId ohne A>.
  local accountType=AccountTypeOther
  if accountType == nil then
    error("Amazon: AccountTypeOther fehlt in der MoneyMoney-Laufzeit")
  end
  return {
    name=name,
    owner=owner,
    accountNumber=accountNumber,
    type=accountType,
    portfolio=false,
    currency="EUR",
    -- MoneyMoney Konto-Einstellungen (undokumentiert, wie showDailyBalance):
    -- "Gesamtsumme" / Total sum in der Seitenleiste.
    withTotalSum=false,
    -- "In Diagrammen anzeigen" (Auswertungen, nicht nur Balkendiagramm).
    showInDiagrams=false,
    -- "Balkendiagramm anzeigen" in der Übersicht.
    showDailyBalance=false,
    -- perspective.chart=1 → Ansicht → Liste (⌘1); 2=Balkendiagramm, 3=Tortendiagramm.
    perspective={ chart=1 },
    attributes=buildAccountAttributes(knownAccounts, accountNumber),
  }
end

function loadOrderBlacklistFromConfig()
  local list={}
  for order in string.gmatch(config.blacklistOrders, "[D0-9-]+") do
    print("blacklist order=",order)
    list[order]=true
  end
  return list
end

function ListAccounts (knownAccounts)
  -- MoneyMoney calls RefreshAccount right after ListAccounts, still during
  -- "Konten werden gesucht" — before the user confirmed the selection.
  -- That RefreshAccount must not load bookings. Erstimport runs on the first
  -- RefreshAccount after EndSession (Kontenrundruf / Aktualisieren).
  local enableInitialSync=type(LocalStorage.lastHarvestSince) ~= 'number'
  beginAccountSetupSession(enableInitialSync)
  if type(secUsername) ~= 'string' or secUsername == '' then
    error("Amazon: ListAccounts benötigt den Anmeldenamen (E-Mail)")
  end
  local owner=secUsername
  local accounts={makeListAccountEntry("Amazon", owner, secUsername, knownAccounts)}

  local discovered=LocalStorage.discoveredSubAccounts
  local completeDiscovered={}
  if type(discovered) == 'table' then
    for _,sub in ipairs(discovered) do
      if isCompleteDiscoveredSubAccount(sub) then
        table.insert(completeDiscovered, sub)
      end
    end
  end
  if #completeDiscovered > 1 then
    for _,sub in ipairs(completeDiscovered) do
      local mmNumber=moneyMoneyAccountNumberForCustomerId(sub.accountNumber)
      table.insert(accounts, makeListAccountEntry(
        "Amazon "..listAccountDisplayLabel(sub.accountNumber, sub),
        owner, mmNumber, knownAccounts))
    end
  end
  return accounts
end

function fetchOrderDetailsBatch(pendingDetails, now, detailsLimit, fetchState)
  if type(fetchState) ~= 'table' then
    error("fetchOrderDetailsBatch requires fetchState")
  end
  if type(pendingDetails) ~= 'table' or #pendingDetails == 0 then
    return fetchState
  end
  if html == nil then
    html=connectShop("GET",baseurl)
  end
  local ordersTotal=#pendingDetails
  local batchCounter=0
  if ordersTotal + fetchState.counter > detailsLimit then
    MM.printStatus("Amazon: noch "..tostring(ordersTotal + fetchState.counter - detailsLimit)
      .." Bestelldetails offen – Fortsetzung beim nächsten Aktualisieren")
    ordersTotal=detailsLimit - fetchState.counter
    if ordersTotal <= 0 then
      return fetchState
    end
  end
  for i=1,#pendingDetails do
    if fetchState.counter >= detailsLimit or batchCounter >= ordersTotal then
      break
    end
    batchCounter=batchCounter+1
    fetchState.counter=fetchState.counter+1
    local entry=pendingDetails[i]
    local orderCode=entry.orderCode
    local order=entry.order
    if not orderBlacklist[orderCode] then
      MM.printStatus(fetchState.counter.."/"..detailsLimit
        .." Bestelldetails für "..tostring(orderCode))
      if getOrderDetails(order) ~= true then
        fetchState.failed=fetchState.failed+1
      end
    else
      MM.printStatus(fetchState.counter.."/"..detailsLimit
        .." Bestellung gesperrt: "..tostring(orderCode))
      scheduleNextDetailsDate(order, now)
    end
  end
  return fetchState
end

function fetchDetailsInSubAccountSession(kind, accountNumber, now, detailsLimit, fetchState)
  local sessionErr=ensureAmazonSubAccountSession(kind)
  if sessionErr ~= nil then
    MM.printStatus("Amazon: "..sessionErr)
    return sessionErr
  end
  fetchOrderDetailsBatch(
    ordersNeedingDetailsForAccount(accountNumber, now),
    now,
    detailsLimit,
    fetchState)
  return nil
end

function fetchPendingOrderDetails(accountNumber, now)
  local fetchState={counter=0, pendingAtStart=0, failed=0}
  fetchState.pendingAtStart=pendingDetailsCountForRefresh(accountNumber, now)
  if fetchState.pendingAtStart == 0 then
    return fetchState
  end
  local detailsLimit=config.limitOrders

  if isCombinedInitialSyncDetailsFetch(accountNumber) then
    local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
    if type(discovered) == 'table' and #discovered > 0 then
      for _, sub in ipairs(discovered) do
        if type(sub) == 'table' and type(sub.kind) == 'string' and sub.kind ~= '' then
          local subAccountNumber=subAccountNumberForKind(sub.kind)
          local sessionErr=fetchDetailsInSubAccountSession(
            sub.kind, subAccountNumber, now, detailsLimit, fetchState)
          if sessionErr ~= nil then
            return fetchState
          end
          if fetchState.counter >= detailsLimit then
            return fetchState
          end
        end
      end
      return fetchState
    end
    fetchOrderDetailsBatch(ordersNeedingDetailsInCache(now), now, detailsLimit, fetchState)
    return fetchState
  end

  local wantKind=harvestPriorityKindFromAccountNumber(accountNumber)
  if wantKind ~= nil then
    local sessionErr=fetchDetailsInSubAccountSession(
      wantKind, accountNumber, now, detailsLimit, fetchState)
    if sessionErr ~= nil then
      return fetchState
    end
    return fetchState
  end
  fetchOrderDetailsBatch(
    ordersNeedingDetailsForAccount(accountNumber, now),
    now,
    detailsLimit,
    fetchState)
  return fetchState
end

function RefreshAccount (account, since)
  assertCurrentMoneyMoneyAccountNumber(account and account.accountNumber)
  local now=os.time()

  webCacheState='RefreshAccount'

  applyImportSchemaUpgrade()

  config.keepStorno=false
  config.nameMaxLength=0
  if type(account.attributes) == 'table' then
    LocalStorage.patcher={}
    for k,v in pairs(account.attributes) do
      if type(k) == 'string' and type(v) == 'string' then
        local canonical=canonicalAccountAttributeKey(k)
        if canonical ~= nil and isSupportedAccountAttributeKey(k) then
          print("attribut",canonical,v)
          LocalStorage.patcher[canonical]=v
          applyAccountAttribute(k, v, true)
          if canonical == 'resetCache' and v ~= '' and v ~= LocalStorage.resetCache then
            resetImportState(false)
            LocalStorage.resetCache=v
            MM.printStatus("Amazon: Cache zurückgesetzt – Bestellungen werden neu geladen…")
          end
        end
      end
    end
  end

  local blocked=refreshAccountBlockedResult()
  if blocked ~= nil then
    return blocked
  end

  ensureOrderCache()
  orderBlacklist=loadOrderBlacklistFromConfig()

  local divisor=refreshAccountLedgerProfile(account.accountNumber).divisor

  print("Refresh",accountNumberForLog(account.accountNumber))

  local transactions={}

  local refreshSince=effectiveRefreshSince(since)
  if isPendingInitialSync() and not isAccountSetupSession() and not isInitialSyncHarvestDone() then
    MM.printStatus("Amazon: Erstimport – gesamte Bestellhistorie wird geladen…")
  end
  LocalStorage.refreshSince=refreshSince
  local harvest=shouldRunAccountHarvest(refreshSince, now)
  local scanErr=nil
  local scanComplete=false
  local detailsFetchState={counter=0}

  local prefetchInitialSyncDetails=isPendingInitialSync()
    and not isAccountSetupSession()
    and not harvest
  if prefetchInitialSyncDetails then
    detailsFetchState=fetchPendingOrderDetails(account.accountNumber, now)
  end

  if harvest then
    logMoneyMoneyRefreshMode(refreshSince, now)

    html=connectShop("GET",baseurl)

    ensureOrderFilterCacheRoot()
    ensureInvalidCache()

    LocalStorage.harvestPriorityKind=harvestPriorityKindFromAccountNumber(account.accountNumber)
    local _, harvestScanErr=scanAllAmazonSubAccounts()
    LocalStorage.harvestPriorityKind=nil
    scanErr=harvestScanErr
    scanComplete=isFullAccountHarvestComplete()
    if scanErr ~= nil then
      MM.printStatus("Amazon: "..tostring(scanErr))
    elseif scanComplete then
      LocalStorage.lastLoginCounter = LocalStorage.loginCounter
      LocalStorage.lastHarvestSince=refreshSince
      LocalStorage.lastListHarvestAt=now
      if isPendingInitialSync() then
        markInitialSyncHarvestDone()
      end
    elseif isPendingInitialSync() then
      MM.printStatus("Amazon: Erstimport – Abruf der Unterkonten unvollständig, Fortsetzung beim nächsten Aktualisieren")
    end
  else
    print("skip account scan")
    -- Details-only refresh still settles the login watermark so later gates stay consistent.
    if not isAccountSetupSession()
        and not isPendingInitialSync()
        and LocalStorage.loginCounter ~= LocalStorage.lastLoginCounter
        and isIncrementalMoneyMoneyRefresh(refreshSince, now)
        and not incrementalListHarvestNeeded(refreshSince, now) then
      LocalStorage.lastLoginCounter=LocalStorage.loginCounter
    end
  end

  local refundWatch=scheduleIncrementalRefundWatch(account.accountNumber, refreshSince, now)
  if refundWatch > 0 then
    print("incremental refund watch: re-queued details for", refundWatch, "orders")
  end

  if LocalStorage.OrderCache[config.rescanOrder] ~= nil then
    LocalStorage.OrderCache[config.rescanOrder].detailsDate=1
    clearOrderEmittedFlags(LocalStorage.OrderCache[config.rescanOrder])
    print("rescan order="..config.rescanOrder)
  end

  if harvest or not prefetchInitialSyncDetails then
    detailsFetchState=fetchPendingOrderDetails(account.accountNumber, now)
  end

  if shouldRecordInitialSyncAccountRefresh(harvest, scanErr, scanComplete) then
    recordInitialSyncAccountRefresh(account.accountNumber)
  end
  tryCompleteInitialSync(now)

  local ctx={
    transactions=transactions,
    accountNumber=account.accountNumber,
    divisor=divisor,
    now=now,
    balance=0,
  }
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    if not orderBlacklist[orderCode] and orderMatchesMoneyMoneyAccount(order, ctx.accountNumber) then
      appendOrderToRefresh(ctx, order, orderCode)
    end
  end

  addMixFloatingBalance(transactions, ctx.accountNumber, refreshSince, now, divisor)

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

  reportEmptyEmitIfMisaligned(account.accountNumber, transactions, now)

  appendIncompleteHarvestDummy(transactions, account.accountNumber, now, harvest, detailsFetchState)
  sortTransactionsNewestFirst(transactions)

  return {balance=ctx.balance/divisor, transactions=transactions}
end

function EndSession ()
  clearAccountSetupState()
  tryCompleteInitialSync(os.time())
  local persistLogin = shouldPersistAmazonLoginSession(LocalStorage)
  -- Multi-login: keep cookies in LocalStorage.logins[loginKey]; remote logout
  -- would invalidate the persisted jar for the next sync of this login.
  if config.reallyLogout and html ~= nil and not persistLogin then
    local logoutElement=html:xpath('//a[contains(@id,"nav-item-signout") or contains(@href,"sign-out")]')
    if logoutElement ~= nil then
      print("Logout")
      local logoutResponse=logoutElement:click()
      if logoutResponse ~= nil then
        html=connectShop(logoutResponse)
      end
    else
      print("error: logout link not found")
    end
  end
  if type(LocalStorage) == 'table' then
    suspendAmazonLoginState(LocalStorage)
  end
  connection = nil
  secPassword=nil
  secUsername=nil
end

-- SIGNATURE: MCwCFADXoW9IQ8E3gKZIvLlZX6w/MPcrAhRKrBC+jjNHPEpgB3p4b7GDoJxG1w==
