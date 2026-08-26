# Amazon Unterkonten via ListAccounts

Datum: 2026-08-25

## Ziel

- „Nach neuen Konten suchen“: **nur** Konten ermitteln, **keine** Umsätze laden.
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
- MFA/`auth_prompt` beim Wechsel nur im Refresh-/Harvest-Pfad.
