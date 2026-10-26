# Amazon WAF Challenge + Cookie Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Softblock vor Claim: wenn möglich native MoneyMoney-AWS-WAF-Captcha (C), sonst klare Bot-Prüfung-Meldung (A) und jederzeit `COOKIE:…`-Import (B); nie irreführendes „Passwort falsch“.

**Architecture:** Softblock- und COOKIE-Basis von `bugfix/claim-challenge-login` (2.06/2.07) übernehmen. Neu: aus Softblock-HTML absolute `*.token.awswaf.com/.../challenge.js`-URL + `sitekey` extrahieren; bei `interactive` Captcha-Challenge zurückgeben und `LocalStorage.awsWafCaptchaPending=true` setzen; Token einmal als Cookie `aws-waf-token` setzen, Startseite neu laden; sonst kanonische A-Meldung. Plugin bleibt eine Datei `amazon-bestellungen.lua`.

**Tech Stack:** LuaJIT / MoneyMoney WebBanking API (`InitializeSession2` Challenges), `test/run.sh` + `test/mm_shim.lua`, Fixtures unter `test/fixtures/`.

**Spec:** `docs/superpowers/specs/2026-10-26-amazon-waf-challenge-cookie-fallback-design.md`

## Global Constraints

- Single-file plugin: nur `amazon-bestellungen.lua` (+ Tests/README/Fixtures/`test/measure_diff_crap.lua`)
- Kein Claim hinter ungelöster Softblock-Seite
- Bot-Prüfung-UI ≠ Passwort-Dialog ≠ OTP-Titel (`Amazon Bot-Prüfung`)
- `COOKIE:`-Blob nie als `secPassword`
- Max. ein C-Versuch pro Login-Lauf; gesteuert ausschließlich über `LocalStorage.awsWafCaptchaPending` (kein paralleles Modul-Flag)
- `interactive ~= true` → kein C, nur A
- Token-Apply: Cookie `aws-waf-token=<token>` (Domain=`const.domain`, Path=/; Secure), dann `GET` Startseite; Token nie in `LocalStorage` speichern
- C nur bei **absoluter** Script-URL mit Host `token.awswaf.com` und Pfad/`src` der `challenge.js` enthält; relative Scripts → kein C (A)
- Keine Secrets/Cookies in Issues oder Fixtures
- Unrelated WIP auf `master` nicht mischen; Feature-Branch von `origin/bugfix/claim-challenge-login` (Worktree empfohlen)
- Offline: `./test/run.sh <script.lua>`
- Version nach Feature: `WebBanking.version = 2.08`

## File map

| File | Responsibility |
| --- | --- |
| `amazon-bestellungen.lua` | Softblock, Extraktion, Challenge, Token-Apply, COOKIE-Import, `InitializeSession2` |
| `test/fixtures/aws_waf_challenge.html` | Softblock mit `challenge.js` ohne Sitekey / falscher Host (→ A) |
| `test/fixtures/aws_waf_softblock_shell.html` | Leere Schale (→ A) |
| `test/fixtures/aws_waf_challenge_sitekey.html` | Softblock mit `token.awswaf.com` + Sitekey (→ C) |
| `test/test_aws_waf_softblock.lua` | Halt / A ohne C |
| `test/test_aws_waf_captcha_challenge.lua` | Extraktion, Challenge-Return, Step-2 Apply, interactive-Guard, Order-List-C |
| `test/test_cookie_import.lua` | B (bereits auf Branch) |
| `test/measure_diff_crap.lua` | Neue Helper-Namen registrieren |
| `README.md` | Nutzerhinweise C→A→B |

---

### Task 1: Arbeitsbranch + Softblock/COOKIE-Basis

**Files:**
- Branch from: `origin/bugfix/claim-challenge-login`
- Verify: `test/test_aws_waf_softblock.lua`, `test/test_cookie_import.lua`, `test/test_claim_collect_signin.lua`

**Interfaces:**
- Consumes: `isAmazonAwsWafChallengePage`, `amazonAwsWafSoftblockMessage`, `establishAmazonSessionFromImportedCookies`, `haltMessageIfAmazonAwsWaf`
- Produces: Feature-Branch auf 2.07-Linie; Spec/Plan von `master` per Cherry-Pick der Doc-Commits (falls noch nicht auf Branch)

