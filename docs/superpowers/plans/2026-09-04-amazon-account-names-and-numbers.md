# Amazon Account Names and Numbers Implementation Plan

> **Status: umgesetzt** (2026-09-04). Autoritative Ist-Semantik:
> `docs/superpowers/specs/2026-09-04-amazon-account-names-and-numbers-design.md`.
> Dieser Plan ist die historische Task-Liste; bei Widerspruch gilt die Spec.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MoneyMoney listet Amazon als Konto `Amazon` (E-Mail-Kontonummer, Sonstiges), Unterkonten als `Amazon <customerName|businessName>` mit Amazon-`customerId`, inkl. korrekter Match-Logik (kein Match-all).

**Architecture:** Reine Hilfen für `customerId`-Parsing und Konto-Rollen-SSOT zuerst (TDD); dann `ListAccounts`/Discovery mit kurzem Switcher-Wechsel; danach Key-Aliase (`emitAccountKey`, Initial-Sync) und Doku. Monolith `amazon-orders.lua` bleibt; keine Dateisplit-Pflicht.

**Tech Stack:** LuaJIT, MoneyMoney WebBanking-Host-Globals, Offline-Harness `test/run.sh` + `test/mm_shim.lua`.

**Spec:** `docs/superpowers/specs/2026-09-04-amazon-account-names-and-numbers-design.md`

## Global Constraints

- Anzeigenamen: Combined=`Amazon`; Personal=`Amazon <customerName>`; Business=`Amazon <businessName>`.
- Kontonummern: Combined=`secUsername`; Subs=`customerId`; kein neues `mix`/`sub:*` in `ListAccounts`.
- `type=AccountTypeOther` für alle Neuangebote; Flags `withTotalSum=false`, `showInDiagrams=false`, `showDailyBalance=false`, `perspective.chart=1`.
- Keine stillen Fallbacks (`sub:*`, Dummy-E-Mail, Match-all für unbekannte Nummern).
- Discovery ohne Order-Harvest; MFA/Auth-Fail und Restore-Fail → Fehler, keine Teilliste.
- Kein Refresh für Alt-Nummern `mix` / `sub:*` / `normal` / … — Neu-Anlage unter *Amazon Bestellungen*.
- Breaking: Nutzer löscht und legt Amazon-Konten neu an (README).
- Tests: `./test/run.sh test/<file>.lua` bzw. Suite-Loop laut `test/README.md`.
- Commits nur mit sinnvoller Message; kein Cursor-Co-Author-Trailer.

## File map

| File | Role |
| --- | --- |
| `amazon-orders.lua` | Parsing, Rollen-SSOT, ListAccounts, Discovery-Wechsel, Keys |
| `test/test_customer_id_parse.lua` | Neu: `customerId` aus HTML |
| `test/test_account_role_ssot.lua` | Neu: Combined/Sub/Legacy/Match-all-Verbot |
| `test/test_list_accounts.lua` | Anpassen: Namen, Nummern, type |
| `test/test_discover_customer_ids.lua` | Neu: Discovery-Fehlerpfade (gemockter Switch) |
| `test/test_account_switcher.lua` / weitere `test_*.lua` | Legacy-Keys / Aufrufe nachziehen |
| `test/fixtures/*` | ggf. `customerId` in Switch-/SPA-Fixtures |
| `README.md` | Neu-Anlage, Namen, Nummern, Sonstiges |
| `docs/superpowers/specs/2026-08-31-*.md`, `2026-08-25-amazon-subaccounts-*.md` | Historisch + Verweis |
| `docs/superpowers/specs/2026-09-04-amazon-account-names-and-numbers-design.md` | Status → Implementiert (am Ende) |

---

### Task 1: `customerId` aus HTML parsen

**Files:**
- Create: `test/test_customer_id_parse.lua`
- Modify: `amazon-orders.lua` (neue Funktion nahe anderen HTML-Parsern, z. B. nach `firstNonEmpty`)
- Test: `test/test_customer_id_parse.lua`
- Optional fixture: bestehendes `test/fixtures/ab_your_orders_spa.html` nutzen

