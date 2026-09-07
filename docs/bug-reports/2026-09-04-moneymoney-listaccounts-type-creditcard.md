# Bug-Report: `ListAccounts.type = AccountTypeOther` wird bei der Kontoanlage oft als Kreditkarte gespeichert

**Produkt:** MoneyMoney (macOS)
**Version:** 2.5.1 (516) Beta
**OS:** macOS 27.0 (ARM)
**Datum:** 2026-09-04
**API:** [Web Banking Extensions](https://moneymoney.app/api/webbanking/)
**Extension:** eigene Lua-Extension `amazon-bestellungen.lua` (Service-Name „Amazon Bestellungen“, Web Scraping)

---

## Klare Aussage

Laut Dokumentation setzt das Feld `type` in `ListAccounts` die Kontoart.
Wir setzen für **alle** zurückgegebenen Konten explizit `type = AccountTypeOther` (Bedeutung: **Sonstige**).

MoneyMoney legt trotzdem **häufig einzelne dieser Konten als Kreditkarte** an — bei identischem `type`, gleichem Owner und ohne dass die Extension jemals `AccountTypeCreditCard` liefert.

Das ist ein Fehler im Host (Kontoanlage nach `ListAccounts`), nicht in der Extension-Payload.

---

## Erwartetes Verhalten (Doku)

Aus der API-Dokumentation, Abschnitt „Datenstruktur eines Kontos“:

| Konstante | Bedeutung |
| --- | --- |
| `AccountTypeCreditCard` | Kreditkarte |
| `AccountTypeOther` | Sonstige |

`ListAccounts` liefert ein Array solcher Kontotabellen. Das Feld `type` ist die Kontoart.

**Erwartung:** Wenn `type = AccountTypeOther`, muss das angelegte Konto **Sonstige** sein.

---

## Tatsächliches Verhalten

Nach „Nach neuen Konten suchen“ / Kontoassistent:

| Konto (Name) | `accountNumber` (Form) | Extension `type` | Host-Kontoart (Export) |
| --- | --- | --- | --- |
| Amazon (Combined) | Login-E-Mail | `AccountTypeOther` | Sonstige |
| Bestellungen Roland | `z9.…@amazon-orders.invalid` | `AccountTypeOther` | **Kreditkarte** |
| Bestellungen Altanis GmbH | `z9.…@amazon-orders.invalid` | `AccountTypeOther` | Sonstige |

Gleiche Extension-Antwort, gleiches `type`, gleiches Encoding der Unterkonten — Host-Ergebnis **inkonsistent**.

---

## Live-Laufzeitkonstante (wichtig)

In MoneyMoney 2.5.1 (516) ist der Stringwert von `AccountTypeOther` **nicht** `"Other"`, sondern:

```text
AccountTypeOther     = "Unknown"
AccountTypeCreditCard = "Credit card"
AccountTypeGiro       = "Giro account"
```

Wir verwenden die **Host-Konstante** `AccountTypeOther` (nicht den Literal-String `"Other"`).
Vergleich in der Extension: `type == AccountTypeOther` → true, `type == AccountTypeCreditCard` → false für alle drei Konten.

Hinweis: Ein Experiment mit dem Literal `"Other"` statt `"Unknown"` verschlechterte das Ergebnis (beide Unterkonten wurden Kreditkarte). Die dokumentierte Konstante `AccountTypeOther` bleibt der korrekte API-Pfad.

---

## Reproduktion

1. MoneyMoney 2.5.1 (516) mit einer Web-Scraping-Extension, deren `ListAccounts` mindestens zwei Konten mit `type = AccountTypeOther` zurückgibt (siehe Minimalbeispiel unten).
2. Bankzugang anlegen bzw. „Nach neuen Konten suchen“.
3. Angebotene Konten bestätigen und anlegen.
4. Kontoart in den Kontoeinstellungen bzw. per AppleScript `export accounts` prüfen.

**Beobachtung:** Mindestens ein Konto mit `AccountTypeOther` erscheint als **Kreditkarte**.

Wiederholbar in mehreren Durchläufen mit unterschiedlichen Kontonummern und Namen (siehe Kontrollversuche).

---

## Evidenz: Extension-Payload (Diag, 2026-09-04T15:52:42Z)

Gekürzter Auszug (E-Mail redigiert):

```text
AccountTypeOther={string value="Unknown"}
AccountTypeCreditCard={string value="Credit card"}
returning #3 accounts:
out[1] name="Amazon"
       accountNumber="<login-email>"
       type=Unknown
       type==AccountTypeOther -> true
       type==AccountTypeCreditCard -> false
out[2] name="Bestellungen Roland"
       accountNumber="z9.3Q0VYB8LMHNXG@amazon-orders.invalid"
       type=Unknown
       type==AccountTypeOther -> true
       type==AccountTypeCreditCard -> false
out[3] name="Bestellungen Altanis GmbH"
       accountNumber="z9.3PQNNWE23MR9U@amazon-orders.invalid"
       type=Unknown
       type==AccountTypeOther -> true
       type==AccountTypeCreditCard -> false
```

Protokoll (Auszug):

```text
Web Banking account: Amazon (<login-email>)
Web Banking account: Bestellungen Roland (z9.3Q0VYB8LMHNXG@amazon-orders.invalid)
Web Banking account: Bestellungen Altanis GmbH (z9.3PQNNWE23MR9U@amazon-orders.invalid)
```

Anschließend bestätigt `export accounts`: Roland = Kreditkarte, Altanis = Sonstige, Combined = Sonstige.

---

## Kontrollversuche (Host-Override bleibt)

Alle Versuche mit `type = AccountTypeOther` (`"Unknown"`), sofern nicht anders vermerkt:

| Versuch | Änderung | Ergebnis Unterkonten |
| --- | --- | --- |
| A | Nackte Amazon-`customerId` (`A…`) | Roland oft Kreditkarte |
| B | Prefix `AB-A…` | Roland weiterhin Kreditkarte |
| C | Encoding `AO.<id ohne A>` | Unterkonten Kreditkarte |
| D | Jungfräuliche Nummern `Z9.<…>` | Beide Unterkonten Kreditkarte |
| E | Anzeigenamen ohne „Amazon …“ (`Bestellungen …`) | Beide weiterhin Kreditkarte |
| F | Literal `type = "Other"` (nicht die Konstante) | Beide Unterkonten Kreditkarte (schlechter) |
| G | E-Mail-förmige Nummern `z9.…@amazon-orders.invalid` | Roland = Kreditkarte, Altanis = Sonstige |

**Widerlegt als alleinige Ursache:**

- Extension setzt `AccountTypeCreditCard`
- Soft-Delete nur über exakte alte Kontonummer (jungfräuliche `Z9.` / `z9.…@…`)
- Soft-Delete nur über Anzeigename „Amazon …“
- „Nur Nicht-E-Mail-Nummern werden Kreditkarte“ (Altanis mit E-Mail-Form wurde Sonstige, Roland nicht)

**Bleibt:** Host speichert trotz dokumentiertem `AccountTypeOther` häufig **Kreditkarte**.

---

## Minimalbeispiel `ListAccounts` (Konzept)

```lua
function ListAccounts(knownAccounts)
  return {
    {
      name = "Example Combined",
      owner = secUsername,
      accountNumber = secUsername, -- E-Mail
      type = AccountTypeOther,
      portfolio = false,
      currency = "EUR",
    },
    {
      name = "Example Sub A",
      owner = secUsername,
      accountNumber = "z9.EXAMPLESUBA01@example.invalid",
      type = AccountTypeOther,
      portfolio = false,
      currency = "EUR",
    },
    {
      name = "Example Sub B",
      owner = secUsername,
      accountNumber = "z9.EXAMPLESUBB02@example.invalid",
      type = AccountTypeOther,
      portfolio = false,
      currency = "EUR",
    },
  }
end
```

Erwartung laut Doku: alle drei **Sonstige**.
Beobachtung: mindestens ein Unterkonto wird **Kreditkarte**.

---

## Auswirkungen

- Falsche Kontoart in der Seitenleiste und in Auswertungen
- Nutzer müssen Kontoart manuell korrigieren (falls möglich) oder Konten löschen/neu anlegen
- Extension-Autoren können die dokumentierte Kontoart nicht zuverlässig steuern

---

## Anhänge (auf Anfrage / beiliegend)

1. Protokoll: `MoneyMoney-202609041753.log` (MoneyMoney 2.5.1 (516))
2. Extension-Diag: `amazon-listaccounts-diag.txt` (Payload inkl. Konstantenvergleich)
3. AppleScript-Export der betroffenen Konten (`type` / `accountNumber` / `name`)
4. Bei Bedarf: weitere Protokolle der Kontrollversuche A–G

---

## Bitte an MoneyMoney

1. Bestätigen, dass `ListAccounts[].type = AccountTypeOther` bei der Neuanlage immer zu Kontoart **Sonstige** führen muss.
2. Den Override/Heuristik-Pfad finden, der trotz `AccountTypeOther` **Kreditkarte** speichert.
3. Optional: Doku anpassen, falls `AccountTypeOther` intern `"Unknown"` heißt (aktuell weicht der Live-String von einer naiven Lesart „Other“ ab; die Konstante selbst ist korrekt).