- [ ] **Step 1: WIP auf master nicht zerstören**

Wenn `master` dirty ist (Claim-Collect-Diff o.ä.): **nicht** hart auschecken. Stattdessen Worktree:

```bash
git fetch origin
git worktree add ../Amazon-MoneyMoney-waf-challenge origin/bugfix/claim-challenge-login
cd ../Amazon-MoneyMoney-waf-challenge
git checkout -B feature/waf-challenge-cookie-fallback
```

Oder im selben Repo nur wenn Working Tree clean:

```bash
git fetch origin
git checkout -B feature/waf-challenge-cookie-fallback origin/bugfix/claim-challenge-login
```

- [ ] **Step 2: Spec/Plan-Commits von master holen (falls fehlend)**

```bash
git cherry-pick 397ac50 0287171
```

(Commit-Hashes der Spec- bzw. Plan-Commits auf `master`; bei Konflikt nur Doc-Dateien behalten.)

- [ ] **Step 3: Basis-Tests**

```bash
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
./test/run.sh test/test_claim_collect_signin.lua
```

Expected: PASS. Bei FAIL zuerst Basis reparieren.

- [ ] **Step 4: Commit nur bei Checkout-Fixes**

Sonst kein leerer Commit — weiter Task 2.

---

### Task 2: Kanonische A-Meldung

**Files:**
- Modify: `amazon-bestellungen.lua` (`amazonAwsWafSoftblockMessage`)
- Modify: `test/test_aws_waf_softblock.lua`
- Modify: `README.md` (Bot-Prüfung-Absatz an Text angleichen)

**Interfaces:**
- Produces: `amazonAwsWafSoftblockMessage() -> string`

- [ ] **Step 1: Assert auf kanonischen Text schärfen (rot erwarten)**

In `test/test_aws_waf_softblock.lua` zusätzlich:

```lua
assert(result:find("keine falsche Passwort", 1, true),
  "softblock message must say it is not a wrong-password error, got: " .. result)
assert(result:find("MoneyMoney-Helper", 1, true)
    or result:find("Helper", 1, true),
  "softblock message must mention Helper for COOKIE import")
```

- [ ] **Step 2: Implementierung**

```lua
function amazonAwsWafSoftblockMessage()
  return "Amazon: Bot-Prüfung nicht gelöst. Bitte im Browser bei amazon.de "
    .."anmelden, Session mit dem MoneyMoney-Helper als COOKIE:… ins "
    .."Passwortfeld legen (siehe README) und erneut abrufen. "
    .."Das ist keine falsche Passwort-Meldung."
end
```

- [ ] **Step 3: Test**

```bash
./test/run.sh test/test_aws_waf_softblock.lua
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add amazon-bestellungen.lua test/test_aws_waf_softblock.lua README.md
git commit -m "$(cat <<'EOF'
Align softblock user message with cookie-import guidance.

EOF
)"
```

---

### Task 3: Extraktion `challenge.js` + `sitekey` (TDD)

**Files:**
- Create: `test/fixtures/aws_waf_challenge_sitekey.html`
- Create: `test/test_aws_waf_captcha_challenge.lua`
- Modify: `amazon-bestellungen.lua` (Helpers direkt nach Softblock-Detect / `isAmazonAwsWafChallengePage`)
- Modify: `test/measure_diff_crap.lua` (Namen der drei neuen Funktionen)

**Interfaces:**
- Produces:
  - `extractAmazonAwsWafChallengeScriptUrl(htmlNode) -> string|nil`
  - `extractAmazonAwsWafSitekey(htmlNode, scriptUrl) -> string|nil`
  - `amazonAwsWafCaptchaChallengeParts(htmlNode, refererUrl) -> {scriptUrl=, sitekey=, referer=}|nil`

- [ ] **Step 1: Fixture**

`test/fixtures/aws_waf_challenge_sitekey.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title></title>
  <script src="https://techblog.token.awswaf.com/abc123/challenge.js"></script>
</head>
<body>
  <div id="challenge-container" data-sitekey="test-sitekey-001"></div>
  <script>
    window.gokuProps = { key: "test-sitekey-001" };
  </script>
</body>
</html>
```

