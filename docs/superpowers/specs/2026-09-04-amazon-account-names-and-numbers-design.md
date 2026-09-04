# Amazon: Anzeigenamen und Kontonummern

Datum: 2026-09-04

Status: **Implementiert** (2026-09-04). Implementierungsplan:
`docs/superpowers/plans/2026-09-04-amazon-account-names-and-numbers.md`.

## Ziel

- Gemeinsames Konto: Anzeigename nur **Amazon**.
- Persönlich: **Amazon** + Switcher-`customerName`.
- Geschäftlich: **Amazon** + Switcher-`businessName` (gleiche Form wie privat).
- Kontonummern sinnvoll und stabil:
  - Gemeinsam: Login-E-Mail (`secUsername`).
  - Persönlich / Geschäftlich: Amazon-`customerId` der jeweiligen Session.
- Gemeinsames Konto (und die Unterkonten) als MoneyMoney-Kontoart
  **Sonstiges** (`AccountTypeOther`), inkl. der bestehenden Flags gegen
  Gesamtsumme/Diagramme.
- Breaking: Nutzer löschen Amazon-Konten und legen neu an. Alte Nummern
  `mix` / `sub:personal` / `sub:business` nur noch Legacy-Refresh.

## Nicht-Ziele

- Keine stille Migration der Kontonummer in MoneyMoney (App unterstützt das
  nicht zuverlässig).
- Kein Order-Harvest während der Kontensuche.
- Keine Änderung der Buchungslogik (Ausgleich, Storno, ABA), außer soweit
  Konto-Keys und Match-Hilfen umgebaut werden müssen (siehe unten).

## Anzeigenamen

| Konto | `name` in `ListAccounts` | Quelle |
| --- | --- | --- |
| Gemeinsam | `Amazon` | fest |
| Persönlich | `Amazon <customerName>` | Switcher `data-test-id="customerName"` |
| Geschäftlich | `Amazon <businessName>` | Switcher `data-test-id="businessName"` |

- Feste Suffixe „Alle Konten“ / „Persönlich“ / „Geschäftlich“ entfallen für
  Neuangebote.
- Fehlt `customerName` bzw. `businessName` nach Trim: Unterkonto **nicht**
  anbieten (kein stiller Fallback auf generische Labels).
- Kombinierter Name `Persönliches Konto + Firma` entfällt.

## Kontonummern

| Konto | `accountNumber` | Quelle |
| --- | --- | --- |
| Gemeinsam | Login-E-Mail | `secUsername` aus der Session |
| Persönlich | Amazon-`customerId` | Seiten-JS der Personal-Session |
| Geschäftlich | Amazon-`customerId` | Seiten-JS der Business-Session |

`discoveredSubAccounts` speichert nur Unterkonten
`{kind, label, customerName|businessName, accountNumber=customerId}`.
Das gemeinsame Konto wird **nicht** als Discovery-Eintrag mit Rolle
„combined“ persistiert.

### Discovery (Ansatz A)

`discoverAmazonSubAccounts` ohne Order-Harvest; darf kurz Unterkonten
wechseln, um je Session die `customerId` zu lesen:

1. Ausgangssession merken (welches `kind` aktiv ist, soweit erkennbar).
2. Switcher öffnen und Optionen parsen (wie bisher).
3. Für jedes erkannte Unterkonto: Wechsel → `customerId` lesen → speichern.
4. **MUST:** Session wieder auf die gemerkte Ausgangssession stellen. Scheitert
   der Rückwechsel: Discovery mit klarer Fehlermeldung abbrechen (kein
   „weiter mit falscher Session“).
5. `ListAccounts` liefert nur Unterkonten mit vollständigem `kind`,
   Anzeigename-Teil und `customerId`.
6. Fehlt `secUsername` für das gemeinsame Konto: `ListAccounts` mit klarer
   Fehlermeldung abbrechen (kein Dummy/`mix`).

### Discovery-Fehlerpfade (Muss)

| Situation | `ListAccounts`-Ergebnis |
| --- | --- |
| Switcher leer / ein Konto; E-Mail vorhanden | nur gemeinsames Konto (E-Mail) |
| Switcher ≥2; alle IDs + Namen ok | gemeinsam + vollständige Subs |
| Switcher ≥2; eine oder mehrere IDs/Namen fehlen, aber kein Auth-Abbruch | nur gemeinsames Konto; unvollständige Subs **weglassen** (kein `sub:*`-Fallback) |
| MFA/Auth beim Discovery-Wechsel scheitert (nach einmaliger Credential-Antwort wie Refresh) | **Fehler** zurückgeben; keine Kontenliste mit Teilstand |
| Rückwechsel zur Ausgangssession scheitert | **Fehler** (siehe Schritt 4) |

## Interne Erkennung (Muss-Rewrite)

Heutiger Stand ist mit E-Mail/`customerId` **falsch**:
`isCombinedMoneyMoneyAccount` behandelt jede Nummer ohne Prefix `sub:` als
Combined; `orderMatchesMoneyMoneyAccount` liefert bei unbekanntem Key
faktisch „match all“. Das darf nach dem Umbau **nicht** mehr gelten.

### SSOT

