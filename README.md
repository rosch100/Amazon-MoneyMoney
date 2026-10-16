# Amazon — MoneyMoney-Erweiterung

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Version: **2.04** (Beta; die Versionsnummer in MoneyMoney ist 2.04, der Zusatz steht in der Beschreibung)
Repository: https://github.com/rosch100/Amazon-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

Fork von [Michael Beutling](https://github.com/Michael-Beutling/Amazon-MoneyMoney).

## Installation

Dateiname: **`amazon-bestellungen.lua`** (nicht `amazon-orders.lua` — der Name ist bereits
durch die Erweiterung von Michael Beutling belegt; alle Extensions liegen im selben
Download-Verzeichnis).

Aus diesem Repository (inkl. MoneyMoney Signatur):
[amazon-bestellungen.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-bestellungen.lua)

Website-Download unter diesem Namen, sobald auf moneymoney-app.com bereitgestellt.

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
kopieren, oder im Klon `./link_ext.sh` ausführen.

Unsignierte/Entwicklungs-Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* ausschalten.

## Einrichten

*Konto hinzufügen* → *Andere* → *Amazon Bestellungen*.

Benutzername und Passwort = Amazon-Login. Mehrere Amazon-Konten: jeweils einen
eigenen Bankzugang mit eigener E-Mail anlegen.

Es erscheinen das gemeinsame Konto **Amazon** und ggf. getrennte Konten für
persönlich und geschäftlich. Kontoart *Sonstige* belassen.

Alte Zugänge (anderer Service-Name oder alte Kontonummern) löschen und neu
anlegen — sie werden nicht mehr aktualisiert.

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

Alle Konto-Notizen und erweiterten Optionen (`resetCache`, `blacklistOrders`,
`rescanOrder`, `keepStorno`, `nameMaxLength`, `resyncDeletedTransactions`,
`limitOrders`, `scanFiltersMonths`, `cookieLanguage`, `orderDetailsUrl`) mit
Defaults und Verwendung sind unter [Amazon — Einstellungen und Verhalten](https://github.com/rosch100/moneymoney-extensions/blob/main/docs/LUA-EXTENSIONS.md#amazon--einstellungen-und-verhalten)
dokumentiert.

## Fehler & Ideen

Issues bitte über GitHub melden:
[Neues Issue](https://github.com/rosch100/Amazon-MoneyMoney/issues/new/choose).
Keine MoneyMoney-Logdateien anhängen — Details stehen im Bug-Formular.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