**Interfaces:**
- Produces: `parseAmazonCustomerIdFromHtml(htmlOrText) → string|nil`
  Akzeptiert String oder Node mit `:html()`/Rohtext; erkennt `customerId` / `customerID` in JS (`iss`, JSON-ähnliche Snippets). Gültig: `^A[A-Z0-9]+$` (Amazon-Customer-Id-Form). Sonst `nil`.

- [ ] **Step 1: Failing test schreiben**

```lua
-- test/test_customer_id_parse.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")

local fromFixture = env.parseAmazonCustomerIdFromHtml(
  mm.readFixture("ab_your_orders_spa.html"))  -- oder Datei-Inhalt laden wie andere Tests
assert(fromFixture == "A3PQNNWE23MR9U")

assert(env.parseAmazonCustomerIdFromHtml('var iss={customerId:"A1EXAMPLEID22"};') == "A1EXAMPLEID22")
assert(env.parseAmazonCustomerIdFromHtml('{"customerID":"A9ZZZZZZZZZZZ"}') == "A9ZZZZZZZZZZZ")
assert(env.parseAmazonCustomerIdFromHtml("<html></html>") == nil)
assert(env.parseAmazonCustomerIdFromHtml(nil) == nil)
assert(env.parseAmazonCustomerIdFromHtml('customerId:"not-an-id"') == nil)
print("test_customer_id_parse OK")
```

Hinweis: Fixture-Laden wie in bestehenden Tests (`io.open` / Hilfsfunktion im Test) — `mm.readFixture` nur verwenden, wenn der Shim das schon hat; sonst:

```lua
local function readFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "r"))
  local s = f:read("*a"); f:close(); return s
end
```

- [ ] **Step 2: Test ausführen (erwarteter Fail)**

Run: `./test/run.sh test/test_customer_id_parse.lua`
Expected: Fail (`parseAmazonCustomerIdFromHtml` nil/undefined)

- [ ] **Step 3: Minimale Implementierung**

```lua
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
```

- [ ] **Step 4: Test grün**

Run: `./test/run.sh test/test_customer_id_parse.lua`
Expected: `test_customer_id_parse OK`

- [ ] **Step 5: Commit**

```bash
git add test/test_customer_id_parse.lua amazon-orders.lua
git commit -m "$(cat <<'EOF'
Add Amazon customerId HTML parser for account numbers.

EOF
)"
```

---

### Task 2: Konto-Rollen-SSOT (Combined / Sub / Legacy / kein Match-all)

**Files:**
- Create: `test/test_account_role_ssot.lua`
- Modify: `amazon-orders.lua` — `isCombinedMoneyMoneyAccount`, `orderMatchesMoneyMoneyAccount`, `harvestPriorityKindFromAccountNumber`; Hilfen `moneyMoneyAccountKind`, `combinedAccountNumberFromSession` falls sinnvoll
- Test: `test/test_account_role_ssot.lua`

**Interfaces:**
- Consumes: `LocalStorage.discoveredSubAccounts`, global `secUsername` (Session)
- Produces:
  - `isCombinedMoneyMoneyAccount(accountNumber) → bool`
    true nur bei: `nil`/`''` (Legacy), `"mix"`, oder `accountNumber == secUsername`
  - `moneyMoneyAccountKind(accountNumber) → "personal"|"business"|nil`
    Lookup Discovery nach `accountNumber`; Legacy `"sub:personal"` / `"sub:business"`
  - `harvestPriorityKindFromAccountNumber(accountNumber) → kind|nil`
    Combined → `nil`; sonst `moneyMoneyAccountKind`
  - `orderMatchesMoneyMoneyAccount(order, accountNumber) → bool`
    Combined → true (alle Orders); Sub → `order.subAccountKind == kind` nach Backfill; **unbekannte Nummer → false** (nicht true)

- [ ] **Step 1: Failing test**

```lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-orders.lua")
env.LocalStorage = {}
env.secUsername = "user@example.com"

assert(env.isCombinedMoneyMoneyAccount("user@example.com") == true)
assert(env.isCombinedMoneyMoneyAccount("mix") == true)
assert(env.isCombinedMoneyMoneyAccount(nil) == true)
assert(env.isCombinedMoneyMoneyAccount("A3PERSONALID01") == false)
assert(env.isCombinedMoneyMoneyAccount("sub:personal") == false)

env.LocalStorage.discoveredSubAccounts = {
  { kind = "personal", label = "Test User", accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", accountNumber = "A3BUSINESSID02" },
}
assert(env.harvestPriorityKindFromAccountNumber("A3PERSONALID01") == "personal")
assert(env.harvestPriorityKindFromAccountNumber("A3BUSINESSID02") == "business")
assert(env.harvestPriorityKindFromAccountNumber("user@example.com") == nil)
assert(env.harvestPriorityKindFromAccountNumber("sub:personal") == "personal")
assert(env.harvestPriorityKindFromAccountNumber("unknown-id") == nil)

local biz = { subAccountKind = "business" }
assert(env.orderMatchesMoneyMoneyAccount(biz, "user@example.com") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "A3BUSINESSID02") == true)
assert(env.orderMatchesMoneyMoneyAccount(biz, "A3PERSONALID01") == false)
assert(env.orderMatchesMoneyMoneyAccount(biz, "unknown-id") == false)
print("test_account_role_ssot OK")
```

- [ ] **Step 2: Run → FAIL** (aktuell ist `A3PERSONALID01` combined / unknown match-all)

Run: `./test/run.sh test/test_account_role_ssot.lua`

- [ ] **Step 3: Implement SSOT**

Ersetze die drei Funktionen gemäß Spec-Tabelle. Beispielkern:

```lua
function isCombinedMoneyMoneyAccount(accountNumber)
  if accountNumber == nil or accountNumber == '' then
    return true
  end
  local num=tostring(accountNumber)
  if num == "mix" then
    return true
  end
  if type(secUsername) == 'string' and secUsername ~= '' and num == secUsername then
    return true
  end
  return false
end

function moneyMoneyAccountKind(accountNumber)
  if type(accountNumber) ~= 'string' or accountNumber == '' then
    return nil
  end
  local legacy=string.match(accountNumber, "^sub:(.+)$")
  if legacy == "personal" or legacy == "business" then
    return legacy
  end
  local discovered=LocalStorage and LocalStorage.discoveredSubAccounts
  if type(discovered) == 'table' then
    for _,sub in ipairs(discovered) do
      if type(sub) == 'table' and sub.accountNumber == accountNumber
          and (sub.kind == "personal" or sub.kind == "business") then
        return sub.kind
      end
    end
  end
  return nil
end

function harvestPriorityKindFromAccountNumber(accountNumber)
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return nil
  end
  return moneyMoneyAccountKind(accountNumber)
end

function orderMatchesMoneyMoneyAccount(order, accountNumber)
  if type(order) ~= 'table' then
    return false
  end
  if isCombinedMoneyMoneyAccount(accountNumber) then
    return true
  end
  local wantKind=moneyMoneyAccountKind(accountNumber)
  if wantKind == nil then
    return false
  end
  backfillSubAccountKind(order)
  return order.subAccountKind == wantKind
end
```

- [ ] **Step 4: Tests grün**

Run: `./test/run.sh test/test_account_role_ssot.lua`
Dann gezielt bestehende Tests, die Combined/`sub:` prüfen:
`./test/run.sh test/test_list_accounts.lua` (noch rot wegen alter Erwartungen — ok bis Task 3)
`./test/run.sh test/test_empty_emit_misaligned.lua` u. a. bei Failures fixen, **ohne** Match-all zurückzubringen.

- [ ] **Step 5: Commit**

```bash
git add test/test_account_role_ssot.lua amazon-orders.lua
git commit -m "$(cat <<'EOF'
Rewrite Amazon account role matching for email and customerId keys.

EOF
)"
```

---

### Task 3: `ListAccounts` Namen + Nummern + Sonstiges

