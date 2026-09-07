# Amazon — MoneyMoney-Erweiterung

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Version: **2.00**
Repository: https://github.com/rosch100/Amazon-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

Fork von [Michael Beutling](https://github.com/Michael-Beutling/Amazon-MoneyMoney).

## Installation

Dateiname: **`amazon-bestellungen.lua`** (nicht `amazon-orders.lua` — der Name ist bereits
durch die Erweiterung von Michael Beutling belegt; alle Extensions liegen im selben
Download-Verzeichnis).

Aus diesem Repository:
[amazon-bestellungen.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-bestellungen.lua)

Signierte Website-Version: sobald Adams die Datei unter diesem Namen auf
moneymoney-app.com bereitstellt.

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
Erstattungen und Rückgaben erscheinen als Umsätze; **Amazon Ausgleich** hält
den Saldo bei 0.

Optionale Feineinstellungen liegen in den Kontonotizen (z. B. Cache neu
einlesen). Details:
[Amazon — Einstellungen und Verhalten](https://github.com/rosch100/moneymoney-extensions/blob/main/docs/LUA-EXTENSIONS.md#amazon--einstellungen-und-verhalten)
im Hub.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
