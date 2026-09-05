# Amazon-Plugin für MoneyMoney

Bestellungen von amazon.de als Umsätze in MoneyMoney.

Version: **2.01**
Service: **Amazon Bestellungen**
Auth: Username/Passwort (Amazon-Login; kein Cookie-Import)
Repository: https://github.com/rosch100/Amazon-MoneyMoney
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

Das ist ein fork von https://github.com/Michael-Beutling/Amazon-MoneyMoney und eine Weiterentwicklung von Michaels plugin.

## Installation

Signierte Version: https://moneymoney-app.com/extensions/amazon-orders.lua

Aktuelle unsignierte Version aus diesem Repository: [amazon-orders.lua](https://raw.githubusercontent.com/rosch100/Amazon-MoneyMoney/master/amazon-orders.lua)

Die signierte Version wird außerhalb dieses Forks veröffentlicht und entspricht
nicht automatisch dessen erweitertem Funktionsumfang. Die unten im Abschnitt
[Änderungen gegenüber der ursprünglichen Version](#änderungen-gegenüber-der-ursprünglichen-version)
beschriebenen Funktionen beziehen sich auf die unsignierte Datei aus diesem
Repository.

Datei nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions` kopieren. Bei einem Klon des Repositories reicht `./link_ext.sh`; das Skript ersetzt den vorhandenen Link bzw. die vorhandene Datei durch einen Hardlink und setzt den Standard-Containerpfad voraus. MoneyMoney lädt die Erweiterung ohne Neustart; Prüfung über *Fenster → Log*.

Unsignierte Plugins laufen nur in der **Beta** von MoneyMoney, und die Signaturprüfung muss in den Erweiterungseinstellungen ausgeschaltet sein.

## Konten anlegen

*Konto hinzufügen* → *Andere* → *Amazon Bestellungen*.

Mehrere Amazon-Logins parallel: jeweils einen eigenen MoneyMoney-Bankzugang
mit eigener E-Mail anlegen. Order-Cache und Harvest-State sind pro Login
isoliert.

Das gemeinsame Konto heißt **Amazon**; die Kontonummer ist die Login-E-Mail.
Sind ein persönliches und ein geschäftliches Amazon-Konto verbunden, werden
zusätzlich **Amazon <Name>** (persönlich) und **Amazon <Firmenname>**
(geschäftlich) angeboten. Die Kontonummern der Unterkonten sind `AO.` plus die
Amazon-Kunden-ID **ohne** führendes `A` (z. B. `AO.3Q0VYB8LMHNXG`) — so bleibt
die ID nicht als Substring erkennbar und MoneyMoney mappt sie nicht auf die
eingebaute *Amazon-Kreditkarte*.

Die Unterkonten werden nur angeboten, wenn der Amazon-Kontowechsler beim Login
tatsächlich beide Unterkonten liefert und Amazon die Namen meldet.

Alle diese Konten buchen Käufe, Erstattungen und Rückgaben als echte Umsätze. Eine offene Buchung **Amazon Ausgleich** hält den Saldo bei 0. Sie erscheinen als Kontoart *Sonstige*, zählen nicht zur Gesamtsumme in der Seitenleiste und nicht in Diagrammen. Die Umsatzliste öffnet als Liste, nicht als Balkendiagramm.

Der Service heißt absichtlich nicht nur *Amazon*, damit er nicht mit MoneyMoney’s
eingebauter *Amazon-Kreditkarte* kollidiert und nicht Beutlings *Amazon Orders*
übernimmt. Alt-Zugänge mit Service *Amazon* oder Kontonummern wie `mix` /
`sub:*` / `normal` / … sowie nackte Kunden-IDs oder `AB-…` werden **nicht** mehr
aktualisiert: MoneyMoney meldet dann, dass die Konten unter *Amazon Bestellungen*
neu angelegt werden müssen.

Beim Bestätigen in MoneyMoney die Kontoart prüfen (*Sonstige*). Eine bereits
angelegte *Kreditkarte* ändert ein Refresh nicht.

Beim Einrichten (*Konten werden gesucht*) werden noch keine Umsätze geladen.

Alte Konten (auch Normal / Invertiert / Monatlich / Jährlich) bitte löschen und
neu anlegen — sie werden nicht weiter bedient.

## Erstimport

Den Zugang mehrfach aktualisieren, bis die Statuszeile nichts Offenes mehr
meldet und keine offene Platzhalterbuchung mehr auf einen unvollständigen
Abruf hinweist. Beim Einrichten sucht `ListAccounts` nur Konten; der eigentliche
Erstimport beginnt nach dem Ende dieser Sitzung.

Beim **geschäftlichen Unterkonto** hat das Geschäftskonto Vorrang. **Amazon**
(gemeinsames Konto) arbeitet dagegen im Round-Robin-Verfahren: Pro Aktualisierung wird
höchstens ein Batch je erkanntem Unterkonto verarbeitet und bei noch offenen
Daten mit dem nächsten Unterkonto fortgesetzt. Dadurch kann ein vollständiger
Erstimport mehrere Aktualisierungen benötigen.

`limitOrders` begrenzt getrennt die Zahl neu verarbeiteter Bestellungen eines
Filter-Batches und die Zahl geladener Bestelldetails (Standard jeweils 250).
Amazon-Business-Berichte werden unabhängig davon in höchstens sechs
Berichts-Jobs pro Aktualisierung abgearbeitet.

### Lokale Entwicklerwerkzeuge

Die folgenden Skripte arbeiten mit dem MoneyMoney-Datenverzeichnis im
Standard-Container und sind nur für lokale Debug-Sitzungen gedacht:

- `./webCache_on.sh` aktiviert den Webcache.
- `./webCache_off.sh` deaktiviert den Webcache.
- `./clean_webCache.sh` leert den Webcache und legt ihn wieder an.
- `./toggleCleanLocalStorage.sh` schaltet die Bereinigung von
  `LocalStorage` beim nächsten Debug-Lauf um.

Geschäftliche Bestellungen kommen primär aus Amazon Business Analytics:
`PAST_12_MONTHS` und anschließend ältere `CUSTOM_RANGE`-Zeitfenster. Die
Rollup-Tabelle wird seitenweise gelesen (maximal 250 Seiten). Beim vollständigen
Business-Abruf ergänzt das Plugin fehlende Jahresbereiche über die klassische
Bestellübersicht; beim inkrementellen Abruf bleibt es beim Business-Bericht.
Private Bestellungen kommen aus der Bestellübersicht mit Zeit-/Jahresfiltern.

### Offener Abruf

Die offene Buchung trägt unter **Referenz**
`AMAZON-INCOMPLETE-HARVEST`, hat den Betrag 0 und ist nicht gebucht. Ihr
Verwendungszweck nennt den konkreten offenen Zustand:

- Unterkonten- oder Erstimport noch nicht vollständig,
- noch offene Business-Berichts-Jobs oder unvollständige Rollup-Pagination,
- Bestelldetails nach einer Kürzung am Abruflimit oder nach einem Abruffehler.

Nur noch planmäßig zur späteren Prüfung vorgemerkte Details erzeugen für sich
allein keinen Platzhalter. Während *Konten werden gesucht* wird ebenfalls kein
Platzhalter ausgegeben.

## Laufende Aktualisierung

Neue Bestellungen werden automatisch übernommen (Schlüssel: Bestellnummer).
Bestellungen der letzten 366 Tage werden auf Erstattungen und Rückgaben
überwacht. Ihre Detailseiten werden abhängig vom Alter erneut eingeplant:
nach 7–14 Tagen bei Bestellungen unter 90 Tagen, nach 21–42 Tagen bis 366 Tage
und danach nach 90–180 Tagen. Taucht eine Bestellung erneut im Harvest auf,
kann sie ebenfalls wieder zur Detailprüfung vorgemerkt werden.

## Buchungen

Die Amazon-Bestellnummer steht **nicht** in der Titelzeile, sondern unter **Referenz**.

Bei **Artikelzeilen:**

- **Titelzeile:** Artikelbezeichnung, vollständig (siehe `nameMaxLength`).
- **Verwendungszweck:** volle Artikelbezeichnung.
- **Referenz:** Bestellnummer.
- **Umsatzart:** Lieferadresse, soweit bekannt.

Außerdem können eigene Buchungen entstehen für Versand, Verpackung, Geschenkverpackung, **Bestelldifferenz**, **Erstattung**, **Rückgabe**, **Rücksendekosten**, **Amazon Ausgleich** und den Platzhalter zum erneuten Abruf.

Volle Erstattung, volle Rückgabe und stornierte (nicht berechnete) Bestellung: Buchung und Gegenbuchung (Storno) werden standardmäßig weggelassen. Teilrückgabe und volle Rückgabe mit verbleibendem Versand erscheinen als **Rücksendekosten**. Mit `keepStorno` bleiben Buchung und Gegenbuchung sichtbar.

## Einstellungen (Notizen)

Konto → Einstellungen → Notizen. Diese Felder legt MoneyMoney beim Anlegen bzw. bei *Bankzugang → Nach neuen Konten suchen* mit Standardwerten an. Ein normaler Abruf ändert die Tabelle nicht.

| Feld | Bedeutung |
|------|-----------|
| `resetCache` | Cache leeren und Bestellhistorie neu einlesen. Nach Schema-Upgrade (Statusmeldung zum vollständigen Neuimport) den Wert **ändern** (z. B. auf das heutige Datum) — derselbe alte Wert hebt die Sperre nicht auf — dann aktualisieren. |
| `blacklistOrders` | Bestellnummern (kommagetrennt), die weder als Umsätze ausgegeben noch regulär im Detailabruf verarbeitet werden. Ihre nächste Detailprüfung wird planmäßig terminiert. Das ältere Notizfeld `blackListOrders` wird weiterhin gelesen. |
| `rescanOrder` | Eine Bestellnummer, deren Details beim nächsten Abruf neu geladen werden. Die bereits gemerkte Ausgabezuordnung wird für diese Bestellung zurückgesetzt. |
| `keepStorno` | `true`: Buchung und passendes Storno behalten. Standard: `false`. Bereits importierte Buchungen werden nicht gelöscht; eine spätere volle Erstattung wird trotzdem importiert. |
| `nameMaxLength` | Maximale Länge der **Titelzeile** (Zeichen). `0` = ungekürzt (Standard). Der Verwendungszweck bleibt immer vollständig. Beispiel: `70`. |

Diese Felder kann man zusätzlich eintragen (kein Standardwert in der Notiztabelle):

| Feld | Bedeutung |
|------|-----------|
| `limitOrders` | Grenze je Bestelllisten-Filter-Batch und getrennte Grenze für Bestelldetails (interner Standard jeweils 250). Business-Berichts-Jobs haben ein eigenes Limit. |
| `scanFiltersMonths` | Maximales Alter der gelesenen Bestellübersichtsfilter. `0` = beim vollständigen Import alle Jahre (Standard); beim inkrementellen Abruf begrenzt das Plugin das Fenster automatisch auf den aktuellen Abrufzeitraum. |
| `cookieLanguage` | Sprachkennung der Amazon-Seite, falls die Anzeige nicht Deutsch ist. |
| `orderDetailsUrl` | Nur nötig, wenn Amazon den Pfad zu den Bestelldetails ändert. |

## Update von älteren Versionen

Es hat sich so viel geändert (Anzeigenamen, Kontonummern, Kontoart *Sonstige*,
Mix-Buchungen, Service *Amazon Bestellungen*), dass **Löschen und neu Anlegen
der Amazon-Konten** Pflicht ist. Alt-Zugänge und alte Kontonummern
(`mix` / `sub:*` / `normal` / …) werden bewusst nicht mehr aktualisiert.
Bestehende Umsätze werden nicht umgeschrieben; alte Titelzeilen mit Bestellnummer
bleiben sonst stehen. Ohne Neuanlage bleibt die bisherige Kontoart (z. B.
Kreditkarte) und die neuen Nummern/Service-Namen kommen nicht an.

Cache-Version **23** verwirft ältere Plugin-Importcaches. MoneyMoney zeigt
danach die Aufforderung zum vollständigen Neuimport; vorhandene fehlerhafte
Umsätze werden nicht still verändert. Zusätzlich: in den Kontonotizen
`resetCache` auf einen **neuen** Wert setzen (nicht denselben wie zuvor),
danach aktualisieren — sonst bleibt der Abruf gesperrt.

1. Amazon-Zugang in MoneyMoney entfernen (Konten löschen).
2. Plugin aktualisieren.
3. Zugang und Konten neu anlegen, danach Erstimport wie oben.

Nur Umsätze löschen und `resetCache` setzen reicht in der Regel nicht: Kontotyp
*Sonstige*, neue Kontonummern (E-Mail bzw. `AO.` + Kunden-ID ohne `A`), Notizfelder und
die neue Aufteilung der Konten kommen so nicht zuverlässig an.

## Änderungen gegenüber der ursprünglichen Version

Fork von [Michael Beutling](https://github.com/Michael-Beutling/Amazon-MoneyMoney). Gegenüber dem Original:

- **Titelzeile** ist der Artikelname, nicht mehr die Bestellnummer. Die Bestellnummer steht unter **Referenz**.
- **Gemeinsames Konto** **Amazon** (Kontonummer = Login-E-Mail) sowie getrennte
  Unterkonten **Amazon <Name>** / **Amazon <Firmenname>**
  (Kontonummer = `AO.` + Amazon-Kunden-ID ohne führendes `A`). Die fünf Buchungsarten Normal / Invertiert /
  Mix / Monatlich / Jährlich und Alt-Nummern `mix`/`sub:*` werden nicht mehr
  bedient — Konten unter *Amazon Bestellungen* neu anlegen.
- **Mix-Logik:** echte Käufe, Erstattungen und Rückgaben, dazu ein offener **Amazon Ausgleich** auf Saldo 0 — nicht mehr Kauf und Gegenbuchung mit der Bestellnummer als Titel.
- Konten erscheinen als **Sonstige** und zählen nicht zur Gesamtsumme oder zu Diagrammen.
- **Amazon Business** über die Beschaffungsanalysen (Berichte), nicht nur über die Bestellübersicht.
- **Fortsetzbarer Erstimport:** Zustandsbehafteter Harvest über mehrere
  Aktualisierungen, Round-Robin für *Amazon* (gemeinsames Konto) und Priorität des gewählten
  Unterkontos.
- **Business-Batching und Pagination:** `PAST_12_MONTHS` plus ältere
  `CUSTOM_RANGE`-Zeiträume, sechs Jobs je Aktualisierung sowie fortsetzbare
  Rollup-Pagination mit klassischem Jahresfilter als Lückenabdeckung.
- Erstattungen und Rückgaben aus den **Bestelldetails**, nicht mehr aus dem Nachrichten-Center.
- **Erneute Detailprüfung:** Altersabhängige Termine und gezieltes
  `rescanOrder`; leere Detailantworten bleiben offen. Storno-Stubs ohne
  Bestelldatum (nur „storniert“-Banner) gelten als nicht berechnete Stornierung
  und blockieren den Abruf nicht. Nicht ladbare Detailseiten bekommen einen
  erneuten Termin statt sofortigem Dauer-Retry.
- Volle Erstattung, volle Rückgabe und nicht berechnete Stornierung: Buchung und Storno standardmäßig **weglassen** (`keepStorno` zum Anzeigen).
- Teilrückgabe und Rückgabe mit restlichem Versand als **Rücksendekosten**.
- Versand, Verpackung, Geschenkverpackung und **Bestelldifferenz** als eigene Buchungen.
- **Lieferadresse** als Umsatzart, Zahlungsart wird mitgeführt.
- Deutsche Bezeichnungen (Erstattung, Rückgabe, Ausgleich).
- Beim **Einrichten** keine Umsätze. Erstimport über mehrere Abrufe; ein
  zweckspezifischer Platzhalter mit Referenz `AMAZON-INCOMPLETE-HARVEST` statt
  „Please reload!“.
- Titelzeile **ungekürzt** (optional `nameMaxLength`).
- Aktuelles Amazon-Seitenlayout (Bestellkarten, Business-SPA,
  Akamai-Zwischenseiten und Kontowechsel). Benötigt der Wechsel während eines
  Abrufs erneut MFA, fordert das Plugin zum Ab- und erneuten Anmelden auf.
- **Fehlerklassifikation beim Login:** Nur eine explizite Ablehnung der
  Zugangsdaten liefert `LoginFailed` und verwirft Cookies. Fehlende oder
  unerwartete Antwortseiten werden als vorübergehender Fehler gemeldet; die
  gespeicherte Session bleibt erhalten.
- **Korrekte Zeichenkodierung:** Amazon-HTML wird entsprechend Amazons
  tatsächlicher Auslieferung als UTF-8 gelesen; veraltete oder falsche
  Charset-Hinweise einzelner Seiten erzeugen dadurch kein Mojibake wie
  `FrÃ¼her`.

## Laufzeit

Der erste Import liest die erreichbare Historie in fortsetzbaren Batches.
Weitere Läufe lesen neue oder geänderte Bestellungen und die jeweils fälligen
Detailprüfungen. Die Dauer hängt von Zahl und Alter der Bestellungen, den
erkannten Unterkonten, Business-Berichts-Jobs, Pagination und Amazon-Antworten
ab; das Plugin garantiert keine feste Laufzeit pro Aktualisierung.

## Haftung

Keine. Wenn das Skript täglich zehn Tonnen Hundefutter bestellt, ist das dein Problem.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