- [ ] **Step 2: Failing tests**

`test/test_aws_waf_captcha_challenge.lua`:

```lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local function readFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "rb"))
  local html = f:read("*all")
  f:close()
  return html
end

local env = mm.loadPlugin("amazon-bestellungen.lua")
local withKey = mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
local noKey = mm.HTML(readFixture("aws_waf_challenge.html"))
local shell = mm.HTML(readFixture("aws_waf_softblock_shell.html"))
local relativeOnly = mm.HTML([[<!DOCTYPE html><html lang="en"><head><title></title>
<script src="/cdn/challenge.js"></script></head><body>
<div data-sitekey="x"></div></body></html>]])

local parts = env.amazonAwsWafCaptchaChallengeParts(
  withKey, "https://www.amazon.de/")
assert(type(parts) == "table", "sitekey fixture must yield challenge parts")
assert(parts.scriptUrl:find("token%.awswaf%.com", 1)
    and parts.scriptUrl:find("challenge%.js", 1),
  "scriptUrl must be token.awswaf.com challenge.js")
assert(parts.sitekey == "test-sitekey-001", "sitekey must be extracted")
assert(parts.referer == "https://www.amazon.de/", "referer must pass through")

assert(env.amazonAwsWafCaptchaChallengeParts(noKey, "https://www.amazon.de/") == nil,
  "challenge.js without sitekey / wrong host must not enable C")
assert(env.amazonAwsWafCaptchaChallengeParts(shell, "https://www.amazon.de/") == nil,
  "empty softblock shell must not enable C")
assert(env.amazonAwsWafCaptchaChallengeParts(relativeOnly, "https://www.amazon.de/") == nil,
  "relative challenge.js must not enable C")

print("ok extract")
```

- [ ] **Step 3: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

Expected: FAIL (`amazonAwsWafCaptchaChallengeParts` nil)

- [ ] **Step 4: Helpers implementieren**

```lua
local AMAZON_WAF_BOT_TITLE = "Amazon Bot-Prüfung"

function extractAmazonAwsWafChallengeScriptUrl(htmlNode)
  if htmlNode == nil then
    return nil
  end
  local raw = htmlNodeRaw(htmlNode)
  if raw == "" then
    return nil
  end
  local src = raw:match(
    '[sS][rR][cC]%s*=%s*["\'](https://[^"\']*token%.awswaf%.com[^"\']*challenge%.js[^"\']*)["\']')
  if type(src) ~= "string" or src == "" then
    return nil
  end
  return src
end

function extractAmazonAwsWafSitekey(htmlNode, scriptUrl)
  if htmlNode == nil then
    return nil
  end
  if type(scriptUrl) == "string" then
    local fromQuery = scriptUrl:match("[?&]sitekey=([^&#]+)")
    if type(fromQuery) == "string" and fromQuery ~= "" then
      return fromQuery
    end
  end
  local raw = htmlNodeRaw(htmlNode)
  if raw == "" then
    return nil
  end
  local key = raw:match('data%-sitekey%s*=%s*["\']([^"\']+)["\']')
    or raw:match('["\']sitekey["\']%s*:%s*["\']([^"\']+)["\']')
    or raw:match("gokuProps%s*=%s*{[^}]*key%s*:%s*[\"']([^\"']+)[\"']")
  if type(key) ~= "string" or key == "" then
    return nil
  end
  return key
end

function amazonAwsWafCaptchaChallengeParts(htmlNode, refererUrl)
  local scriptUrl = extractAmazonAwsWafChallengeScriptUrl(htmlNode)
  if scriptUrl == nil then
    return nil
  end
  local sitekey = extractAmazonAwsWafSitekey(htmlNode, scriptUrl)
  if sitekey == nil then
    return nil
  end
  if type(refererUrl) ~= "string" or refererUrl == "" then
    return nil
  end
  return {
    scriptUrl = scriptUrl,
    sitekey = sitekey,
    referer = refererUrl,
  }
end
```

