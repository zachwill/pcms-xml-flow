# NBA Import — Query Tool Migration TODO

Assessment dates: 2026-02-09 to 2026-02-11

This tracks follow-up work to improve `import_nba_data.flow/` using Query Tool
batching where it helps, while keeping legacy endpoints where they remain the
better fit.

Related: `nba/api/QUERY_TOOL_NOTES.md`

---

## Decisions from latest assessment

1. **Use Query Tool batching more aggressively for game-level backfill/refresh**
   (`/event/*`, `/game/*` endpoints).
2. **Keep a hybrid model** (do **not** force full migration off `/api/stats/*`).
3. **Do not treat 5k as an API hard cap**.
   - Global hard cap is 10k.
   - 5k ceilings are often caller-imposed (`MaxRowsReturned=5000`).
4. **Add split/retry guardrails** for both row cap and URI size limits.

---

## Key empirical findings (preprod)

### 1) Batching is much faster than one-call-per-game

10-game benchmark:

- `/game/player` Tracking: ~33.7s → ~1.0s batched
- `/game/lineups` Base: ~20.0s → ~1.2s batched
- `/event/player` FieldGoals: ~19.9s → ~1.0s batched

### 2) 10k is the true hard cap; 5k is often self-inflicted

- `MaxRowsReturned > 10000` returns `400`.
- Setting `MaxRowsReturned=5000` can silently truncate at 5k.
- Omitting `MaxRowsReturned` is endpoint-specific (e.g. `/season/lineups`
  defaulted to 2000 in tests).

### 3) URI length can fail before row cap

- Very large `GameId` lists can return `414 URI Too Long`.
- Observed failures around 320+ game IDs in one request.

### 4) Query Tool is not a complete boxscore replacement yet

Compared to legacy `/api/stats/boxscore`, Query Tool game/player responses have
schema/semantics differences (especially around full roster + not-playing
metadata). Keeping legacy boxscore calls currently preserves expected table
shape and semantics.

---

## Current data shape observations (preprod)

- `nba.shot_chart` is fully populated for all final games (good Query Tool path).
- `nba.tracking_stats` and `nba.lineup_stats_game` are underfilled relative to
  final games, indicating immediate wins from batched game-level backfill.
- `nba.lineup_stats_season` currently uses `LINEUP_MAX_ROWS=5000` in flow;
  this likely risks silent truncation for league-wide pulls.

---

## Implementation plan

## Phase 1 — High priority

- [ ] **Batch tracking backfill/refresh in `game_data.inline_script.py`**
  - Move `/game/player?MeasureType=Tracking` from per-game calls to batched
    `GameId` calls.
  - Start with batch size 100 (or 50), then tune.
  - Add split/retry for truncation and 414.

- [ ] **Batch game lineups in `aggregates.inline_script.py`**
  - Move `/game/lineups` from per-game loops to batched `GameId` calls.
  - Start with Base=100–200, Advanced=100–150.
  - Add split/retry for truncation and 414.

- [ ] **Fix season lineup truncation risk**
  - Audit `/season/lineups` strategy (team-scoped pulls vs league-wide).
  - Avoid relying on `MaxRowsReturned=5000` as a steady-state cap.
  - Add explicit truncation checks (`meta.rowsReturned` and row length).

## Phase 2 — Medium priority

- [ ] **Evaluate optional Query Tool use for season aggregates**
  - Keep current `/api/stats/player` + `/api/stats/team` by default (faster in
    current tests).
  - Revisit only if schema simplification or incremental behavior justifies it.

- [ ] **Evaluate game/player + game/team Base/Advanced migration for boxscore stats**
  - Only proceed if we can preserve `boxscores_*` semantics or explicitly accept
    schema behavior changes.

## Out of scope (no known Query Tool replacement)

- [ ] Keep existing sources for:
  - Play-by-play (`/api/stats/pbp`)
  - Players-on-court (`/api/stats/poc`)
  - Hustle XML feeds (`/api/hustlestats/*`)

---

## Guardrails to implement everywhere Query Tool is used

- [ ] Always set explicit `MaxRowsReturned`.
- [ ] Treat `meta.rowsReturned` at/near cap as truncation signal.
- [ ] Retry on 429/5xx with backoff.
- [ ] On 414, reduce batch size and retry.
- [ ] Log request batch size + rows returned for observability.

---

## Suggested assertions to add

- [ ] `tracking_stats` coverage vs final games (distinct `game_id` ratio).
- [ ] `lineup_stats_game` coverage vs final games.
- [ ] Truncation sentinel checks (unexpectedly frequent `rowsReturned==cap`).

---

## Expected impact

Hybrid migration (batching game-level Query Tool paths) should significantly
reduce wall-clock backfill/refresh time without sacrificing legacy boxscore
metadata fidelity.
