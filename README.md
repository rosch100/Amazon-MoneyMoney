# Amazon-Plugin für MoneyMoney

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Repository: https://github.com/rosch100/Amazon-MoneyMoney

## Installation

Signierte Version: https://moneymoney-app.com/extensions/amazon-orders.lua

Aktuelle unsignierte Version aus diesem Repository: [amazon-orders.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-orders.lua)

Datei nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions` kopieren. Bei einem Klon des Repositories reicht `link_ext.sh`. MoneyMoney lädt die Erweiterung ohne Neustart; Prüfung über *Fenster → Log*.

Unsignierte Plugins laufen nur in der **Beta** von MoneyMoney, und die Signaturprüfung muss in den Erweiterungseinstellungen ausgeschaltet sein.

## Konten anlegen

*Konto hinzufügen* → *Andere* → *Amazon Orders*. Kontotypen:

- **Normal:** Käufe negativ, Erstattungen und Gutschriften positiv.
- **Invertiert:** umgekehrt.
- **Mix:** Käufe, Erstattungen und Rückgaben als echte Buchungen. Eine offene Buchung **Amazon Ausgleich** hält den Saldo bei 0. Das Konto erscheint als *Sonstige*, zählt nicht zur Gesamtsumme in der Seitenleiste und nicht in Diagrammen. Die Umsatzliste öffnet als Liste, nicht als Balkendiagramm.
- **Monatlich / Jährlich:** Käufe negativ, dazu eine Gegenbuchung, die das Konto auf 0 bringt.

Wenn persönliches und geschäftliches Amazon-Konto verbunden sind, erscheinen zusätzlich:

- **Amazon Alle Konten** — beide zusammen
- **Amazon Persönlich**
- **Amazon Geschäftlich**

Beim Einrichten (*Konten werden gesucht*) werden noch keine Umsätze geladen. Danach *Bankzugang → Nach neuen Konten suchen*, falls Einstellungen oder Kontotyp nicht übernommen wurden.

## Erstimport

Den Zugang mehrfach aktualisieren, bis die Statuszeile nichts Offenes mehr meldet und die Platzhalterbuchung *„Es sind noch weitere Bestellungen offen…“* verschwindet.

Pro Durchgang werden höchstens 250 Bestelldetails geladen. Beim Abruf von **Amazon Geschäftlich** wird zuerst das Geschäftskonto gelesen.

Geschäftliche Bestellungen kommen aus den Amazon-Business-Berichten. Amazon liefert dort in der Regel die letzten zwölf Monate und das Jahr davor; ältere Geschäftsbestellungen stellt Amazon oft nicht bereit. Private Bestellungen kommen aus der Bestellübersicht (Jahresfilter).

## Laufende Aktualisierung

Neue Bestellungen werden automatisch übernommen (Schlüssel: Bestellnummer). Bereits importierte Bestellungen der letzten zwölf Monate werden auf Erstattungen und Rückgaben geprüft.

## Buchungen

- **Titelzeile:** Artikelbezeichnung, vollständig (siehe `nameMaxLength`).
- **Verwendungszweck:** immer die volle Artikelbezeichnung.
- **Referenz:** Bestellnummer.
- **Umsatzart:** Lieferadresse, soweit bekannt.

Volle Erstattung, volle Rückgabe und stornierte (nicht berechnete) Bestellung: Buchung und Gegenbuchung (Storno) werden standardmäßig weggelassen. Teilrückgabe erscheint als **Rücksendekosten** (Anteil, der nicht erstattet wurde). Mit `keepStorno` bleiben Buchung und Gegenbuchung sichtbar.

## Einstellungen (Notizen)

Konto → Einstellungen → Notizen. Die Felder werden beim Anlegen bzw. bei *Nach neuen Konten suchen* mit Standardwerten angelegt. Ein normaler Abruf ändert die Tabelle nicht.

| Feld | Bedeutung |
|------|-----------|
| `resetCache` | Cache leeren und Bestellhistorie neu einlesen. Nach einem Update und dem Löschen aller Umsätze einmal auf ein neues Datum setzen, dann aktualisieren. |
| `blacklistOrders` | Bestellnummern (kommagetrennt), die übersprungen werden, wenn Details fehlschlagen. |
| `rescanOrder` | Eine Bestellnummer, deren Details beim nächsten Abruf neu geladen werden. |
| `keepStorno` | `true`: Buchung und passendes Storno behalten. Standard: `false`. Bereits importierte Buchungen werden nicht gelöscht; eine spätere volle Erstattung wird trotzdem importiert. |
| `nameMaxLength` | Maximale Länge der **Titelzeile** (Zeichen). `0` = ungekürzt (Standard). Der Verwendungszweck bleibt immer vollständig. Beispiel: `70`. |
| `limitOrders` | Maximale Zahl Bestelldetails pro Abruf (Standard 250). |

## Update von älteren Versionen

Bestehende Umsätze werden nicht umgeschrieben.

1. Alle Umsätze der Amazon-Konten in MoneyMoney löschen.
2. In den Notizen `resetCache` auf einen neuen Wert setzen (z. B. das heutige Datum).
3. Aktualisieren. Die Statuszeile sagt, falls der Neuimport noch aussteht.

Vor Schritt 2–3 werden keine neuen Umsätze geladen, damit nichts doppelt oder unvollständig entsteht.

## Laufzeit

Der erste Import liest die gesamte Historie (bei vielen Jahren Dauer im Bereich von Minuten). Weitere Läufe nur neue bzw. geänderte Bestellungen; ein normaler Abruf dauert meist unter einer Minute.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.
