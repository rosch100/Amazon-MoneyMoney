# Amazon WAF Challenge + Cookie Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Softblock vor Claim: wenn möglich native MoneyMoney-AWS-WAF-Captcha (C), sonst klare Bot-Prüfung-Meldung (A) und jederzeit `COOKIE:…`-Import (B); nie irreführendes „Passwort falsch“.

**Architecture:** Softblock- und COOKIE-Basis von `bugfix/claim-challenge-login` (2.06/2.07) übernehmen. Neu: aus Softblock-HTML `challenge.js`-URL + `sitekey` extrahieren, bei `interactive` eine Captcha-Challenge zurückgeben, Token einmal anwenden und Startseite neu laden; sonst kanonische A-Meldung. Plugin bleibt eine Datei `amazon-bestellungen.lua`.

**Tech Stack:** LuaJIT / MoneyMoney WebBanking API (`InitializeSession2` Challenges), `test/run.sh` + `test/mm_shim.lua`, Fixtures unter `test/fixtures/`.

**Spec:** `docs/superpowers/specs/2026-10-26-amazon-waf-challenge-cookie-fallback-design.md`

## Global Constraints

- Single-file plugin: nur `amazon-bestellungen.lua` (+ Tests/README/Fixtures)
- Kein Claim hinter ungelöster Softblock-Seite
- Bot-Prüfung-UI ≠ Passwort-Dialog ≠ OTP-Titel (`Amazon Bot-Prüfung`)
- `COOKIE:`-Blob nie als `secPassword`
- Max. ein C-Versuch pro Login-Lauf; `interactive == false` → kein C, nur A
- Token-Apply: Cookie `aws-waf-token` setzen, dann `GET` Startseite erneut (gegen Live-HTML nachziehen, wenn nötig)
- Keine Secrets/Cookies in Issues oder Fixtures
- Unrelated WIP auf `master` (Claim-Collect-Diff) nicht in diese Arbeit mischen — von `origin/bugfix/claim-challenge-login` branchen oder dort weiterarbeiten
- Offline: `./test/run.sh <script.lua>`

## File map

| File | Responsibility |
| --- | --- |
| `amazon-bestellungen.lua` | Softblock, Extraktion, Challenge, Token-Apply, COOKIE-Import, `InitializeSession2` |
| `test/fixtures/aws_waf_challenge.html` | Softblock mit `challenge.js` ohne Sitekey (→ A) |
| `test/fixtures/aws_waf_softblock_shell.html` | Leere Schale (→ A) |
| `test/fixtures/aws_waf_challenge_sitekey.html` | Softblock mit `token.awswaf.com` + Sitekey (→ C) |
| `test/test_aws_waf_softblock.lua` | Halt / A ohne C |
| `test/test_aws_waf_captcha_challenge.lua` | Extraktion, Challenge-Return, Step-2 Apply, interactive-Guard |
| `test/test_cookie_import.lua` | B (bereits auf Branch) |
| `README.md` | Nutzerhinweise C→A→B |

---

### Task 1: Arbeitsbranch + Softblock/COOKIE-Basis

**Files:**
- Branch from: `origin/bugfix/claim-challenge-login`
- Verify: `test/test_aws_waf_softblock.lua`, `test/test_cookie_import.lua`

**Interfaces:**
- Consumes: bestehende Branch-Funktionen `isAmazonAwsWafChallengePage`, `amazonAwsWafSoftblockMessage`, `establishAmazonSessionFromImportedCookies`
- Produces: sauberer Branch-Stand mit grünen Softblock- und Cookie-Tests

- [ ] **Step 1: Branch anlegen / auschecken**

```bash
git fetch origin
git checkout -B feature/waf-challenge-cookie-fallback origin/bugfix/claim-challenge-login
```

Expected: Working tree auf 2.07-Linie mit Softblock + COOKIE.

- [ ] **Step 2: Basis-Tests laufen lassen**

```bash
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
./test/run.sh test/test_claim_collect_signin.lua
```

Expected: alle PASS. Bei FAIL zuerst Branch-Basis reparieren, nicht C anfangen.

- [ ] **Step 3: Commit nur wenn Checkout lokale Fixes brauchte**

