# Task 3 Report: ListAccounts Namen und Nummern

## Status

Erledigt. `ListAccounts` liefert jetzt ein gemeinsames Konto mit dem Wert
`secUsername` als Kontonummer und dem Namen `Amazon`. Entdeckte vollständige
Unterkonten werden mit ihrer Customer-ID als Kontonummer und mit dem
fachlichen Namen (`customerName` bzw. `businessName`) als `Amazon ...`
angeboten.

Einträge ohne Customer-ID oder ohne fachlichen Anzeigenamen werden nicht
gespeichert. Fehlt `secUsername`, schlägt `ListAccounts` explizit fehl.
Bestehende Konto-Flags und `AccountTypeOther` bleiben erhalten.

## Tests

- `./test/run.sh test/test_list_accounts.lua`
- `for test_file in test/test_*.lua; do ./test/run.sh "$test_file" || exit 1; done`
- `git diff --check`

Alle Tests bestanden.

## Regressionsanpassungen

Tests für neue ListAccounts-Konten verwenden jetzt E-Mail bzw. Customer-ID.
Legacy-Refresh-Pfade mit `mix` und `sub:*` bleiben in den bestehenden Tests
erhalten.

## Hinweise

Die IDE-Lintdiagnostik meldet weiterhin neun bereits vorhandene Lua-Typwarnungen
in `amazon-orders.lua` (u. a. HTML-Dictionary-Felder und dynamische
Aufrufe); durch diese Änderung wurden keine neuen Warnungen festgestellt.
