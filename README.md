# Amazon — MoneyMoney-Erweiterung

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Version: **2.07**
Repository: https://github.com/rosch100/Amazon-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

Fork von [Michael Beutling](https://github.com/Michael-Beutling/Amazon-MoneyMoney).

## Installation

Dateiname: **`amazon-bestellungen.lua`** (nicht `amazon-orders.lua` — der Name ist bereits
durch die Erweiterung von Michael Beutling belegt; alle Extensions liegen im selben
Download-Verzeichnis).

Aus diesem Repository (aktuell **unsigniert**, Version 2.07 — Signatur ausstehend):
[amazon-bestellungen.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-bestellungen.lua)

Website-Download unter diesem Namen: **2.04** signiert; dieses Repo ist **2.07** (Signatur ausstehend).

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
kopieren, oder im Klon `./link_ext.sh` ausführen.

Unsignierte/Entwicklungs-Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* ausschalten.

Liefert der erste Abruf eine AWS-WAF-/Softblock-Seite und MoneyMoney kann die
Captcha-Challenge nicht anzeigen bzw. lösen, bricht die Extension mit einer
Bot-Prüfung-Meldung ab (nicht „Passwort falsch“). Hinweis: Browser-Login →
MoneyMoney-Helper → `COOKIE:…` ins Passwortfeld (unten). Ein Browser auf demselben
Mac allein teilt die Session nicht mit MoneyMoney.

## Einrichten

*Konto hinzufügen* → *Andere* → *Amazon Bestellungen*.

Benutzername = Amazon-E-Mail. Passwort = Amazon-Passwort **oder** Cookie-Import
`COOKIE:…` (siehe unten). Mehrere Amazon-Konten: jeweils einen eigenen Bankzugang
mit eigener E-Mail anlegen.

Es erscheinen das gemeinsame Konto **Amazon** und ggf. getrennte Konten für
persönlich und geschäftlich. Kontoart *Sonstige* belassen.

Alte Zugänge (anderer Service-Name oder alte Kontonummern) löschen und neu
anlegen — sie werden nicht mehr aktualisiert.

## Cookie-Import (bei Bot-Prüfung / Softblock)

Wenn Username/Passwort an der AWS-WAF hängen bleibt: Session aus dem Browser
übernehmen (gleicher Ablauf wie BoA/Fidelity/MLP im
[Hub — Cookie-Import](https://github.com/rosch100/moneymoney-extensions#cookie-import-beta-extensions)).

1. Im Browser bei [amazon.de](https://www.amazon.de) anmelden (WAF und 2FA lösen).
2. Mit dem **MoneyMoney Helper** Cookies kopieren (oder manuell
   `COOKIE:session-id=…; at-acbde=…; …`).
3. In MoneyMoney als **Passwort** einfügen (E-Mail unverändert lassen).
4. Zugang aktualisieren — Claim-Login entfällt; die Session kommt aus den Cookies.

Pflicht: `session-id` und ein Auth-Cookie (`at-acbde` / `at-main` bzw.
`sess-at-acbde` / `sess-at-main`). Abgelaufene Cookies → Meldung zum Neu-Export.
**Nie** Cookie-Strings in Issues posten.

### Lokal nachvollziehen (Kaltstart wie Nolif/#7)

1. Plugin 2.07 in den Extensions-Ordner (`./link_ext.sh` oder Kopie), MoneyMoney-Beta,
   Signaturprüfung aus.
2. Amazon-Zugang **neu anlegen** (oder bestehenden löschen), damit keine Alt-Cookies
   in `LocalStorage` helfen — so wie Nolifs Kaltstart.
3. Zuerst mit echtem Passwort abrufen → erwartbar Softblock/Bot-Prüfung (wenn Amazon
   WAF zeigt).
4. Browser-Login → Helper → `COOKIE:…` als Passwort → Abruf sollte Konten/Bestellungen
   ohne Claim laden.
5. Offline: `./test/run.sh test/test_cookie_import.lua`

## Nutzung

Den Zugang mehrfach aktualisieren, bis nichts Offenes mehr gemeldet wird. Der
erste vollständige Import kann mehrere Aktualisierungen brauchen.

Die Bestellnummer steht unter **Referenz**, nicht in der Titelzeile. Käufe,
Erstattungen und Rückgaben erscheinen als Umsätze. Wenn eine negative
Gutschein- oder Aktionsrabatt-Gutschrift einer positiven Versandposition
derselben Bestellung betragsgleich netto oder brutto (bei 19 % MwSt.)
entspricht, werden beide als von Amazon übernommene Versandkosten unterdrückt.
Nicht passende Warenkorb-Gutscheine bleiben erhalten. Der synthetische
**Amazon Ausgleich** ist derzeit deaktiviert.

## Umlaute und gelöschte Umsätze

Eine normale Aktualisierung ändert bereits gebuchte Zeilen nicht. Titel aus
Bestellungen bis etwa 2015, die als `WÃ¤rme` oder `weiÃŸ` dastehen, werden erst
beim erneuten Aufbau der Umsatzzeile korrigiert.

Dafür in den Kontonotizen `resetCache` auf einen **neuen** Wert setzen und das
Konto mehrfach aktualisieren, bis der Hinweis zum Erstimport verschwindet.
Damit wird die ganze Bestellhistorie neu gelesen, nicht nur der Zeitraum seit
dem letzten Abruf. Bereits vorhandene Umsätze bleiben; gelöschte kommen wieder
dazu.

`resyncDeletedTransactions` reicht dafür nicht. Dabei werden die schon
gespeicherten Texte erneut geschickt.

## Konto-Notizen

Schlüssel/Wert unter **Konto → Einstellungen → Notizen**. Die ersten sechs
Felder bietet MoneyMoney beim Anlegen an; die vier erweiterten werden nur
gelesen, wenn sie manuell eingetragen sind. Leere Werte behalten den Standard.
Nur `blackListOrders` ist als Alias von `blacklistOrders` erlaubt.

| Feld | Standard | Wirkung |
|------|----------|---------|
| `resetCache` | leer | Import-Cache löschen und die Historie neu aufbauen. Wirkt nur bei einem neuen, nichtleeren Wert. Löscht keine schon importierten Umsätze. |
| `blacklistOrders` | leer | Bestellnummern (kommagetrennt), die nicht als Umsätze ausgegeben werden. |
| `rescanOrder` | leer | Eine bekannte Bestellnummer, deren Details bei jedem Abruf neu geladen werden. Danach leeren. |
| `keepStorno` | `false` | Nur `true`: Buchung und Gegenbuchung bei voller Erstattung/Storno behalten. |
| `nameMaxLength` | `0` | Maximale Titellänge in Zeichen. `0` = unbegrenzt. |
| `resyncDeletedTransactions` | leer | Gespeicherte Umsätze dieses Kontos erneut anbieten. Neuer, nichtleerer Wert je Wiederholung. |
| `limitOrders` | `250` | Obergrenze neuer Bestellungen und Detailseiten pro Abruf. |
| `scanFiltersMonths` | `0` | Altersfenster der Listenfilter in Monaten. `0` = alle angebotenen Zeiträume. |
| `cookieLanguage` | leer | Sprachcookie, z. B. `de-DE`. Leer = Sprache der Amazon-Domain. |
| `orderDetailsUrl` | `/your-orders/order-details?orderID=` | Pfadpräfix der Bestelldetails; Bestellnummer wird angehängt. |

## Fehler & Ideen

Issues bitte über GitHub melden:
[Neues Issue](https://github.com/rosch100/Amazon-MoneyMoney/issues/new/choose).
Keine MoneyMoney-Logdateien anhängen — Details stehen im Bug-Formular.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