Sonst kein leerer Commit — weiter Task 2.

---

### Task 2: Kanonische A-Meldung (Text angleichen)

**Files:**
- Modify: `amazon-bestellungen.lua` (`amazonAwsWafSoftblockMessage`)
- Modify: `test/test_aws_waf_softblock.lua` (Asserts auf neuen Text)
- Modify: `README.md` (Bot-Prüfung-Absatz, falls abweichend)

**Interfaces:**
- Produces: `amazonAwsWafSoftblockMessage() -> string` (kanonischer Spec-Text)

- [ ] **Step 1: Failing Assert auf kanonischen Wortlaut vorbereiten**

In `test/test_aws_waf_softblock.lua` sicherstellen, dass die Meldung enthält:

- `Bot-Prüfung`
- `COOKIE:`
- `keine falsche Passwort` (oder exakt Spec-Formulierung)

Wenn der Branch-Text schon `COOKIE:` hat, Assert um Spec-Satz ergänzen und rot erwarten.

- [ ] **Step 2: Implementierung**

```lua
function amazonAwsWafSoftblockMessage()
  return "Amazon: Bot-Prüfung nicht gelöst. Bitte im Browser bei amazon.de "
    .."anmelden, Session mit dem MoneyMoney-Helper als COOKIE:… ins "
    .."Passwortfeld legen (siehe README) und erneut abrufen. "
    .."Das ist keine falsche Passwort-Meldung."
end
```

- [ ] **Step 3: Tests**

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
- Modify: `amazon-bestellungen.lua` (neue Helpers nahe Softblock-Block)

**Interfaces:**
- Produces:
  - `extractAmazonAwsWafChallengeScriptUrl(htmlNode) -> string|nil` (absolut, Host enthält `token.awswaf.com`, Pfad/`src` endet mit `challenge.js`)
  - `extractAmazonAwsWafSitekey(htmlNode, scriptUrl) -> string|nil`
  - `amazonAwsWafCaptchaChallengeParts(htmlNode, refererUrl) -> {scriptUrl=, sitekey=, referer=}|nil`

- [ ] **Step 1: Fixture anlegen**

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

(Sitekey darf Dummy sein; kein Live-Token.)

- [ ] **Step 2: Failing tests schreiben**

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

local parts = env.amazonAwsWafCaptchaChallengeParts(
  withKey, "https://www.amazon.de/")
assert(type(parts) == "table", "sitekey fixture must yield challenge parts")
assert(parts.scriptUrl:find("token%.awswaf%.com", 1) and parts.scriptUrl:find("challenge%.js", 1),
  "scriptUrl must be token.awswaf.com challenge.js")
assert(parts.sitekey == "test-sitekey-001", "sitekey must be extracted")
assert(parts.referer == "https://www.amazon.de/", "referer must pass through")

assert(env.amazonAwsWafCaptchaChallengeParts(noKey, "https://www.amazon.de/") == nil,
  "challenge.js without sitekey / wrong host must not enable C")
assert(env.amazonAwsWafCaptchaChallengeParts(shell, "https://www.amazon.de/") == nil,
  "empty softblock shell must not enable C")

print("ok extract")
```

- [ ] **Step 3: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

Expected: FAIL (function nil)

- [ ] **Step 4: Minimal helpers implementieren**

In `amazon-bestellungen.lua` (nach Softblock-Detect):

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
  -- Prefer script src=...token.awswaf.com...challenge.js
  local src = raw:match(
    '[sS][rR][cC]%s*=%s*["\'](https://[^"\']*token%.awswaf%.com[^"\']*challenge%.js[^"\']*)["\']')
  if src == nil then
    local rel = raw:match(
      '[sS][rR][cC]%s*=%s*["\'](/[^"\']*challenge%.js[^"\']*)["\']')
    if rel ~= nil then
      src = absoluteAmazonShopUrl(rel)
    end
  end
  if type(src) ~= "string" or src == "" then
    return nil
  end
  if not src:find("token%.awswaf%.com", 1) then
    return nil
  end
  if not rawHasAwsWafChallengeJs(string.lower(src))
      and not src:find("challenge%.js", 1) then
    return nil
  end
  return src
end

function extractAmazonAwsWafSitekey(htmlNode, scriptUrl)
  if htmlNode == nil then
    return nil
  end
  if type(scriptUrl) == "string" then
    local fromQuery = scriptUrl:match("[?&]sitekey=([^&]+)")
    if fromQuery ~= nil and fromQuery ~= "" then
      return MM.urldecode and MM.urldecode(fromQuery) or fromQuery
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
    refererUrl = baseurl
  end
  return {
    scriptUrl = scriptUrl,
    sitekey = sitekey,
    referer = refererUrl,
  }
end
```

