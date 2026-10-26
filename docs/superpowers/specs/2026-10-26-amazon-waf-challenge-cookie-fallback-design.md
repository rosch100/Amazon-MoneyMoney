# Amazon Bot-Prüfung: native WAF-Challenge, klare Meldungen, Cookie-Fallback

Datum: 2026-10-26

Status: **Entwurf / freigegeben im Brainstorming** — noch nicht implementiert.
Bezug: [Issue #7](https://github.com/rosch100/Amazon-MoneyMoney/issues/7).
Vorarbeit auf Branch `bugfix/claim-challenge-login`: Softblock-Halt (2.06),
`COOKIE:`-Import (2.07).

## Ziel

Nutzer sollen Bot-Prüfung, normales Passwort und OTP klar unterscheiden können.
Wenn Amazon eine AWS-WAF-Softblock-Seite liefert, soll MoneyMoney die Prüfung
wenn möglich **in-app** lösen (Captcha-API). Sonst verständlicher Hinweis und
Session-Import per `COOKIE:…`. Kein Claim hinter ungelöster Softblock-Seite
(vermeidet irreführendes „Passwort falsch“).

## Kontext (warum du ≠ Nolif)

Claim-Collect → Passwort → OTP ist derselbe Ablauf. Unterschiedlich ist, ob
Amazon dem MoneyMoney-Client schon beim ersten `GET www.amazon.de` eine
Bot-Prüfung vorschaltet. MoneyMoney führt kein Seiten-JavaScript aus; ungelöste
Prüfung + Claim → oft „E-Mail oder Passwort nicht korrekt“ ohne OTP. Browser auf
demselben Mac teilt Cookies **nicht** automatisch mit MoneyMoney.

## Ansatz (Priorität)

1. **C — Native MoneyMoney-WAF-Challenge**, wenn `challenge.js` + `sitekey`
   belastbar extrahierbar sind.
2. **A — Klare Fehlermeldung**, wenn C unmöglich oder nach einem Versuch
   gescheitert.
3. **B — `COOKIE:…` im Passwortfeld** jederzeit als Session-Import (auch ohne
   vorherigen Softblock).

## Login-Flow (`InitializeSession2`)

### Schritt 1 — echtes Passwort (kein `COOKIE:`)

1. `GET` Startseite (+ bestehende Akamai-Behandlung).
2. Softblock-Erkennung (`isAmazonAwsWafChallengePage`; logged-in Order-Landing
   zählt nicht als Softblock).
3. Verzweigung:
   - **C möglich:** absolute Script-URL auf `*.token.awswaf.com` (bzw.
     gleichwertig) inkl. `challenge.js` und extrahierbarem `sitekey` →
     Challenge-Tabelle an MoneyMoney; Claim **nicht** starten.
   - **C unmöglich:** leere Schale / kein Sitekey → Fehlertext **A**; Claim
     nicht starten.
4. Startseite „normal“ → Order-List / Claim / Passwort / OTP wie bisher.

### Schritt 2 — WAF-Token (`credentials[1]`)

1. Token nicht als `secPassword` speichern.
2. Nach Amazons erwartetem Muster anwenden (Cookie/`aws-waf-token` und/oder
   Verify, dann denselben Einstieg erneut `GET`).
3. Softblock-Check erneut:
   - weg → Login fortsetzen;
   - noch da oder Token leer → **A**, Claim nicht starten.
4. Maximal **ein** C-Versuch pro Login-Lauf.

### Cookie-Import (`COOKIE:…`)

Wie auf dem 2.07-Pfad: Claim überspringen; Jar in `LocalStorage.cookies`;
Order-Landing prüfen. Pflicht: `session-id` plus Auth-Cookie (`at-acbde` /
`at-main` bzw. `sess-at-*`). Cookie-Blob wird nicht `secPassword`. Softblock
nach Import → A; Sign-in-Landing → eigene „Session abgelaufen“-Meldung.

### Interactive / Hintergrund

Bei `interactive == false`: C nicht anbieten → direkt A (kein Captcha-Dialog im
automatischen Abruf).

## Dialog-Unterscheidung

| Situation | MoneyMoney-UI |
| --- | --- |
| Passwort | Zugangsdaten-Dialog (E-Mail / Passwort) |
| OTP / Claims-Verify | Challenge „Bestätigungscode“ (bestehend) |
| Bot-Prüfung C | Captcha-Dialog, Titel z. B. „Amazon Bot-Prüfung“ |
| Bot-Prüfung ohne C / C fehlgeschlagen | Fehlermeldung A (kein Passwort-Dialog) |
| Echtes Credential-Fail nach normaler Startseite + Claim | Amazon-/`LoginFailed`-Text, nicht mit Bot-Prüfung vermischen |

## Native WAF-Challenge (C) — Details

MoneyMoney-API ([Captcha / Amazon WAF](https://moneymoney.app/api/webbanking/)):

- `challenge` = Script-URL mit Query `sitekey`, `referer` (urlencoded Softblock-
  bzw. Start-URL); optional `type=checkbox` nur wenn die Seite das nahelegt,
  sonst unsichtbar (MoneyMoney versucht zuerst ohne Klick).
- Relative `challenge.js`-URLs gegen die aktuelle Seiten-URL absolut machen.
- Zustand merken (Modulflag / `LocalStorage`), dass der nächste Step ein
  WAF-Token erwartet (analog OTP / `claimsVerify1run`).

Token-Apply-Details gegen echte Softblock-HTML verifizieren; synthetische
Fixtures decken Extraktion und Verzweigung ab.

## Meldungen (A)

Softblock ohne C / C gescheitert (kanonischer Text, ggf. leicht kürzen):

> Amazon: Bot-Prüfung nicht gelöst. Bitte im Browser bei amazon.de anmelden,
> Session mit dem MoneyMoney-Helper als COOKIE:… ins Passwortfeld legen (siehe
> README) und erneut abrufen. Das ist keine falsche Passwort-Meldung.

Weitere:

- Abgelaufene Cookie-Session: eigene Meldung („Cookie-Session abgelaufen… neu
  exportieren“), nicht „Passwort falsch“.
- Cookie-only ohne gespeichertes Passwort bei Schritten, die Passwort brauchen:
  bestehende klare Meldung beibehalten bzw. angleichen.

## Tests

- Softblock mit extrahierbarer URL+Sitekey → Challenge-Tabelle; kein Claim.
- Softblock ohne Sitekey (leere Schale) → String A; kein Challenge; kein Claim.
- Step 2 Token-Stub → Softblock weg → Login-Pfad weiter (Mocks).
- Step 2 Token leer / Softblock bleibt → A; ein Versuch.
- `interactive=false` + lösbare Softblock → A, keine Challenge-Tabelle.
- Bestehend grün: Claim-Collect, COOKIE-Import, Softblock-Halt, Akamai.
- Fixture: synthetisch zuerst; redacted echtes Softblock-HTML aus #7 ergänzen,
  sobald verfügbar.

## Nicht-Ziele

- WAF in reinem libxml2 ohne MoneyMoney-Captcha „knacken“.
- Automatisches Mitlesen von Safari/Chrome-Cookies ohne Import.
- Community-OAuth-Browser-Freigabe (Host-Whitelist).
- Akamai `bm-verify` ersetzen (eigener Pfad bleibt).
- Signierte Website-Release erzwingen (MoneyMoney-Signatur-Prozess).

## Erfolgskriterien

- Bot-Prüfung ≠ Passwort ≠ OTP für den Nutzer erkennbar.
- Lösbare WAF: Login in MoneyMoney ohne Cookie-Paste möglich.
- Nolif-artige Schale ohne Sitekey: klare A-Anweisung; B funktioniert.
- Kein Claim hinter ungelöster Softblock-Seite.
- Issue #7 nach Release mit Verweis auf C→A→B aktualisierbar / schließbar.

## Implementierungsbasis

- Softblock-Erkennung und Halt: bereits (2.06-Linie).
- `COOKIE:`-Import: Branch `bugfix/claim-challenge-login` (2.07) als Basis
  mergen/übernehmen, Meldungstexte an A angleichen.
- Neu: Extraktion Sitekey/URL, Challenge-Return, Token-Apply, ein Versuch,
  `interactive`-Guard, Tests für C.
