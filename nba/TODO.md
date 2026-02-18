# NBA Import — Query Tool batching + hybrid ingest TODO

Assessment dates: 2026-02-09 → 2026-02-11

This tracks follow-up work to speed up `import_nba_data.flow/` by using **Query Tool batching** where it’s a clear win, while keeping **legacy `/api/stats/*`** endpoints where they provide important semantics/metadata.

Related: `nba/api/QUERY_TOOL_NOTES.md`

---

## Current state (preprod reality check)

Observed in `$POSTGRES_URL`:

- `nba.games`: **816 total / 801 final**
- Query Tool path proven:
  - `nba.shot_chart`: **801 games** (fully populated; batched Query Tool)
- Underfilled / missing (obvious next wins):
  - `nba.tracking_stats`: **10 games**
  - `nba.lineup_stats_game`: **0 games**
- Legacy game-data tables are only partially populated (expected for preprod):
  - `nba.boxscores_traditional`: **13 games**
  - `nba.boxscores_advanced`: **13 games**

Interpretation: **shot chart is the success case**; tracking + game lineups are the next most valuable batching upgrades.

---

## What we’re optimizing for

1) **Fast season backfills** (reduce call count by batching `GameId`)
2) **Fast daily refresh** (batch the last N games in one request)
3) **No accidental semantic regressions** (especially boxscore “roster/DNP metadata”)

---

## What Query Tool is great for (high leverage)

These endpoints support **comma-separated `GameId` batching** and have stable, upsert-friendly keys:

- `/event/player` (`EventType=FieldGoals`, `SumScope=Event`) → `nba.shot_chart` (already good)
- `/game/player` (`MeasureType=Tracking`) → `nba.tracking_stats`
- `/game/lineups` (`MeasureType=Base|Advanced`) → `nba.lineup_stats_game`

---

## What Query Tool is *not* a drop-in replacement for

### Boxscore semantics + roster metadata

Legacy `/api/stats/boxscore` includes player rows and metadata the Query Tool **does not** provide:

- `status`
- `notPlayingReason`, `notPlayingDescription`
- `order` / rotation order
- `jerseyNum`
- `oncourt`, `played`

Also: Query Tool `/game/player MeasureType=Base` tends to return **fewer players** (played players only), so it can’t fully reproduce “full roster incl. DNP” semantics without additional sources.

### No Query Tool equivalent

These remain legacy forever:

- Play-by-play: `/api/stats/pbp`
- Players-on-court: `/api/stats/poc`
- Hustle: XML feeds (`/api/hustlestats/*`)

---

## Empirical constraints (must design around)

### 10,000 row hard cap + silent truncation

- `MaxRowsReturned > 10000` → `400`
- `MaxRowsReturned=10000` can still truncate silently.
- The only reliable signal is `meta.rowsReturned == 10000` (or “suspiciously close”, e.g. `>= 9900`).

### URI length (414)

- Very large comma-separated `GameId` lists can hit `414 URI Too Long`.
- Observed failures around **320+ game IDs** in a single request.

### Timeouts / 504

- Some endpoints are expensive at scale.
- In practice, `/game/lineups MeasureType=Advanced` is **timeout-sensitive** with large batches.

---

## Guardrails (required for *every* Query Tool use)