**Files:**
- Modify: `amazon-orders.lua` — `makeListAccountEntry`, `rememberDiscoveredSubAccounts`, `listAccountDisplayLabel`, `combinedAccountListLabel` (entfernen oder nur Legacy), `ListAccounts`, `subAccountNumberForKind`
- Modify: `test/test_list_accounts.lua`
- Test: `test/test_list_accounts.lua`

**Interfaces:**
- Consumes: `secUsername`, `LocalStorage.discoveredSubAccounts` mit `accountNumber=customerId`, `customerName`/`businessName`/`label`
- Produces: `ListAccounts` → Combined `{name="Amazon", accountNumber=secUsername, type=AccountTypeOther, …}`; Subs nur wenn `#discovered` mit ≥2 vollständigen Einträgen; Namen `Amazon <…>`

- [ ] **Step 1: Tests umschreiben (failing against old behavior)**

In `test/test_list_accounts.lua`:

```lua
env.secUsername = "user@example.com"
env.LocalStorage = {}
local onlyShared = env.ListAccounts({})
assert(#onlyShared == 1)
assert(onlyShared[1].name == "Amazon")
assert(onlyShared[1].accountNumber == "user@example.com")
assert(onlyShared[1].type == "AccountTypeOther")

env.rememberDiscoveredSubAccounts({
  { kind = "personal", label = "Test User", customerName = "Test User",
    accountNumber = "A3PERSONALID01" },
  { kind = "business", label = "Example GmbH", businessName = "Example GmbH",
    accountNumber = "A3BUSINESSID02" },
})
local listed = env.ListAccounts({})
assert(#listed == 3)
local byNum = {}
for _, a in ipairs(listed) do byNum[a.accountNumber] = a end
assert(byNum["user@example.com"].name == "Amazon")
assert(byNum["A3PERSONALID01"].name == "Amazon Test User")
assert(byNum["A3BUSINESSID02"].name == "Amazon Example GmbH")
assert(byNum["user@example.com"].type == "AccountTypeOther")
assert(byNum["A3PERSONALID01"].type == "AccountTypeOther")
assert(byNum["mix"] == nil)
assert(byNum["sub:personal"] == nil)
```

Zusätzlich: Eintrag ohne `accountNumber`/`customerId` wird von `rememberDiscoveredSubAccounts` **nicht** gespeichert; `ListAccounts` dann nur Combined.

Fehlende `secUsername`: `ListAccounts` wirft/errort (String oder `error`) — im Test per `pcall` prüfen.

- [ ] **Step 2: Run → FAIL**

Run: `./test/run.sh test/test_list_accounts.lua`

- [ ] **Step 3: Implement**

- `rememberDiscoveredSubAccounts`: nur wenn `kind` und nicht-leerer `accountNumber` (customerId) und Anzeigename-Teil (`customerName` bei personal, `businessName` bei business, sonst kein Insert). `label` weiter für Backfill speichern.
- `makeListAccountEntry(name, owner, accountNumber, knownAccounts)` — `name` bereits voller Anzeigename (nicht immer `"Amazon "..suffix`).
- `ListAccounts`: Combined-Nummer = `secUsername`; Fehler wenn fehlend. Subs wenn `#discoveredSubAccounts > 1` (nur vollständige Einträge zählen).
- `subAccountNumberForKind`: aus Discovery; **kein** Default `"sub:"..kind` für neue Pfade — Rückgabe `nil` wenn unbekannt (Legacy-Aufrufer prüfen). Optional Legacy-Default nur wenn explizit Altkonto: Spec sagt kein Fallback für Neuangebote; für Harvest-Legacy darf `"sub:"..kind` bleiben, wenn kein Discovery-Hit.

- [ ] **Step 4: Tests grün**

Run: `./test/run.sh test/test_list_accounts.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/test_list_accounts.lua amazon-orders.lua
git commit -m "$(cat <<'EOF'
Offer Amazon ListAccounts with email and customerId account numbers.

EOF
)"
```

---

### Task 4: Discovery wechselt und liest `customerId`

**Files:**
- Modify: `amazon-orders.lua` — `discoverAmazonSubAccounts`, ggf. `enrichDiscoveredSubAccountsWithCustomerIds`
- Create: `test/test_discover_customer_ids.lua`
- Modify: `test/test_account_setup_no_harvest.lua` falls Discovery-Mocks betroffen
- Test: `test/test_discover_customer_ids.lua`

