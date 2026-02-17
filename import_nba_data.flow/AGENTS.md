# AGENTS.md — `import_nba_data.flow/`

This directory is the **Windmill flow** that imports data from the **official NBA API** (`https://api.nba.com/v0`) into Postgres (schema: `nba`).

This is separate from:
- `import_pcms_data.flow/` (PCMS XML ingest)
- `nba/` (schema design docs + API specs)

---

## Requirements

Environment variables:
- `POSTGRES_URL` — destination database
- `NBA_API_KEY` — sent as an `X-NBA-Api-Key` header on official NBA API requests
- `NGSS_API_KEY` — required for the `ngss.inline_script.py` step

Python dependencies are embedded per-script (via `# /// script` blocks), typically:
- `httpx`
- `psycopg[binary]`

---

## Flow structure (`flow.yaml`)

All steps are raw Python inline scripts:

- `teams.inline_script.py` → `nba.teams`
- `players.inline_script.py` → `nba.players`
- `schedules.inline_script.py` → `nba.schedules`
- `standings.inline_script.py` → `nba.standings`
- `games.inline_script.py` → `nba.games`, `nba.playoff_series`
- `game_data.inline_script.py` → per-game detail tables (boxscore/pbp/hustle/tracking/etc.)
- `aggregates.inline_script.py` → `nba.player_stats_aggregated`, `nba.team_stats_aggregated`
- `lineups.inline_script.py` → `nba.lineup_stats_season`, `nba.lineup_stats_game`
  - `season_backfill` mode: fetches season + game lineups.
  - `refresh`/`date_backfill` modes: defaults to game lineups only (set `NBA_LINEUPS_INCLUDE_SEASON_IN_REFRESH=1` to force season lineups).
  - When `game_ids` is provided, season lineup pulls are scoped to teams in those games.
- `shot_chart.inline_script.py` → `nba.shot_chart`
- `supplemental.inline_script.py` → injuries, alerts, pregame storylines, tracking streams
- `ngss.inline_script.py` → legacy NGSS endpoints (stored as `nba.ngss_*` tables)

The flow input is intentionally simple:
- `save_data` (boolean)
- `league_id` (default `00`)
- `season_label` (e.g. `2025-26`)
- `season_type` (e.g. `Regular Season`)
- `run_mode`: `refresh`, `date_backfill`, or `season_backfill`
- `days_back` (refresh only)
- `start_date`, `end_date` (date backfill only)
- `game_ids` (optional advanced override for game-level steps)
- `only_final_games` (game_data/lineups/shot_chart/ngss)

There are no per-step `include_*` toggles in the flow. It always runs the full pipeline (reference + games + game data + aggregates + lineups + shot chart + supplemental + NGSS).

---

## Running locally

Use the dedicated local runner:

```bash
# default is dry-run (no DB writes)
uv run scripts/test-nba-import.py teams

# date backfill (writes)
uv run scripts/test-nba-import.py games \
  --run-mode date_backfill \
  --start-date 2024-10-01 \
  --end-date 2024-10-02 \
  --write

# season backfill (writes)
uv run scripts/test-nba-import.py all \
  --run-mode season_backfill \
  --season-label 2023-24 \
  --write
```

Notes:
- The runner defaults to dry-run unless you pass `--write`.
- `run_mode=refresh` defaults to `--days-back 2`.

---

## Debugging tips

- Most fetch helpers retry on `429` and `5xx` responses.
- Many endpoints legitimately return `404` for missing game/date payloads; the scripts usually treat `404` as "no data".
- Before changing DB schema, confirm the upstream payload shape (log keys/sample rows).
- `aggregates`, `lineups`, and `shot_chart` each wrap major fetch sections in try/except blocks so a single endpoint failure doesn’t kill the whole step. Errors are collected in each step’s `"errors"` array.

See also:
- `nba/AGENTS.md` — schema design conventions + where the API specs live
- `nba/api/QUERY_TOOL_NOTES.md` — batching, row limits, and practical patterns for the Query Tool API
- `scripts/test-nba-import.py` — canonical local invocation + flags

---

## Shot chart (`nba.shot_chart`)

The `shot_chart` step fetches FieldGoals event data from the Query Tool `/event/player` endpoint and writes to `nba.shot_chart` — a proper table with first-class columns and a `(game_id, event_number)` natural key.

Shot chart uses **batched GameId requests** (50 games per API call via comma-separated `GameId` parameter) to stay under the 10k-row API limit (~180 shots/game × 50 = ~9000).

`shot_chart.inline_script.py` now returns a `telemetry` object with:
- game-list resolution timing
- batch/call counters
- per-batch FieldGoals + TrackingShots timings/row counts
- parse/merge timing
- upsert timing

Current tuning notes (2025-26 regular-season dry-run):
- batch size **50**: ~65–67s, no truncation warnings
- batch size **40**: ~89s (more API calls)
- batch size **60**: triggers split-on-truncation frequently and regresses heavily (~185s)

For one-off backfills there's also a standalone script:

```bash
# dry-run (shows what would be fetched)
uv run scripts/backfill-shot-chart.py

# write, full season
uv run scripts/backfill-shot-chart.py --write

# write, limited batch
uv run scripts/backfill-shot-chart.py --write --limit 50
```

The backfill script is resumable — it only fetches games with no existing `nba.shot_chart` rows.

SQL assertions: `queries/sql/070_nba_shot_chart_assertions.sql`
