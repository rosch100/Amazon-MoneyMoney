# Amazon — MoneyMoney-Erweiterung

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Version: **2.09**
Repository: https://github.com/rosch100/Amazon-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

Fork von [Michael Beutling](https://github.com/Michael-Beutling/Amazon-MoneyMoney).

## Installation

Dateiname: **`amazon-bestellungen.lua`** (nicht `amazon-orders.lua` — der Name ist bereits
durch die Erweiterung von Michael Beutling belegt; alle Extensions liegen im selben
Download-Verzeichnis).

Aus diesem Repository (aktuell **unsigniert**, Version 2.09 — Signatur ausstehend):
[amazon-bestellungen.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-bestellungen.lua)

Website-Download unter diesem Namen: **2.04** signiert; dieses Repo ist **2.09** (Signatur ausstehend).

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
kopieren, oder im Klon `./link_ext.sh` ausführen.

Unsignierte/Entwicklungs-Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* ausschalten.

### Bot-Prüfung vs. Passwort vs. OTP

Amazon kann vor dem Login eine Bot-Prüfung (AWS WAF) zeigen. MoneyMoney zeigt dann
möglichst den Dialog **„Amazon Bot-Prüfung“** (Captcha). Das ist **nicht** der
Passwort-Dialog und **nicht** die OTP-/Bestätigungscode-Abfrage.

Wenn die Captcha-Challenge fehlt oder scheitert (oder der Abruf nicht interaktiv
ist): klare Bot-Prüfung-Meldung — nicht „Passwort falsch“. Dann: im Browser bei
amazon.de anmelden → MoneyMoney-Helper → `COOKIE:…` ins Passwortfeld (unten).
Ein Browser auf demselben Mac allein teilt die Session **nicht** mit MoneyMoney.

## Einrichten

*Konto hinzufügen* → *Andere* → *Amazon Bestellungen*.

Benutzername = Amazon-E-Mail. Passwort = Amazon-Passwort **oder** Cookie-Import
`COOKIE:…` (siehe unten). Mehrere Amazon-Konten: jeweils einen eigenen Bankzugang
mit eigener E-Mail anlegen.

Wenn Privat- und Firmenkonto vorhanden sind, erscheinen das Gesamtkonto
**Amazon (Privat + Geschäftlich)** sowie beide Einzelkonten. Das Gesamtkonto
enthält dieselben Bestellungen wie die beiden Einzelkonten zusammen. Wähle
entweder das Gesamtkonto oder die Einzelkonten; wenn du nur Privat- oder nur
Firmenbestellungen brauchst, wähle nur das betreffende Einzelkonto. So werden
dieselben Bestellungen nicht in mehreren MoneyMoney-Konten geführt.
Kontoart *Sonstige* belassen.

Alte Zugänge (anderer Service-Name oder alte Kontonummern) löschen und neu
anlegen — sie werden nicht mehr aktualisiert.

## Cookie-Import (bei Bot-Prüfung / Softblock)

Wenn Username/Passwort an der AWS-WAF hängen bleibt: Session aus dem Browser
übernehmen (gleicher Ablauf wie BoA/Fidelity im
[Hub — Cookie-Import](https://github.com/rosch100/moneymoney-extensions#cookie-import-beta-extensions)).

1. Im Browser bei [amazon.de](https://www.amazon.de) anmelden (WAF und 2FA lösen).
2. Mit der [MoneyMoney-Helper-Erweiterung](https://github.com/rosch100/moneymoney-extensions/tree/main/browser-extension)
   Cookies kopieren. Alternativ kann eine Browser-Erweiterung wie
   [Cookie-Editor](https://cookie-editor.com/) den Cookie-Header exportieren;
   daraus `COOKIE:session-id=…; at-acbde=…; …` bilden.
3. In MoneyMoney als **Passwort** einfügen (E-Mail unverändert lassen).
4. Zugang aktualisieren — Claim-Login entfällt; die Session kommt aus den Cookies.

Pflicht: `session-id` und ein Auth-Cookie (`at-acbde` / `at-main` bzw.
`sess-at-acbde` / `sess-at-main`). Abgelaufene Cookies → Meldung zum Neu-Export.
**Nie** Cookie-Strings in Issues posten.

### Lokal nachvollziehen (Kaltstart wie Nolif/#7)

1. Plugin 2.09 in den Extensions-Ordner (`./link_ext.sh` oder Kopie), MoneyMoney-Beta,
   Signaturprüfung aus.
2. Amazon-Zugang **neu anlegen** (oder bestehenden löschen), damit keine Alt-Cookies
   in `LocalStorage` helfen — so wie Nolifs Kaltstart.
3. Zuerst mit echtem Passwort abrufen → Captcha „Amazon Bot-Prüfung“ oder Softblock-
   Meldung (wenn Amazon WAF zeigt).
4. Wenn nötig: Browser-Login → Helper → `COOKIE:…` als Passwort → Abruf sollte
   Konten/Bestellungen ohne Claim laden.
5. Offline: `./test/run.sh test/test_cookie_import.lua` und
   `./test/run.sh test/test_aws_waf_captcha_challenge.lua`

## Nutzung

Den Zugang mehrfach aktualisieren, bis nichts Offenes mehr gemeldet wird. Der
erste vollständige Import kann mehrere Aktualisierungen brauchen.

Die Kontonotiz `scanFiltersMonths` begrenzt auch diesen Erstimport. Zum Beispiel
setzt `6` das Altersfenster auf sechs Monate; `0` lässt alle Zeiträume zu. Bei
Geschäftskonten gilt die Grenze für Business Analytics und ergänzende
Jahresfilter. Amazon bietet in der Bestellliste nur ganze Kalenderjahre an;
ein gewähltes Jahr kann deshalb auch ältere Bestellungen liefern. Deren Datum
wird beim Abruf der Bestelldetails geprüft; Umsätze außerhalb des eingestellten
Fensters werden nicht ausgegeben. Solche Bestellungen können beim Erstimport
vorübergehend noch offene Bestelldetails verursachen.

Die Bestellnummer steht unter **Referenz**, nicht in der Titelzeile. Käufe,
Erstattungen und Rückgaben erscheinen als Umsätze. Wenn eine negative
Gutschein- oder Aktionsrabatt-Gutschrift einer positiven Versandposition
derselben Bestellung betragsgleich netto oder brutto (bei 19 % oder 7 % MwSt.)
entspricht, werden beide als von Amazon (Prime) übernommene Versandkosten
unterdrückt. Das gilt auch bei Rücksendungen. Nicht passende Warenkorb-Gutscheine
bleiben in Bestellungen ohne Rückgabe erhalten; in Bestellungen mit Rückgabe
werden nicht gepaarte Gutscheine und Rabatte nicht gebucht.

### Buchungsarten

Die Kontonotiz `ledgerMode` legt fest, wie Käufe und Erstattungen gebucht werden.
Standard ist `normal`.
Setze `ledgerMode` unter **Konto → Einstellungen → Notizen** auf einen der Werte
in der Tabelle.

| Wert | Wirkung |
|------|---------|
| `normal` | Käufe sind Ausgaben, Erstattungen Einnahmen. |
| `inverse` | Umgekehrte Vorzeichen: Käufe sind Einnahmen, Erstattungen Ausgaben. |
| `mix` | Gleicht jede Bestellung für jeden Buchungstag mit einer Gegenbuchung aus. |
| `monthly` | Gleicht die Umsätze jedes Monats mit einer Sammelbuchung aus. |
| `yearly` | Gleicht die Umsätze jedes Jahres mit einer Sammelbuchung aus. |

Ein Wechsel von `ledgerMode` ändert vorhandene Umsätze nicht. Ohne `resetCache`
gilt die neue Buchungsart nur für neu importierte Umsätze.

Für eine andere Buchungsart in der Historie setze `resetCache` auf einen neuen
Wert und aktualisiere das Konto mehrfach, bis der Hinweis zum Erstimport
verschwindet. Bereits vorhandene Umsätze bleiben dabei erhalten.
Wenn du von oder zu `inverse` wechselst, lösche die betroffenen Umsätze vorher
in MoneyMoney. Sonst können dieselben Käufe zusätzlich mit umgekehrtem
Vorzeichen erscheinen.
Wenn du von `monthly` zu `yearly` wechselst, lösche die bisherigen
Monatsausgleiche im neu eingelesenen Zeitraum, falls du nur Jahresausgleiche
behalten möchtest. Sonst können beide Ausgleichsarten bestehen bleiben.

Bei `monthly` und `yearly` gleicht jede Sammelbuchung die in diesem Abruf
ausgegebenen Umsätze des jeweiligen Zeitraums aus. Buchungen mit gleichem
Buchungstag, Betrag, Namen und Verwendungszweck werden dabei nur einmal gezählt.
Der Verwendungszweck enthält Monat oder Jahr und den Abrufzeitpunkt. Spätere
Abrufe mit weiteren Umsätzen können zusätzliche Sammelbuchungen für denselben
Zeitraum erzeugen; die vorherige wird nicht verändert oder ersetzt.
Bei einem Saldo von null entsteht keine Sammelbuchung. Ihr Buchungstag liegt
am Periodenende, jedoch nicht in der Zukunft.
`resyncDeletedTransactions` stellt gelöschte Monats- und Jahresausgleiche nicht
wieder her. Ein vollständiger Neuimport mit `resetCache` kann neue
Periodenausgleiche erzeugen; bereits importierte Buchungen bleiben dabei
bestehen. Entferne betroffene alte Ausgleiche vor dem Neuimport, damit keine
doppelten Sammelbuchungen entstehen.

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

Schlüssel/Wert unter **Konto → Einstellungen → Notizen**. Die ersten sieben
Felder bietet MoneyMoney beim Anlegen an; die erweiterten werden nur gelesen,
wenn sie manuell eingetragen sind. Leere Werte behalten den Standard.
Nur `blackListOrders` ist als Alias von `blacklistOrders` erlaubt.

| Feld | Standard | Wirkung |
|------|----------|---------|
| `resetCache` | leer | Import-Cache löschen und die Historie neu aufbauen. Wirkt nur bei einem neuen, nichtleeren Wert. Löscht keine schon importierten Umsätze. |
| `blacklistOrders` | leer | Bestellnummern (kommagetrennt), die nicht als Umsätze ausgegeben werden. |
| `rescanOrder` | leer | Eine bekannte Bestellnummer, deren Details bei jedem Abruf neu geladen werden. Danach leeren. |
| `keepStorno` | `false` | Nur `true`: Buchung und Gegenbuchung bei voller Erstattung/Storno behalten. |
| `nameMaxLength` | `0` | Maximale Titellänge in Zeichen. `0` = unbegrenzt. |
| `resyncDeletedTransactions` | leer | Gespeicherte Umsätze dieses Kontos erneut anbieten. Neuer, nichtleerer Wert je Wiederholung. |
| `ledgerMode` | `normal` | Buchungsart festlegen. Siehe [Buchungsarten](#buchungsarten). |
| `limitOrders` | `250` | Obergrenze neuer Bestellungen und Detailseiten pro Abruf. |
| `scanFiltersMonths` | `0` | Altersfenster der Listenfilter in Monaten. Jahresfilter können zusätzliche ältere Bestellungen umfassen. `0` = alle angebotenen Zeiträume. |
| `cookieLanguage` | leer | Sprache der Amazon-Seiten, z. B. `de-DE` oder `en-GB`. Leer = Deutsch (`de-DE`). Wird als Cookie `lc-acbde` mit Unterstrich gesetzt (`de_DE`). |
| `orderDetailsUrl` | `/your-orders/order-details?orderID=` | Pfadpräfix der Bestelldetails; Bestellnummer wird angehängt. |
| `debug` | `false` | `true` schaltet die Detail-Protokollierung ein. Die Zeilen stehen im MoneyMoney-Protokollfenster (Fenster → Protokollfenster). Sie können Bestellnummern, Links, Notiz-Werte und Texte aus Login-Seiten enthalten. Nur zur Fehlersuche verwenden und danach wieder entfernen. Ohne `debug` erscheinen nur Ergebnisse, Warnungen und Fehler. |

`transactionId` ordnet bereits bekannte Umsätze zu, verhindert aber nicht
MoneyMoneys Ähnlichkeits-Deduplizierung nach Buchungstag, Betrag, Name und
Verwendungszweck. Wurden Zeilen zusammengefasst, müssen die betroffenen Umsätze
gelöscht werden. Für den Neuimport `resetCache` in den Kontonotizen auf einen
neuen Wert setzen und das Konto mehrfach aktualisieren, bis der Hinweis zum
Erstimport verschwindet. Der Cache-Neuaufbau löscht keine bereits importierten
Umsätze.

## Fehler & Ideen

Issues bitte über GitHub melden:
[Neues Issue](https://github.com/rosch100/Amazon-MoneyMoney/issues/new/choose).
Keine MoneyMoney-Logdateien anhängen — Details stehen im Bug-Formular.

So entsteht ein brauchbarer Fehlerbericht:

1. Unter **Konto → Einstellungen → Notizen** `debug` auf `true` setzen.
2. Den Abruf wiederholen, bis der Fehler erscheint.
3. Im Protokollfenster die Zeilen rund um den Fehler kopieren und redigieren: Bestellnummern, Namen, Adressen, Links und Notiz-Werte entfernen. Cookies gehören ohnehin nicht hinein.
4. Die Zeilen im Bug-Formular einfügen und `debug` danach wieder entfernen.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
