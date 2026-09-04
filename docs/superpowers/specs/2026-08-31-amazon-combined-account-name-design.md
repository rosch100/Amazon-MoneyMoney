# Amazon: Name des gemeinsamen Kontos

Datum: 2026-08-31

Status: **Historisch / überholt** durch
`2026-09-04-amazon-account-names-and-numbers-design.md`.

## Ziel

Wenn Amazon ein persönliches und ein geschäftliches Unterkonto meldet, verwendet
das gemeinsame MoneyMoney-Konto beide unveränderten Amazon-Bezeichnungen:

`Amazon <persönliches Label> + <geschäftliches Label>`

Beispiel: `Amazon Persönliches Konto + Example GmbH`.

## Verhalten

- Die interne Kontonummer bleibt aus Kompatibilitätsgründen `mix`.
- Die Labels stammen aus `LocalStorage.discoveredSubAccounts`.
- Die Ausgabe ist unabhängig von der Switcher-Reihenfolge stets persönlich,
  dann geschäftlich.
- Nur wenn beide Labels vorhanden sind, wird der kombinierte Name gebildet.
- Ohne vollständig erkanntes Paar bleibt der bestehende Name
  `Amazon Alle Konten`.
- Namen der einzelnen Unterkonten, Harvest, Cache und Migration bleiben
  unverändert.

## Implementierung

Eine fokussierte Hilfsfunktion liefert den Suffix für das gemeinsame Konto.
`ListAccounts` verwendet diesen Suffix statt der Konstanten
`combinedAccountListName`. Bestehende Discovery-Daten werden nur gelesen; es
wird kein abgeleiteter Name zusätzlich persistiert.

## Tests

`test/test_list_accounts.lua` prüft:

1. den bisherigen Namen ohne Discovery,
2. die Kombination beider Amazon-Labels,
3. die stabile Reihenfolge bei umgekehrter Switcher-Reihenfolge,
4. die unveränderte interne Kontonummer `mix`.

Die Benutzer- und Entwicklerdokumentation wird an den neuen Anzeigenamen
angepasst.