Hinweis: `refererUrl` leer → `nil` Parts (kein stiller `baseurl`-Fallback in der Extraktion; Caller übergibt `baseurl` explizit).

In `test/measure_diff_crap.lua` die drei Funktionsnamen in die Ziel-Liste aufnehmen (wie bestehende WAF-/Cookie-Namen).

- [ ] **Step 5: Run — expect pass**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 6: Commit**

```bash
git add amazon-bestellungen.lua test/fixtures/aws_waf_challenge_sitekey.html \
  test/test_aws_waf_captcha_challenge.lua test/measure_diff_crap.lua
git commit -m "$(cat <<'EOF'
Extract AWS WAF challenge.js URL and sitekey for captcha handoff.

EOF
)"
```

---

### Task 4: Challenge-Tabelle + Softblock-Verzweigung in Login

**Files:**
- Modify: `amazon-bestellungen.lua` (`moneyMoneyAwsWafCaptchaChallenge`, `takeAwsWafCaptchaChallengeOrSoftblockMessage`, `InitializeSession2`)
- Modify: `test/test_aws_waf_captcha_challenge.lua`
- Modify: `test/measure_diff_crap.lua` (neue Funktionsnamen)

**Interfaces:**
- Consumes: `amazonAwsWafCaptchaChallengeParts`
- Produces:
  - `moneyMoneyAwsWafCaptchaChallenge(parts) -> {title=, challenge=, label=}`
  - `takeAwsWafCaptchaChallengeOrSoftblockMessage(htmlNode, refererUrl, interactive) -> table|string|nil`
  - Seiteneffekt bei Challenge: `LocalStorage.awsWafCaptchaPending = true`
  - `MM.urlencode` existiert im Shim (`tostring`-Stub reicht für Tests)

Challenge-URL:

```text
<scriptUrl ohne ?#query/fragment>?sitekey=<MM.urlencode(sitekey)>&referer=<MM.urlencode(referer)>
```

Kein `type=checkbox` (YAGNI).

- [ ] **Step 1: Tests erweitern** (in derselben Datei nach Extract-Tests)

```lua
---@diagnostic disable: duplicate-set-field
env.LocalStorage = { loginCounter = 0, patcher = {} }
env.connectShop = function()
  return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
env.enterOrderList = function()
  error("enterOrderList must not run when WAF captcha challenge is returned")
end

local ch = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch) == "table", "expected captcha challenge table, got " .. tostring(ch))
assert(ch.title == "Amazon Bot-Prüfung", "title must be Amazon Bot-Prüfung")
assert(type(ch.challenge) == "string"
  and ch.challenge:find("token%.awswaf%.com", 1)
  and ch.challenge:find("challenge%.js", 1)
  and ch.challenge:find("sitekey=", 1, true)
  and ch.challenge:find("referer=", 1, true),
  "challenge must be awswaf script URL with sitekey+referer")
assert(env.LocalStorage.awsWafCaptchaPending == true,
  "pending flag must be set when returning captcha challenge")

env.LocalStorage = { loginCounter = 0, patcher = {} }
local msg = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, false)
assert(type(msg) == "string" and msg:find("Bot-Prüfung", 1, true),
  "non-interactive must return A message")
assert(env.LocalStorage.awsWafCaptchaPending ~= true,
  "non-interactive must not set captcha pending")

-- Softblock first appears on order-list GET: still offer C when sitekey present
env.LocalStorage = { loginCounter = 0, patcher = {} }
local homeOk = [[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span></body></html>]]
local shopCalls = 0
local realEnter = env.enterOrderList
env.enterOrderList = realEnter
env.connectShop = function()
  shopCalls = shopCalls + 1
  if shopCalls == 1 then
    return mm.HTML(homeOk)
  end
  return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
local ch2 = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch2) == "table" and ch2.title == "Amazon Bot-Prüfung",
  "order-list softblock with sitekey must return captcha challenge")
```

- [ ] **Step 2: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 3: Implementieren**

`mm_shim.lua`: sicherstellen, dass `MM.urlencode` gesetzt ist (Branch hat bereits `urlencode = function(s) return tostring(s) end`).