Anpassen an vorhandene `htmlNodeRaw` / `absoluteAmazonShopUrl` / `MM.urlencode` (decode nur wenn im Shim vorhanden — sonst Query-Sitekey unge-decodet lassen und Fixture ohne Encoding testen).

- [ ] **Step 5: Run — expect pass**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 6: Commit**

```bash
git add amazon-bestellungen.lua test/fixtures/aws_waf_challenge_sitekey.html \
  test/test_aws_waf_captcha_challenge.lua
git commit -m "$(cat <<'EOF'
Extract AWS WAF challenge.js URL and sitekey for captcha handoff.

EOF
)"
```

---

### Task 4: Challenge-Tabelle bauen + Softblock-Verzweigung in Login

**Files:**
- Modify: `amazon-bestellungen.lua` (`moneyMoneyAwsWafCaptchaChallenge`, Softblock-Zweig in `InitializeSession2`, Modulflag `awsWafCaptcha1run` / `LocalStorage`)
- Modify: `test/test_aws_waf_captcha_challenge.lua`
- Modify: `test/test_aws_waf_softblock.lua` (unverändert A für no-sitekey)

**Interfaces:**
- Consumes: `amazonAwsWafCaptchaChallengeParts`
- Produces:
  - `moneyMoneyAwsWafCaptchaChallenge(parts) -> table` mit `title`, `challenge` (Script-URL + Query)
  - `takeAwsWafCaptchaChallengeOrSoftblockMessage(htmlNode, refererUrl, interactive) -> table|string`
  - Login Step 1: bei Softblock diese Helper nutzen statt sofort nur Message

Challenge-URL-Form (MoneyMoney-API):

```text
<scriptUrl ohne fragment>?sitekey=<key>&referer=<urlencode(referer)>
```

Kein `type=checkbox`, außer Fixture/HTML legt Checkbox nahe (YAGNI: erst ohne).

- [ ] **Step 1: Tests erweitern**

```lua
-- interactive + sitekey → challenge table, enterOrderList not called
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
assert(type(ch) == "table", "expected captcha challenge table")
assert(ch.title == "Amazon Bot-Prüfung" or (type(ch.title) == "string" and ch.title:find("Bot-Prüfung", 1, true)),
  "title must identify bot check")
assert(type(ch.challenge) == "string"
  and ch.challenge:find("challenge%.js", 1)
  and ch.challenge:find("sitekey=", 1, true)
  and ch.challenge:find("referer=", 1, true),
  "challenge must be awswaf script URL with sitekey+referer")

-- interactive=false → A string, not table
local msg = env.InitializeSession2(
  env.ProtocolWebBanking, "Amazon", 1,
  {"user@example.com", "secret-pw"}, false)
assert(type(msg) == "string" and msg:find("Bot-Prüfung", 1, true),
  "non-interactive must return A message")
```

- [ ] **Step 2: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 3: Implementieren**

```lua
function moneyMoneyAwsWafCaptchaChallenge(parts)
  local base = parts.scriptUrl:match("^([^?#]+)")
  local challengeUrl = base
    .. "?sitekey=" .. MM.urlencode(parts.sitekey)
    .. "&referer=" .. MM.urlencode(parts.referer)
  return {
    title = AMAZON_WAF_BOT_TITLE,
    challenge = challengeUrl,
  }
end

function takeAwsWafCaptchaChallengeOrSoftblockMessage(htmlNode, refererUrl, interactive)
  if not isAmazonAwsWafChallengePage(htmlNode) then
    return nil
  end
  if interactive == true then
    local parts = amazonAwsWafCaptchaChallengeParts(htmlNode, refererUrl)
    if parts ~= nil and awsWafCaptcha1run ~= false then
      awsWafCaptcha1run = false
      return moneyMoneyAwsWafCaptchaChallenge(parts)
    end
  end
  return amazonAwsWafSoftblockMessage()
end
```

