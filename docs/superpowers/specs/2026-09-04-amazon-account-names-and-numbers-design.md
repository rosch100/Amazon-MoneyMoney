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
  - Persönlich / Geschäftlich: `AO.` + Amazon-`customerId` **ohne** führendes
    `A` (MoneyMoney-Nummer; Discovery speichert die rohe `customerId`).
    Nackte `customerId` und `AB-<customerId>` enthalten die ID als Substring und
    werden von MoneyMoney mit *Amazon-Kreditkarte* verknüpft → obsolete.
- Gemeinsames Konto (und die Unterkonten) als MoneyMoney-Kontoart
  **Sonstiges** (`AccountTypeOther`), inkl. der bestehenden Flags gegen
  Gesamtsumme/Diagramme.
- Breaking: Nutzer müssen Amazon-Konten löschen und unter *Amazon Bestellungen*
  neu anlegen. Alt-Service `"Amazon"` und Alt-Nummern
  `mix` / `sub:*` / `normal` / `inverse` / `monthly` / `yearly` sowie nackte
  `customerId`s und `AB-…` werden nicht mehr bedient (`SupportsBank` /
  `RefreshAccount` fordern Neu-Anlage).

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
| Persönlich | `AO.` + `customerId` ohne führendes `A` | Seiten-JS der Personal-Session |
| Geschäftlich | `AO.` + `customerId` ohne führendes `A` | Seiten-JS der Business-Session |

`discoveredSubAccounts` speichert nur Unterkonten
`{kind, label, customerName|businessName, accountNumber=customerId}` (roh).
`ListAccounts` setzt die MoneyMoney-Nummer auf `AO.`+`customerId[2…]`. Das
gemeinsame Konto wird **nicht** als Discovery-Eintrag mit Rolle „combined“
persistiert.

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

## Interne Erkennung

### SSOT

| Rolle | Erkennung |
| --- | --- |
| Combined | Login-E-Mail (`secUsername`); leere/`nil`-Nummer nur für interne Emit-Hilfen |
| Personal | Discovery-Eintrag mit `accountNumber` und `kind=="personal"` |
| Business | Discovery-Eintrag mit `accountNumber` und `kind=="business"` |
| Obsolete MM-Nummern | `mix` / `sub:*` / `normal` / `inverse` / `monthly` / `yearly` → kein Refresh; Fehler mit Neu-Anlage |

Unbekannte `accountNumber`: **kein** Match-all.

### Hilfen

- `isCombinedMoneyMoneyAccount` / `isObsoleteMoneyMoneyAccountNumber`
- `orderMatchesMoneyMoneyAccount` / `harvestPriorityKindFromAccountNumber`
- `listAccountDisplayLabel` / `subAccountNumberForKind` (Discovery)
- Combined-`ListAccounts`-Name fest `Amazon` (`combinedAccountListLabel` = `"Amazon"`)

### Key-Inventar

| Bereich | Soll |
| --- | --- |
| `ListAccounts` | E-Mail, `AO.`+`customerId` ohne führendes `A` |
| `emitAccountKey` | Combined = Login-E-Mail (Pflicht); Subs = encoded `AO.…` |
| `obsoleteMoneyMoneyAccountNumbers` | Reject (+ nackte `customerId`, `AB-A…`) |
| `initialSyncRefreshedAccounts` | Combined-E-Mail-Key / encoded Sub-Nummer |
| Order-`emittedAccounts` | nur aktuelle Keys (E-Mail / `AO.…`) |
| `cacheVersion` | aktuell **23**; ältere/unversionierte Import-Caches werden verworfen |

Ledger: alle aktuellen Konten nutzen Mixed + Ausgleich. Kein Perioden-Contra,
keine Emit-/OrderCache-Migration. Notiz-Alias `blackListOrders` →
`blacklistOrders` bleibt lesend gültig.

## Kontoart Sonstiges

Bekannter Ist-Zustand: Plugin setzt bereits `type=AccountTypeOther`, aber das
gemeinsame Live-Konto kann in MoneyMoney als **Kreditkarte** stehen (manuell
oder beim Anlegen überschrieben; Refresh ändert die Art bestehender Konten
nicht). Zusätzlich kollidierte der frühere Service-Name `"Amazon"` mit
MoneyMoney’s eingebauter **Amazon-Kreditkarte**; Neuangebote nutzen daher
`"Amazon Bestellungen"`. `SupportsBank` akzeptiert **nur** diesen Namen
(kein Legacy `"Amazon"`, kein Beutling `"Amazon Orders"`). Alt-Kontonummern
lösen in `RefreshAccount` einen Fehler mit Neu-Anlage-Hinweis aus.

Sicherstellen:

1. `ListAccounts` setzt für **alle** angebotenen Konten explizit
   `type=AccountTypeOther` (gemeinsam und Unterkonten); fehlt die Konstante
   in der Host-Laufzeit, bricht `ListAccounts` mit Fehler ab.
2. Unterkonten-`accountNumber` enthält die rohe `customerId` **nicht** als
   Substring (`AO.` + ID ohne führendes `A`). Nackte IDs und `AB-A…` sind
   obsolete — sonst überschreibt MoneyMoney die persönliche ID mit
   *Kreditkarte* (eingebaute Amazon-Kreditkarte; Live mit `AB-A3Q0…` bestätigt).
3. Weiterhin `withTotalSum=false`, `showInDiagrams=false`,
   `showDailyBalance=false`, `perspective.chart=1`.
4. Tests prüfen `type`, Encoding ohne Substring-Leak und Obsolete-Formen.
5. README: nach dem Update Amazon-Konten **löschen und neu anlegen** unter
   *Amazon Bestellungen*; Alt-Zugänge und Alt-Nummern werden nicht bedient.
6. Kein Codepfad darf `AccountTypeCreditCard` oder eine andere Art setzen.
7. `WebBanking.services` / `SupportsBank`: ausschließlich
   `"Amazon Bestellungen"`.

MoneyMoney-UI kann die Art beim Bestätigen noch überschreiben; das Plugin
kann das nicht verhindern. Nach Neu-Anlage mit `AO.`-Nummern ist der vom
Plugin gelieferte Default **Sonstiges**.

## Breaking / Doku

- README und Update-Abschnitt: neue Namen/Nummern; Neu-Anlage nötig.
- Spezifikation 2026-08-31 (kombinierter Mix-Name) und Teile von
  2026-08-25 (Keys `mix`/`sub:*` für Neuangebote) als historisch markieren bzw.
  auf dieses Dokument verweisen.

## Tests

- `ListAccounts`: Name `Amazon` + E-Mail; `type=AccountTypeOther`.
- Bei zwei Subs: `Amazon <customerName>` / `Amazon <businessName>`,
  `accountNumber=AO.<customerId ohne A>`.
- Unvollständige Discovery: nur Combined; kein `sub:*`.
- Auth-Fehler in Discovery: Fehler, keine Teilliste.
- `isCombined` / `orderMatches`: E-Mail = combined; `AO.…` = eigenes Kind;
  nackte `customerId` / `AB-A…` / unbekannte Nummer ≠ match-all; obsolete →
  kein Match / Refresh-Fehler.

## Offene Umsetzungshinweise (kein Spec-Blocker)

- Exakter Regex/Selector für `customerId` an Live-HTML verifizieren (Fixture
  `ab_your_orders_spa.html` enthält bereits `customerId`).