```lua
function moneyMoneyAwsWafCaptchaChallenge(parts)
  local base = parts.scriptUrl:match("^([^?#]+)")
  local challengeUrl = base
    .. "?sitekey=" .. MM.urlencode(parts.sitekey)
    .. "&referer=" .. MM.urlencode(parts.referer)
  return {
    title = AMAZON_WAF_BOT_TITLE,
    challenge = challengeUrl,
    label = "Bot-Prüfung",
  }
end

function takeAwsWafCaptchaChallengeOrSoftblockMessage(htmlNode, refererUrl, interactive)
  if not isAmazonAwsWafChallengePage(htmlNode) then
    return nil
  end
  if interactive == true
      and type(LocalStorage) == "table"
      and LocalStorage.awsWafCaptchaPending ~= true then
    local parts = amazonAwsWafCaptchaChallengeParts(htmlNode, refererUrl)
    if parts ~= nil then
      LocalStorage.awsWafCaptchaPending = true
      return moneyMoneyAwsWafCaptchaChallenge(parts)
    end
  end
  return amazonAwsWafSoftblockMessage()
end
```

In `InitializeSession2` Step 1 die beiden Softblock-Stellen (Start + nach Order-List) ersetzen:

```lua
local wafResult = takeAwsWafCaptchaChallengeOrSoftblockMessage(
  html, baseurl, interactive)
if type(wafResult) == "table" then
  print("AWS WAF captcha challenge; pause before claim")
  return wafResult
end
if type(wafResult) == "string" then
  print("AWS WAF / softblock; halt before claim")
  MM.printStatus(wafResult)
  return wafResult
end
```

`LocalStorage.awsWafCaptchaPending` zu Session-Start (Step 1, neues Login) auf `nil`/`false` setzen — außer wenn Step > 1 und Pending schon gesetzt (Resume in Task 5).

- [ ] **Step 4: Tests**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
```

Expected: PASS (`aws_waf_challenge.html` ohne Sitekey weiter A)

- [ ] **Step 5: Commit**

```bash
git add amazon-bestellungen.lua test/test_aws_waf_captcha_challenge.lua \
  test/mm_shim.lua test/measure_diff_crap.lua
git commit -m "$(cat <<'EOF'
Return MoneyMoney AWS WAF captcha challenge when sitekey is present.

EOF
)"
```

---

### Task 5: Step 2 — Token anwenden, Login fortsetzen

**Files:**
- Modify: `amazon-bestellungen.lua` (`ensureAmazonShopConnection`, `applyAmazonAwsWafCaptchaToken`, Resume in `InitializeSession2`)
- Modify: `test/test_aws_waf_captcha_challenge.lua`
- Modify: `test/measure_diff_crap.lua`

**Interfaces:**
- Consumes: `credentials[1]` = WAF-Token; `LocalStorage.awsWafCaptchaPending == true`
- Produces:
  - `ensureAmazonShopConnection() -> nil` (legt `connection` an, lädt `LocalStorage.cookies` wie `connectShopRaw`)
  - `applyAmazonAwsWafCaptchaToken(token) -> nil|string` (`nil` = Cookie gesetzt; sonst A-Meldung)
  - Nach Apply: `LocalStorage.awsWafCaptchaPending = nil`, dann Softblock-Check mit `interactive=false` (kein zweites C)

- [ ] **Step 1: Failing tests**

```lua
-- Unit: empty token
env.LocalStorage = { loginCounter = 0, patcher = {}, cookies = "session-id=1" }
env.connection = nil
assert(env.applyAmazonAwsWafCaptchaToken("") ~= nil, "empty token must return A message")
assert(env.applyAmazonAwsWafCaptchaToken(nil) ~= nil, "nil token must return A message")