In `InitializeSession2` Step 1 (nach Softblock-Detect, statt nur Message):

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

Gleiches Muster nach `enterOrderList`, wenn Softblock erst dort erscheint. `awsWafCaptcha1run=true` zusammen mit `captcha1run`/`mfa1run` zu Session-Start setzen.

`mm_shim`: `MM.urlencode` muss existieren (prüfen; sonst Stub ergänzen).

- [ ] **Step 4: Beide Softblock-Tests**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
```

Expected: PASS (no-sitekey weiter A)

- [ ] **Step 5: Commit**

```bash
git add amazon-bestellungen.lua test/test_aws_waf_captcha_challenge.lua test/mm_shim.lua
git commit -m "$(cat <<'EOF'
Return MoneyMoney AWS WAF captcha challenge when sitekey is present.

EOF
)"
```

---

### Task 5: Step 2 — Token anwenden, Login fortsetzen

**Files:**
- Modify: `amazon-bestellungen.lua` (`applyAmazonAwsWafCaptchaToken`, Step-Handling in `InitializeSession2`)
- Modify: `test/test_aws_waf_captcha_challenge.lua`

**Interfaces:**
- Consumes: Token-String aus `credentials[1]` nach Captcha
- Produces: `applyAmazonAwsWafCaptchaToken(token) -> nil|errorString`; danach Softblock-Check / Weiterlogin

- [ ] **Step 1: Failing tests für Step 2**

```lua
-- After challenge, step>1 with token: set cookie path, softblock gone → continue
-- Mock: first GET softblock+sitekey, after token GET normal home + sign-in flow stubs
-- Empty token → A message, claim not started
```

Konkret:

```lua
local posts = 0
local phase = "softblock"
env.awsWafCaptcha1run = true
env.connectShop = function(method, url)
  if phase == "softblock" then
    return mm.HTML(readFixture("aws_waf_challenge_sitekey.html"))
  end
  -- after token: normal storefront shell (not softblock)
  return mm.HTML([[<!DOCTYPE html><html lang="de-de"><head><title>Amazon.de</title></head>
<body><span class="nav-shortened-name">Ada</span>
<form action="/gp/css/order-history"><select name="timeFilter">
<option value="last30">30</option></select></form></body></html>]])
end
-- InitializeSession2 step1 → challenge table (as Task 4)
-- Then simulate step2:
phase = "ok"
local cookiesBefore = {}
env.connection = {
  setCookie = function(_, c) cookiesBefore[#cookiesBefore+1] = c end,
  getCookies = function() return table.concat(cookiesBefore, "; ") end,
}
-- Prefer testing applyAmazonAwsWafCaptchaToken directly:
assert(env.applyAmazonAwsWafCaptchaToken("") ~= nil, "empty token must error")
assert(env.applyAmazonAwsWafCaptchaToken("waf-token-stub") == nil)
assert(table.concat(cookiesBefore, " "):find("aws%-waf%-token=waf%-token%-stub"),
  "token must be stored as aws-waf-token cookie")
```

Zusätzlich Login-Integration: nach Step-1-Challenge Step-2 mit Token darf `enterOrderList` einmal laufen; ohne Token → A.

- [ ] **Step 2: Run — expect fail**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
```

- [ ] **Step 3: Implementieren**

```lua
function applyAmazonAwsWafCaptchaToken(token)
  if type(token) ~= "string" or token == "" then
    return amazonAwsWafSoftblockMessage()
  end
  if connection == nil then
    -- ensureShopConnection / existing connection bootstrap used elsewhere
  end
  connection:setCookie(
    "aws-waf-token=" .. token
      .. "; Domain=" .. const.domain
      .. "; Path=/; Secure")
  return nil
end
```

In `InitializeSession2` **vor** dem normalen Step-1-Block (oder wenn `awsWafCaptcha1run == false` und Step > 1 und kein MFA/Claims-Resume):

```lua
if awsWafCaptcha1run == false and step > 1 and type(credentials[1]) == "string" then
  local applyErr = applyAmazonAwsWafCaptchaToken(credentials[1])
  if applyErr ~= nil then
    return applyErr
  end
  html = connectShop("GET", baseurl)
  -- akamai resolve…
  local again = takeAwsWafCaptchaChallengeOrSoftblockMessage(html, baseurl, false)
  -- force A on second softblock (interactive false → no second captcha)
  if type(again) == "string" then
    MM.printStatus(again)
    return again
  end
  -- fall through into normal post-start login (order list / claim) without resetting awsWafCaptcha1run to allow another C
end
```

Reihenfolge mit bestehenden Resumes (`await_mfa`, claims verify) abstimmen: WAF-Resume nur wenn kein anderer Auth-Resume aktiv und Flag gesetzt war. Flag-Name konsistent halten (`awsWafCaptchaPending` in `LocalStorage` ist robuster über Steps als nur Modulglobal — **bevorzugt LocalStorage**, analog `subAccountScan`).

Empfehlung Spec-konform:

```lua
LocalStorage.awsWafCaptchaPending = true  -- when returning challenge
-- on step2 apply: clear pending; never store token in LocalStorage
```

- [ ] **Step 4: Tests grün**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
```

- [ ] **Step 5: Commit**

```bash
git add amazon-bestellungen.lua test/test_aws_waf_captcha_challenge.lua
git commit -m "$(cat <<'EOF'
Apply AWS WAF captcha token once and resume Amazon login.

EOF
)"
```

---

### Task 6: README + Versionshinweis + Regression

**Files:**
- Modify: `README.md` (C→A→B Nutzerflow, Unterscheidung Dialoge)
- Modify: `amazon-bestellungen.lua` (`WebBanking.version` → `2.08` wenn Release-bereit; sonst Beta-Beschreibung)
- Modify: Spec-Status optional auf „in Umsetzung“

- [ ] **Step 1: README-Abschnitt**

Kurz:

1. Softblock erkannt → ggf. Dialog „Amazon Bot-Prüfung“ (C)
2. Wenn nicht lösbar / Hintergrundabruf → Meldung A
3. Browser anmelden → Helper → Passwort `COOKIE:…` (B)
4. Nie Cookies in Issues posten
5. Gleicher Mac-Browser allein reicht nicht ohne Cookie-Import

- [ ] **Step 2: Volle relevante Suite**

```bash
./test/run.sh test/test_aws_waf_captcha_challenge.lua
./test/run.sh test/test_aws_waf_softblock.lua
./test/run.sh test/test_cookie_import.lua
./test/run.sh test/test_claim_collect_signin.lua
./test/run.sh test/selftest.lua
```

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add README.md amazon-bestellungen.lua
git commit -m "$(cat <<'EOF'
Document WAF captcha and COOKIE fallback for Amazon login.

EOF
)"
```