**Interfaces:**
- Consumes: `openAccountSwitcherEmbed`, `parseAccountSwitcher`, `switchAmazonSubAccount` / `ensureAmazonSubAccountSession`, `parseAmazonCustomerIdFromHtml`, `sessionMatchesSubAccountKind`
- Produces: `discoverAmazonSubAccounts(...)` füllt `discoveredSubAccounts` inkl. `accountNumber=customerId` oder Fehlerstring gemäß Spec-Tabelle

- [ ] **Step 1: Failing tests für Pfade**

```lua
-- Happy path: mock switcher + pages with two customerIds
-- Partial IDs: only combined later via ListAccounts (discovered length < 2 complete)
-- Auth fail: discover returns error string, discovered not half-applied for ListAccounts
-- Restore fail: error
```

Konkret Happy-Path-Skizze (Mocks analog `test_account_switcher.lua` / `test_account_setup_no_harvest.lua`):

1. Stub `openAccountSwitcherEmbed` → Fixture-HTML mit personal+business.
2. Stub Wechsel so, dass nach personal-HTML `A3PERSONAL…`, nach business-HTML `A3BUSINESS…` geparst wird.
3. `discoverAmazonSubAccounts()` → 2 Einträge mit IDs.
4. Ausgangskind wiederherstellen wurde aufgerufen (Zähler/Flag im Stub).

Auth-Fail: Stub liefert `needsMfa` → Funktion returns Fehlerstring; `LocalStorage.discoveredSubAccounts` leer oder vorheriger Stand, jedenfalls keine neuen unvollständigen IDs für ListAccounts.

- [ ] **Step 2: Run → FAIL**

Run: `./test/run.sh test/test_discover_customer_ids.lua`

- [ ] **Step 3: Implement Discovery**

Ablauf laut Spec:

1. Aktives Kind merken (`sessionMatchesSubAccountKind` auf aktuellem `html` / nach leichtem GET falls nötig).
2. Switcher parsen.
3. Pro Option: `ensureAmazonSubAccountSession(kind)` → bei Fehler return Fehlerstring.
4. Seite laden (aktuelles `html` oder Shop-Home) → `parseAmazonCustomerIdFromHtml` → an Option hängen.
5. Restore Ausgangskind; bei Fehler return Fehlerstring.
6. `rememberDiscoveredSubAccounts` nur mit Optionen, die `customerId` und Namensfeld haben.

Kein `getOrders` / ABA / Filter-Harvest in diesem Pfad.

- [ ] **Step 4: Tests + Setup-Test**

Run:
`./test/run.sh test/test_discover_customer_ids.lua`
`./test/run.sh test/test_account_setup_no_harvest.lua`
Expected: PASS; Setup weiterhin ohne Order-Harvest.

- [ ] **Step 5: Commit**

```bash
git add test/test_discover_customer_ids.lua test/test_account_setup_no_harvest.lua amazon-orders.lua
git commit -m "$(cat <<'EOF'
Discover Amazon customerIds via short sub-account switches.

EOF
)"
```

---

### Task 5: Key-Inventar (emit / Initial-Sync / Floating)

**Files:**
- Modify: `amazon-orders.lua` — `emitAccountKey`, `initialSyncSubAccountsNotYetRefreshed`, Stellen mit hartem `"mix"` laut Spec-Inventar
- Modify: betroffene Tests (`test_initial_sync_*.lua`, `test_floating_ausgleich.lua`, `test_mix_scan_round_robin.lua`, …)
- Test: Suite-Stichprobe + geänderte Dateien

**Interfaces:**
- `emitAccountKey(accountNumber)`: `nil`/`''` → wenn `secUsername` gesetzt diese E-Mail, sonst Legacy `"mix"`
- Combined-Refresh zählt als Initial-Sync-Erfüllung für `emitAccountKey(secUsername)` **oder** Legacy `"mix"`

- [ ] **Step 1: Failing/angepasste Asserts**