-- Unit: cookie set via ensureAmazonShopConnection
local cookiesSet = {}
env.Connection = function()
  return {
    setCookie = function(_, c) cookiesSet[#cookiesSet + 1] = c end,
    getCookies = function() return table.concat(cookiesSet, "; ") end,
  }
end
-- Plugin uses global Connection(); mm_shim must expose Connection = env.Connection
-- If shim already provides Connection, override env.connection after ensure:
env.connection = nil
local fakeConn = {
  setCookie = function(_, c) cookiesSet[#cookiesSet + 1] = c end,
  getCookies = function() return table.concat(cookiesSet, "; ") end,
}
env.Connection = function() return fakeConn end
assert(env.applyAmazonAwsWafCaptchaToken("waf-token-stub") == nil)
local joined = table.concat(cookiesSet, " ")
assert(joined:find("aws%-waf%-token=waf%-token%-stub", 1),
  "token must be stored as aws-waf-token cookie, got: " .. joined)

-- Integration: step1 challenge → step2 token → softblock gone → no A, pending cleared
env.LocalStorage = { loginCounter = 0, patcher = {} }
local phase = "softblock"
env.connectShop = function()
  if phase == "softblock" then
    return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
  end
  return mm.HTML([[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span>
<form action="/gp/css/order-history"><select name="timeFilter">
<option value="last30">30</option></select></form></body></html>]])
end
env.resolveAkamaiInterstitial = function(page) return page, nil end
env.enterOrderList = function() end
env.discoverAmazonSubAccounts = function() return true, nil end

local ch = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, true)
assert(type(ch) == "table", "step1 must return challenge")
assert(env.LocalStorage.awsWafCaptchaPending == true)

phase = "ok"
local step2 = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 2,
  {"waf-token-stub"}, true)
assert(step2 == nil or type(step2) == "table",
  "step2 after token must not be softblock A string, got: " .. tostring(step2))
assert(env.LocalStorage.awsWafCaptchaPending ~= true,
  "pending must clear after token apply")

-- Empty token on step2 → A, claim not started
env.LocalStorage = { loginCounter = 0, patcher = {}, awsWafCaptchaPending = true }
phase = "softblock"
env.enterOrderList = function()
  error("enterOrderList must not run when WAF token missing")
end
local empty = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 2,
  {""}, true)
assert(type(empty) == "string" and empty:find("Bot-Prüfung", 1, true),
  "empty WAF token must return A")