---

### Task 7: Issue #7 Kommentar (kein Code)

- [ ] Kurzkommentar: C→A→B laut Spec; Softblock ≠ falsches Passwort; Bitte 2.08-beta testen wenn Release existiert; Session-Angebot optional belassen

Nicht committen — nur GitHub.

---

## Self-Review (Plan vs Spec)

| Spec-Anforderung | Task |
| --- | --- |
| C wenn URL+Sitekey | 3, 4 |
| A wenn nicht | 2, 4 |
| B COOKIE: | 1 (Basis), 6 Docs |
| Token Step 2, ein Versuch | 5 |
| interactive=false → A | 4 |
| Dialog-Unterscheidung Titel | 4 |
| Kein Claim hinter Softblock | 4, 5 Tests |
| Tests Spec-Liste | 3–6 |
| Nicht-Ziele (kein Cookie-Diebstahl, kein Akamai-Replace) | eingehalten |

Keine absichtlichen TBD-Steps; Token-Apply-Cookie-Name bei Live-Abweichung in Task 5 anpassen und Test aktualisieren.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-26-amazon-waf-challenge-cookie-fallback.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — frischer Subagent pro Task, Review dazwischen

**2. Inline Execution** — Tasks in dieser Session mit `executing-plans`, Checkpoints

Which approach?