- Always set `MaxRowsReturned` explicitly.
- Always read `meta.rowsReturned` and compare to your expected range.
- Treat `rowsReturned >= 9900` as truncation risk → **split batch and retry**.
- On `414` → **split batch and retry**.
- On `429` → backoff 10–15s and retry.
- On `504`/timeouts → retry; if it persists, **split batch**.
- Log: endpoint, `MeasureType`/`Measures`, batch size (#games), and `rowsReturned`.

---

## Batch-size policy (starting points, then tune)

These are “safe defaults” from live testing (not theoretical maxima):

- `/event/player` FieldGoals (`SumScope=Event`): **50 games/batch**
  - 80 games hit the 10k cap in tests.
- `/game/player` Tracking: **50–100 games/batch**
  - Watch for 414; split as needed.
- `/game/lineups` Base: **50–200 games/batch**
- `/game/lineups` Advanced: **25–50 games/batch**
  - 100+ games/batch caused `504` in tests.

`MaxRowsReturned` defaults:
- Use **10000** for any batched `/event/*` or `/game/*` calls.
- Avoid leaving older constants like 5000 in place once batching is introduced (that becomes caller-imposed truncation).

---

## Implementation plan

### Phase 1 — immediate wins (no boxscore semantic changes)

- [x] **Batch tracking stats in `import_nba_data.flow/game_data.inline_script.py`**
  - Changed `/game/player?MeasureType=Tracking` from per-game calls to batched `GameId` calls.
  - Uses `MaxRowsReturned=10000`.
  - Initial batch size is **100**.
  - Added adaptive split/retry for truncation (`rowsReturned>=9900`) and 414.

- [x] **Batch game lineups (now in `import_nba_data.flow/lineups.inline_script.py`)**
  - Changed `/game/lineups` from per-game loops to batched `GameId` calls.
  - Increased `MaxRowsReturned` to **10000** for batched pulls.
  - Current initial batch sizes:
    - Base: **250**
    - Advanced: **250**
  - Added adaptive split/retry for truncation and 414/429/5xx.

- [x] **Reduce season lineup truncation risk**
  - `LINEUP_MAX_ROWS` increased to 10000.
  - Added explicit truncation warnings using `meta.rowsReturned` and row count checks.
  - Removed league-wide fallback for `/season/lineups`; now team-scoped IDs are required.
  - Added TeamId batching (`LINEUP_SEASON_TEAM_BATCH_SIZE=10`) so season pulls run in ~3 calls per combo instead of 30.

- [x] **Stop refresh runs from doing full-season season-lineup pulls by default**
  - Lineups moved out of `aggregates` into `import_nba_data.flow/lineups.inline_script.py`.
  - `lineups` now defaults to:
    - `season_backfill`: season + game lineups
    - `refresh` / `date_backfill`: game lineups only
  - Override available via env var: `NBA_LINEUPS_INCLUDE_SEASON_IN_REFRESH=1`.

- [x] **Instrument + tune shot chart batching in `import_nba_data.flow/shot_chart.inline_script.py`**
  - Added structured `telemetry` payload: game selection timing, batch/call counters, per-batch FG/Tracking timings + row counts, parse/merge timing, upsert timing.
  - Added adaptive split/retry for 414/429/5xx + truncation signals (`rowsReturned >= 9900`).
  - Benchmarked 2025-26 regular-season dry-run:
    - Batch 40: ~89s
    - Batch 50: ~65–67s (best)
    - Batch 60: ~185s (frequent split-on-truncation)

- [x] **Split Query Tool event streams out of `game_data` and add `game_data` telemetry/concurrency**
  - New step/script: `import_nba_data.flow/querytool_event_streams.inline_script.py` now owns `nba.querytool_event_streams`.
  - `game_data.inline_script.py` now focuses on boxscore/pbp/poc/hustle + batched tracking/defensive/violations.
  - `game_data` now includes structured `telemetry` and uses bounded per-game concurrency (`GAME_DATA_CONCURRENCY=4`) for legacy per-game endpoints.

- [x] **Add coverage-aware season backfill skipping + tenacity retry guards**
  - `game_data` and `querytool_event_streams` now skip already-populated games by section/event-type when running `season_backfill` (and no explicit `game_ids`).
  - JSON HTTP calls now use tenacity retry wrappers (max 4 attempts, exponential backoff, extra delay on 403).
  - TrackingPasses batch seed moved to **16**; 200-game sample benchmark was faster vs 15 with no split events.

### Phase 2 — optional / careful migrations

- [ ] **Boxscore migration (optional; only if we preserve semantics)**
  - Keep legacy `/api/stats/boxscore` as the “semantic truth” for roster/DNP metadata.
  - If we batch Query Tool for numeric stat lines (`/game/player`, `/game/team`), keep a legacy call for metadata *or* explicitly change table meaning.
  - Quick parity note (2026-02-17): `/game/player?MeasureType=Advanced` returned fewer players than legacy boxscore Advanced in sample game `0022500001` (20 vs 27; 7 IDs present only in legacy). Revisit with a broader parity audit before migrating advanced tables.

- [ ] **Season aggregates (optional)**
  - Keep legacy `/api/stats/player` + `/api/stats/team` by default (fast + stable).
  - If revisiting Query Tool:
    - Use `Measures=Base,Advanced,Misc,Scoring(,Opponent)` (comma-separated `MeasureType` is invalid).
    - Benchmark performance + compare columns before switching.

---

## Assertions to add (to prevent “fast but incomplete”)

- [ ] `tracking_stats` coverage: `COUNT(DISTINCT game_id)` vs final games.
- [ ] `lineup_stats_game` coverage: `COUNT(DISTINCT game_id)` vs final games.
- [ ] Truncation sentinels: flag runs where `rowsReturned == 10000` occurs frequently.
- [ ] (If season lineups remain) sanity checks:
  - team-scoped `/season/lineups?TeamId=...` returns only one `teamId` in payload
  - league-wide pulls without `TeamId` are expected to truncate (and should be treated as “top-N”, not exhaustive)
