# Amazon Bestellungen 2.10 beta

Diese Testversion bündelt die Änderungen an Kontenauswahl, Buchungsarten,
Transaktions-IDs und Zeitraumfilter.

## Änderungen

- Privat-, Geschäfts- und Gesamtkonto klar getrennt auswählbar.
- Buchungsarten `normal`, `inverse`, `mix`, `monthly` und `yearly`.
- Stabile Transaktions-IDs für gleiche Positionen, Periodenausgleiche und
  erneute Importe.
- `scanFiltersMonths` begrenzt den Importzeitraum einschließlich des
  Erstimports. Die Business-Berichte werden bei geändertem Zeitraum neu
  eingeplant; Bestellungen am Stichtag werden vollständig berücksichtigt.
- Bereinigter Umgang mit dem internen Amazon-Port in URLs und Login-Daten.
- Der Jahresfilter-Test verwendet einen festen Zeitpunkt und bleibt unabhängig
  vom Datum der Testausführung.

## Testhinweise

Bitte die Einstellungen für Kontoauswahl, `ledgerMode` und `scanFiltersMonths`
prüfen. Für einen anderen Buchungsmodus oder ein geändertes Scanfenster die
Hinweise in der README beachten. Ein `resetCache` löscht den Import-Cache, aber
nicht bereits in MoneyMoney gespeicherte Umsätze oder Sammelbuchungen.