```

Wenn der bestehende Login nach Softblock-Wegfall sofort Claim/Passwort erwartet und ohne weitere Mocks fehlschlägt: Step2-Erfolg als „nicht A-String und Pending cleared“ werten **oder** `connectShop`/`getOrders`-Pfad so stubben, dass `InitializeSession2` mit `nil` endet (wie `test_cookie_import.lua`).

- [ ] **Step 2: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 3: Implementieren**

Connection-Bootstrap aus `connectShopRaw` extrahieren (kein leerer `if connection == nil`):

```lua
function ensureAmazonShopConnection()
  if connection ~= nil then
    return
  end
  connection = Connection()
  if type(LocalStorage) ~= "table" or type(LocalStorage.cookies) ~= "string" then
    return
  end
  for i in string.gmatch(LocalStorage.cookies, '([^; ]+)') do
    if i:sub(1, #'ap-fid=') ~= 'ap-fid=' and i:sub(-#'=deleted') ~= '=deleted' then
      connection:setCookie(i..'; Domain='..const.domain
        ..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
    end
  end
end

function applyAmazonAwsWafCaptchaToken(token)
  if type(token) ~= "string" or token == "" then
    return amazonAwsWafSoftblockMessage()
  end
  ensureAmazonShopConnection()
  connection:setCookie(
    "aws-waf-token=" .. token
      .. "; Domain=" .. const.domain
      .. "; Path=/; Secure")
  return nil
end
```

`connectShopRaw`: bestehenden `if connection == nil then … end`-Block durch `ensureAmazonShopConnection()` ersetzen (Verhalten identisch).

Resume **oben** in `InitializeSession2` (nach Attribute-Apply, vor neuem Step-1-Login), nur wenn kein `subAccountScan.await_mfa`:

```lua
if type(LocalStorage) == "table"
    and LocalStorage.awsWafCaptchaPending == true
    and step > 1 then
  local applyErr = applyAmazonAwsWafCaptchaToken(credentials[1])
  LocalStorage.awsWafCaptchaPending = nil
  if applyErr ~= nil then
    MM.printStatus(applyErr)
    return applyErr
  end
  html = connectShop("GET", baseurl)
  local resolvedHtml, akamaiError = resolveAkamaiInterstitial(html)
  if akamaiError ~= nil then
    return "Amazon: "..akamaiError
  end
  html = resolvedHtml
  local again = takeAwsWafCaptchaChallengeOrSoftblockMessage(html, baseurl, false)
  if type(again) == "string" then
    MM.printStatus(again)
    return again
  end
  -- fall through into the same post-start path as a clean homepage
  -- (enterOrderList / claim / password). Do not set awsWafCaptchaPending again.
end
```

Fall-through: bestehenden Code nach erfolgreichem Startseiten-GET wiederverwenden (nicht duplizieren) — z.B. gemeinsames `continueAmazonLoginAfterStartPage(interactive)` extrahieren, das Order-List + Softblock-Check + Claim enthält; Step 1 und WAF-Resume rufen es auf.

- [ ] **Step 4: Tests**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
```

- [ ] **Step 5: Commit**

```bash
git add amazon-bestellungen.lua test/test_aws_waf_captcha_challenge.lua \
  test/measure_diff_crap.lua test/mm_shim.lua
git commit -m "$(cat <<'EOF'
Apply AWS WAF captcha token once and resume Amazon login.

EOF
)"
```

---

### Task 6: README, Version 2.08, Regression

**Files:**
- Modify: `README.md`
- Modify: `amazon-bestellungen.lua` (`WebBanking.version = 2.08`)
- Modify: `docs/superpowers/specs/2026-10-26-amazon-waf-challenge-cookie-fallback-design.md` (Status: in Umsetzung → nach Merge umgesetzt)

- [ ] **Step 1: README**

Absätze:

1. Softblock → Dialog „Amazon Bot-Prüfung“ (C), wenn MoneyMoney Captcha anzeigen kann
2. Sonst / Hintergrundabruf → Meldung A (Helper + `COOKIE:…`)
3. Browser-Login allein auf demselben Mac reicht nicht; Cookies müssen importiert werden
4. Nie Cookie-Strings in Issues posten
5. Unterscheidung: Passwort-Dialog ≠ Bot-Prüfung ≠ OTP „Bestätigungscode“

- [ ] **Step 2: Version**

```lua
WebBanking{version  = 2.08,
```

(Beschreibung/README „2.08“ konsistent.)

- [ ] **Step 3: Suite**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
./test/run.sh test/test_claim_collect_signin.lua
./test/run.sh test/selftest.lua
./test/run.sh test/measure_diff_crap.lua
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add README.md amazon-bestellungen.lua \
  docs/superpowers/specs/2026-10-26-amazon-waf-challenge-cookie-fallback-design.md
git commit -m "$(cat <<'EOF'
Release notes for Amazon WAF captcha and COOKIE fallback (2.08).

EOF
)"
```

---

### Task 7: Issue #7 Kommentar (kein Code)

- [ ] Kommentar: Softblock ≠ falsches Passwort; Fix-Pfad C→A→B laut Spec/Plan; Bitte 2.08-beta testen sobald Release-Asset liegt; Session-Angebot optional

Nur GitHub, kein Commit.

---

## Self-Review (Plan vs Spec)

| Spec-Anforderung | Task |
| --- | --- |
| C wenn absolute URL+Sitekey | 3, 4 |
| A wenn nicht / nach Fehlversuch | 2, 4, 5 |
| B COOKIE: | 1, 6 |
| Token Step 2, ein Versuch (`awsWafCaptchaPending`) | 5 |
| interactive=false → A | 4 |
| Dialog-Titel Bot-Prüfung | 4 |
| Kein Claim hinter Softblock | 4, 5 |
| Order-List-Softblock | 4 Test |
| Diff-CRAP neue Helper | 3–5 |
| Nicht-Ziele | eingehalten |

Conformity-Remediation (2026-10-26): Flags vereinheitlicht; Step-2-Tests/Connection-Bootstrap ausgeschrieben; relative URL + urldecode-Fallback entfernt; Worktree/Cherry-Pick; Version fest 2.08.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-26-amazon-waf-challenge-cookie-fallback.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — frischer Subagent pro Task, Review dazwischen

**2. Inline Execution** — Tasks in dieser Session mit `executing-plans`, Checkpoints

Which approach?
