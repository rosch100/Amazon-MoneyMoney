# Incremental Harvest nach Erstimport

Datum: 2026-09-05  
Status: **Umgesetzt** (2026-09-05). Plan:
`docs/superpowers/plans/2026-09-05-amazon-incremental-harvest.md`.

## Ziel

Nach abgeschlossenem initialem Vollabruf nur noch **neue** Bestellungen und
**selektive** Refund-/Retoure-Nachschauen laden — Abrufdauer minimieren.

## Entscheidungen

| Punkt | Wahl |
| --- | --- |
| Listen-Cutoff | **C:** `max(MoneyMoney-since, neueste Cache-bookingDate) − 14 Tage` |
| Refund-Watch | **90 Tage**, nur Kandidaten |
| Ansatz | **1** (Liste eng + selektive Details) |

## Verhalten

### Erstimport / Full Harvest

Unverändert: `since=0`, leerer Cache, stale `since` (>366 Tage) oder offener
Initial-Sync → volle Historie wie heute.

### Inkrementell (nach erfolgreichem Vollabruf)

1. **Bestellliste / Filter / ABA-CUSTOM_RANGE**
   - Cutoff = `max(refreshSince, newestBookingInOrderCache) − 14d`
   - Nur Zeitfilter/Seiten, die diesen Cutoff schneiden
   - Keine Jahr-Filter weit unter dem Cutoff

2. **Details-Refund-Watch**
   - Fenster: `bookingDate >= now − 90d` (statt 366d)
   - Nur emittierte Orders des Kontos
   - Ausschluss: `unbilledCancel`
   - Ausschluss: bereits vollständig abgerechnet
     (`orderHasReturnActivity` und Refund-Summe ≥ `effectiveReturnedCents`)
   - `detailsDate > now` weiter respektieren (kein Force-Requeue)

3. **Offene Details-Queue**
   - Unverändert: Orders ohne fertige Details bleiben due (limitiert pro Refresh)

4. **Session-Optimierungen (weniger Switches / Probes)**
   - Discovery: vollständiger `discoveredSubAccounts`-Cache → kein Switcher
   - Listen-Harvest überspringen wenn letzter Scan-Wall-Clock (`lastListHarvestAt`)
     < `incrementalListMinRescanSec` (4h) und nur Details due → kein
     `scanAllAmazonSubAccounts` (`lastHarvestSince` = MoneyMoney-since-Watermark)
     (gilt auch nach Re-Login; neuer Login forciert Listen-Harvest nur wenn der
     Scan nicht mehr frisch ist oder kein Incremental-Modus greift)
   - Persönlich: bei `scanFiltersMonths < 3` kein `months-3` / „letzten 3 Monaten“
   - Business inkrementell: direkt ABA (`collectBusinessSpaOrders`), keine SPA-Probes
   - `ensureAmazonSubAccountSession`: Switcher-Skip nur wenn HTML bereits zum Kind passt

## Nicht-Ziele

- Keine Änderung der Buchungslogik (Ausgleich, Storno-Semantik)
- Kein Verzicht auf Vollabruf bei leerem Cache / Erstimport / Cache-Reset
- Kein Scraping des Message Centers

## Erfolgskriterien

- Inkrementeller Refresh loggt Cutoff und queued deutlich weniger Refund-Watches
  als zuvor (366d → ≤90d + Filter)
- Tests für Cutoff, Kandidatenfilter und Scan-Monats-Ableitung
- Bestehende Harvest-/Akamai-Tests bleiben grün

## Evidenz Refund-Fenster

Amazon DE: Erstattung max. 14 Tage nach Bearbeitung + bis 7 Werktage Bank;
„manchmal länger“. Praxis/Recherche: typisch 30–90 Tage ab Bestellung bis
sichtbarer Erstattung auf Bestelldetails; >90 Tage Ausnahme.
