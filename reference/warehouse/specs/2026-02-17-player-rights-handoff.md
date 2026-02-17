# Player Rights Handoff — 2026-02-17

## Context
We debugged incorrect NBA draft-rights ownership in `pcms.player_rights_warehouse` (user-reported: Bojan Dubljevic incorrectly on POR).

## Why this got screwed up

### 1) DRLST directionality assumption was wrong
`pcms.refresh_player_rights_warehouse()` historically used DRLST rows with `is_sent = true` as rights holder.

That inverted rights ownership for many players.

### 2) Source semantics are inconsistent enough to require curation
For most rows, DRLST `is_sent = false` aligns with the receiving team (`to_team_code`) and current `people.team_code`.

But one key case (Daniel Diez) conflicts between:
- PCMS `transactions` latest APPR TRADL (2023055): NYK -> POR
- stakeholder expectation + curated notes context: rights should be NYK

So we needed a targeted override.

### 3) Prior assertion coverage was too weak
Assertions only had a single spot-check and no directionality guardrail tied to DRLST row polarity.

## What was changed

### Migrations
- `migrations/083_player_rights_warehouse_use_drlst_receiver.sql`
  - switched DRLST source from sender (`is_sent=true`) to receiver (`is_sent=false`)
- `migrations/084_player_rights_manual_overrides.sql`
  - added initial curated override path for Diez (`player_id=1626229` -> `NYK`)
  - marks override rows as `rights_source='manual_override'`
- `migrations/085_player_rights_overrides_table.sql`
  - introduced durable `pcms.player_rights_overrides` table
  - moved override source from hardcoded CTE to table-backed join in `pcms.refresh_player_rights_warehouse()`
  - added override provenance fields: `reason`, `source_note`, `source_endnote_id`, `created_at`, `updated_at`
  - seeded Diez override in table and added `updated_at` trigger

### Assertions
- Added `queries/sql/075_player_rights_trade_direction_assertions.sql`
  - trade-derived rows must come from DRLST receiver rows
  - Bojan must resolve to NYK for trade `2022107`
  - Diez must resolve to NYK via `manual_override`
- Added `queries/sql/076_player_rights_overrides_assertions.sql`
  - manual override rows must match active rows in `pcms.player_rights_overrides`
  - active NBA ACT/CDL overrides must appear in warehouse as `manual_override`
  - active override team codes must resolve to real teams
- Updated `queries/sql/052_player_rights_warehouse_assertions.sql` note for Diez
- Wired into `queries/sql/run_all.sql`

## Current known state

### Confirmed rows
- Bojan Dubljevic (`203532`) -> NYK (`trade_team_details`, trade `2022107`)
- Daniel Diez (`1626229`) -> NYK (`manual_override`, source trade `2023055`)

### Health snapshot
- NBA draft-rights rows by source:
  - `trade_team_details`: 57
  - `people`: 46
  - `manual_override`: 1
- Mismatch vs latest APPR TRADL `to_team_code` among trade/manual rows: **1** (Diez only)
- Mismatch vs `people.team_code` for NBA ACT/CDL rights rows: **1** (Diez only)

## Quick diagnostic queries for future debugging

### 1) Show current anomalous rows vs latest APPR TRADL `to_team`
```sql
WITH latest_tradl AS (
  SELECT DISTINCT ON (player_id)
    player_id, to_team_code, from_team_code, trade_id, transaction_id, transaction_date
  FROM pcms.transactions
  WHERE player_id IS NOT NULL
    AND league_lk='NBA'
    AND record_status_lk='APPR'
    AND transaction_type_lk='TRADL'
  ORDER BY player_id, transaction_date DESC NULLS LAST, seqno DESC NULLS LAST, transaction_id DESC
)
SELECT
  prw.player_id,
  prw.player_name,
  prw.rights_team_code,
  prw.rights_source,
  lt.trade_id,
  lt.from_team_code,
  lt.to_team_code
FROM pcms.player_rights_warehouse prw
JOIN latest_tradl lt ON lt.player_id=prw.player_id
WHERE prw.rights_kind='NBA_DRAFT_RIGHTS'
  AND prw.rights_source IN ('trade_team_details','manual_override')
  AND prw.rights_team_code IS DISTINCT FROM lt.to_team_code
ORDER BY prw.player_name;
```

### 2) Inspect DRLST polarity for a player
```sql
SELECT
  ttd.player_id,
  p.display_last_name || ', ' || p.display_first_name AS player_name,
  ttd.trade_id,
  tr.trade_date,
  ttd.team_code,
  ttd.seqno,
  ttd.is_sent,
  ttd.trade_team_detail_id
FROM pcms.trade_team_details ttd
JOIN pcms.trades tr ON tr.trade_id = ttd.trade_id
LEFT JOIN pcms.people p ON p.person_id = ttd.player_id
WHERE ttd.trade_entry_lk='DRLST'
  AND ttd.player_id IN (203532, 1626229)
ORDER BY ttd.player_id, tr.trade_date, ttd.trade_id, ttd.seqno, ttd.team_code;
```

## Follow-up TODO (important)
1. Build an anomaly report joining:
   - `player_rights_warehouse`
   - latest APPR TRADL transactions
   - curated notes/endnotes where available
2. Decide policy precedence explicitly:
   - transaction feed vs curated rights workbook evidence when they disagree.
3. Add lightweight workflow/docs for maintaining `pcms.player_rights_overrides`
   (who can edit, required provenance fields, review cadence).

## One-line summary
Most rights were inverted due DRLST sender logic; fixed to receiver, with one curated exception (Diez -> NYK) now managed via durable table-backed override.
