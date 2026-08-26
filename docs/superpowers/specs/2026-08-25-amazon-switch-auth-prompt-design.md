# Amazon Kontowechsel: `auth_prompt` (Passwort)

Datum: 2026-08-25

## Problem

Wechsel zu Business (`Example GmbH`) liefert oft
`redirectUrl` → `/ap/signin?...&switch_account=auth_prompt` mit Passwort-Form
(kein OTP). Plugin brach mit `switch landed on interactive login` ab.

## Lösung

1. Nach Switch-Redirect: wie bisher MFA erkennen.
2. Sonst bei Sign-in+Passwort: **einmal** Passwort (und ggf. E-Mail) aus
   `secPassword`/`secUsername` absenden (`submitSwitchAuthPrompt`).
3. Ergebnis erneut durch `finishAccountSwitchLanding` (MFA-Challenge oder OK).
4. Zweiter Passwort-Prompt oder fehlende Credentials → klarer Fehler (kein Loop).

## Nicht im Scope

- Separater MoneyMoney-Challenge nur fürs Passwort (Credentials sind schon da).
- Captcha-Sonderpfade jenseits bestehender Login-Logik.