| Rolle | Erkennung |
| --- | --- |
| Combined (neu) | `accountNumber == secUsername` (Login-E-Mail der Session) |
| Combined (Legacy) | `accountNumber == "mix"` oder leere/`nil`-Nummer wie bisher für Altpfade |
| Personal (neu) | Eintrag in `discoveredSubAccounts` mit `accountNumber` und `kind=="personal"` |
| Business (neu) | Eintrag in `discoveredSubAccounts` mit `accountNumber` und `kind=="business"` |
| Personal (Legacy) | `accountNumber == "sub:personal"` |
| Business (Legacy) | `accountNumber == "sub:business"` |

Unbekannte `accountNumber`: **kein** Match-all. Kind-Hilfen liefern `nil`;
Order-Filter für reine Unterkonten matchen nur bei bekanntem `kind`.

### Pflicht-Rewrite

Mindestens diese Hilfen müssen die SSOT-Tabelle umsetzen (nicht nur
`isCombinedMoneyMoneyAccount`):

- `isCombinedMoneyMoneyAccount`
- `orderMatchesMoneyMoneyAccount`
- `harvestPriorityKindFromAccountNumber`
- `listAccountDisplayLabel` / `subAccountNumberForKind` (neue Nummern aus
  Discovery, Legacy-Aliase behalten)
- Aufrufer, die heute `^sub:` oder hart `"mix"` annehmen

### Key-Inventar (Pflicht beim Umbau)

| Bereich | Heute | Soll |
| --- | --- | --- |
| `ListAccounts` | `"mix"`, `sub:*` | E-Mail, `customerId` |
| `emitAccountKey(nil/'' )` | `"mix"` | Combined-Key = E-Mail wenn bekannt; Legacy `"mix"` nur für Alt-Emit-Marker |
| `legacyEmitAccountKeys` | enthält `"mix"` | `"mix"` bleibt für Alt-Cache; neu E-Mail parallel wo nötig |
| `initialSyncRefreshedAccounts` / Check auf `mix` | hart `"mix"` | Combined-E-Mail + Legacy `"mix"` |
| `floatingBalanceAnchorByAccount` | via `emitAccountKey` | gleiche Key-Semantik |
| `balancesByPeriod` | via `emitAccountKey` | gleiche Key-Semantik |
| Order-`emittedAccounts` / `isOrderEmittedForAccount(..., "mix")` | hart `"mix"` | Combined-Key + Legacy |
| Tests mit `"mix"` / `sub:*` | fest verdrahtet | neue Keys; Legacy-Fälle behalten |

## Kontoart Sonstiges

Bekannter Ist-Zustand: Plugin setzt bereits `type=AccountTypeOther`, aber das
gemeinsame Live-Konto kann in MoneyMoney als **Kreditkarte** stehen (manuell
oder beim Anlegen überschrieben; Refresh ändert die Art bestehender Konten
nicht).

Sicherstellen:

1. `ListAccounts` setzt für **alle** angebotenen Konten explizit
   `type=AccountTypeOther` (gemeinsam und Unterkonten).
2. Weiterhin `withTotalSum=false`, `showInDiagrams=false`,
   `showDailyBalance=false`, `perspective.chart=1`.
3. Tests prüfen `type` für das gemeinsame Konto und die Unterkonten.
4. README: nach dem Update Amazon-Konten **löschen und neu anlegen**, sonst
   bleibt eine manuell/alt gesetzte Kontoart (z. B. Kreditkarte) erhalten.
5. Kein Codepfad darf `AccountTypeCreditCard` oder eine andere Art setzen.

MoneyMoney-UI kann die Art beim Bestätigen noch überschreiben; das Plugin
kann das nicht verhindern. Nach Neu-Anlage ist der vom Plugin gelieferte
Default **Sonstiges**.

## Breaking / Doku

- README und Update-Abschnitt: neue Namen/Nummern; Neu-Anlage nötig.
- Spezifikation 2026-08-31 (kombinierter Mix-Name) und Teile von
  2026-08-25 (Keys `mix`/`sub:*` für Neuangebote) als historisch markieren bzw.
  auf dieses Dokument verweisen.

## Tests (geplant)

- `ListAccounts`: Name `Amazon` + E-Mail-Kontonummer; `type=AccountTypeOther`.
- Bei zwei Subs: `Amazon <customerName>` / `Amazon <businessName>`, jeweilige
  `customerId`, `type=AccountTypeOther`.
- Unvollständige Discovery (fehlende ID): nur Combined; kein `sub:*`.
- Auth-Fehler in Discovery: Fehler, keine Teilliste.
- `isCombined` / `orderMatches` / `harvestPriorityKind`: E-Mail = combined;
  `customerId` = nur eigenes Kind; unbekannte Nummer ≠ match-all; Legacy
  `mix`/`sub:*` weiter.
- Harvest-/Refresh-Tests auf neue Keys bzw. Legacy-Aliase anpassen.

## Offene Umsetzungshinweise (kein Spec-Blocker)

- Exakter Regex/Selector für `customerId` an Live-HTML verifizieren (Fixture
  `ab_your_orders_spa.html` enthält bereits `customerId`).
