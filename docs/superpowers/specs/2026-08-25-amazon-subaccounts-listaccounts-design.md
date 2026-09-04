# Amazon Unterkonten via ListAccounts

Datum: 2026-08-25

Status: **Historisch / überholt** durch
`2026-09-04-amazon-account-names-and-numbers-design.md`. Ursprünglich
implementiert; Neuangebote mit `mix` / `sub:personal` / `sub:business` sind
obsolet. Verifiziert durch `test/test_list_accounts.lua`,
`test/test_account_setup_no_harvest.lua` und die
`test/test_initial_sync_*.lua`-Tests.

## Ziel

- Beim Login Unterkonten entdecken; „Nach neuen Konten suchen“ listet diese
  anschließend, lädt aber **keine** Umsätze.
- Standard-Angebot: gemeinsames „Amazon …“ (`accountNumber=mix`).
- Wenn der CVF-Switcher **mehrere** Amazon-Unterkonten findet: zusätzlich
  `sub:personal` / `sub:business` zur Auswahl.
- Nutzer entscheidet in MoneyMoney erst dann: nur gemeinsam, und/oder getrennte
  Unterkonten anlegen.
- Umsätze (`RefreshAccount` / `scanAllAmazonSubAccounts`) erst nach dieser Wahl.
- Keine `normal`/`inverse`/`monthly`/`yearly`-Konten mehr in `ListAccounts`
  (Refresh bleibt kompatibel für Altbestände).

## Technik

- Login/`InitializeSession2`: `discoverAmazonSubAccounts()` (Switcher öffnen +
  parsen, kein Kontowechsel, kein Order-Harvest).
- `LocalStorage.discoveredSubAccounts`: `{kind, label, accountNumber}`.
- Keys: `sub:personal`, `sub:business`.
- `ListAccounts`: `mix` immer; bei `#discovered > 1` zusätzlich die Subs.
- Orders: `subAccountKind` beim Harvest in Refresh; Filter nach Konto.
- Wechsel-Authentifizierung liegt nur im Refresh-/Harvest-Pfad:
  `auth_prompt` wird mit den vorhandenen Zugangsdaten einmal direkt beantwortet;
  verlangt Amazon beim normalen Refresh erneut MFA, bricht der Scan mit der
  Aufforderung zum Ab- und erneuten Anmelden ab.