In Initial-Sync-Tests Combined-Konto mit `accountNumber = "user@example.com"` statt `"mix"` anlegen; Legacy-Fall `"mix"` behalten.

- [ ] **Step 2: Run betroffene Tests → Failures notieren**

```bash
./test/run.sh test/test_initial_sync_after_setup.lua
./test/run.sh test/test_mix_scan_round_robin.lua
./test/run.sh test/test_floating_ausgleich.lua
```

- [ ] **Step 3: Keys umbauen**

```lua
function emitAccountKey(accountNumber)
  if accountNumber == nil or accountNumber == '' then
    if type(secUsername) == 'string' and secUsername ~= '' then
      return secUsername
    end
    return "mix"
  end
  return tostring(accountNumber)
end
```

`initialSyncSubAccountsNotYetRefreshed`: Combined erfüllt Sync, wenn `refreshed[emitAccountKey(secUsername)]` oder `refreshed["mix"]` gesetzt.

Weitere Härtungen nur an Inventar-Stellen aus der Spec (keine Scope-Creep-Refactors).

- [ ] **Step 4: Suite**

```bash
for test_file in test/test_*.lua; do ./test/run.sh "$test_file" || exit 1; done
```

Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add amazon-orders.lua test/
git commit -m "$(cat <<'EOF'
Align Amazon emit and initial-sync keys with email account numbers.

EOF
)"
```

---

### Task 6: Doku und Spec-Status

**Files:**
- Modify: `README.md` (Konten anlegen, Update-Abschnitt, Sonstiges)
- Modify: `docs/superpowers/specs/2026-08-31-amazon-combined-account-name-design.md` — Status historisch + Verweis
- Modify: `docs/superpowers/specs/2026-08-25-amazon-subaccounts-listaccounts-design.md` — Neuangebote-Keys historisch + Verweis
- Modify: `docs/superpowers/specs/2026-09-04-amazon-account-names-and-numbers-design.md` — Status **Implementiert**

- [ ] **Step 1: README anpassen**

Ersetzen der Abschnitte zu Namen/`mix`/`Sonstige`:

- Gemeinsames Konto: Name `Amazon`, Kontonummer = Login-E-Mail.
- Persönlich: `Amazon <Name>`, Kontonummer = Amazon-Kunden-ID.
- Geschäftlich: `Amazon <Firmenname>`, Kontonummer = Amazon-Kunden-ID.
- Kontoart Sonstiges; nach Update **löschen und neu anlegen** (Kreditkarte bleibt sonst stehen).

- [ ] **Step 2: Historische Specs markieren**

Beispiel Header-Zusatz:

```markdown
Status: **Historisch / überholt** durch
`2026-09-04-amazon-account-names-and-numbers-design.md`.
```

- [ ] **Step 3: Design-Spec Status → Implementiert**

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/
git commit -m "$(cat <<'EOF'
Document Amazon account display names and customerId account numbers.

EOF
)"
```

---

## Spec coverage (self-review)

| Spec-Anforderung | Task |
| --- | --- |
| Namen Amazon / Amazon+customerName / Amazon+businessName | 3 |
| Nummern E-Mail / customerId | 3, 4 |
| Discovery Ansatz A + Restore MUST | 4 |
| Discovery-Fehlerpfade (Teil-ID, MFA, Restore) | 4 |
| SSOT Combined/Sub/Legacy, kein Match-all | 2 |
| Pflicht-Rewrite orderMatches/harvestPriority/isCombined | 2 |
| Key-Inventar emit/initialSync/floating | 5 |
| AccountTypeOther + Flags + Tests | 3 |
| Breaking README + historische Specs | 6 |
| customerId-Parser | 1 |

## Placeholder scan

Keine TBD/TODO-Schritte; konkrete Testskizzen und Funktionsrümpfe vorhanden.

## Type / name consistency

- `parseAmazonCustomerIdFromHtml`
- `moneyMoneyAccountKind`
- `rememberDiscoveredSubAccounts` erwartet `accountNumber` (= customerId) an Optionen
- Combined-Key = `secUsername` durchgängig in Tasks 2–5
