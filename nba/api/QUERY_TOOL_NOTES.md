# Query Tool API — Practical Notes

These are empirically discovered behaviors of the NBA Query Tool API
(`https://api.nba.com/v0/api/querytool`). The OpenAPI spec lives in
`nba/api/nba-query-tool.txt`; this file covers the behavior the spec does not.

_Last validated: 2026-02-11 (preprod import testing)_

---

## TL;DR

1. **`GameId` batching works** on game/event endpoints and is the biggest ingest speedup.
2. **Global hard cap is 10,000 rows** (`MaxRowsReturned > 10000` returns 400).
3. **“5,000 row limit” is usually caller-imposed**, not a platform cap.
   - If you request `MaxRowsReturned=5000`, you can silently truncate at 5k.
4. **Omitting `MaxRowsReturned` is endpoint-specific** (not always 10k).
   - Example: `/season/lineups` defaulted to 2000 in tests.
5. Very large `GameId` lists can fail with **414 URI Too Long** before row cap.

---

## Comma-separated `GameId` batching

All tested Query Tool endpoints that accept `GameId` support comma-separated
lists of 10-character game IDs:

```text
GameId=0022500001,0022500002,0022500003,...
```

### Tested endpoints

| Endpoint | Batching works | Notes |
|---|---|---|
| `/event/player` | ✅ | Tested at 10/50 games. Shot chart path in prod flow. |
| `/event/team` | ✅ | Tested at 50 games; returned event-level team rows. |
| `/event/league` | Presumed ✅ | Same pattern; not stress-tested yet. |
| `/game/lineups` | ✅ | Tested at 10/50/200/300 games. 300 hit 10k truncation. |
| `/game/player` | ✅ | Tested at 10/50/200 games (Tracking). |
| `/game/team` | ✅ | Tested at 50 games. |
| `/game/league` | Presumed ✅ | Same pattern; not stress-tested yet. |
| `/season/*` | N/A | Season endpoints are not game-scoped. |

---

## Row limits (`MaxRowsReturned`)

## Hard cap: 10,000

The API enforces a maximum of **10,000** rows:

```json
{"errors": {"MaxRowsReturned": ["Max return is 10000 rows"]}}
```

`MaxRowsReturned > 10000` returns `400`.

## Silent truncation behavior

Truncation happens at the effective row limit and is silent (status `200`).
Signal to watch:

- `meta.rowsReturned` exactly equals the effective cap (e.g., 5000 or 10000)
- row array length equals the same value

## Why 5k shows up in practice

A lot of pipelines set `MaxRowsReturned=5000` for safety. That can create an
accidental **5k ceiling per call**.

Observed examples:

- `/event/player` with 50 games:
  - `MaxRowsReturned=5000` → 5000 rows (truncated)
  - `MaxRowsReturned=10000` → 8873 rows (complete)
- `/season/lineups`:
  - `MaxRowsReturned=5000` → 5000 rows
  - `MaxRowsReturned=10000` → 10000 rows (likely still truncated)

So: **5k is not a global API cap**; it is typically a request choice.

---

## Endpoint defaults when `MaxRowsReturned` is omitted

Defaults are not uniform:

- `/season/lineups` omitted `MaxRowsReturned` returned **2000** rows in tests.
- `/event/player` omitted `MaxRowsReturned` returned **8873** rows in tests
  (same result as explicitly setting 10000 for that batch).

Do not rely on omission. Set explicit limits and detect truncation.

---

## URI length limit (414)

Very large comma-separated `GameId` lists can fail with `414 URI Too Long`
(before row cap is reached).

Observed:

- `/game/player` succeeded at 300 IDs in one test, but consistently failed at
  320+ IDs.

Practical guidance: cap `GameId` batches well below this (e.g., 50–200,
endpoint-dependent).

---

## Throughput notes (empirical)

10-game benchmark (same game set):

- `/game/player` Tracking
  - one-by-one: ~33.7s
  - batched: ~1.0s
- `/game/lineups` Base
  - one-by-one: ~20.0s
  - batched: ~1.2s
- `/event/player` FieldGoals
  - one-by-one: ~19.9s
  - batched: ~1.0s

Batching is usually an order-of-magnitude speedup for refresh/backfill.

---

## Practical batch sizing

Use row-volume estimates + URI safety + endpoint behavior.

| Data type | Rows/game (approx) | Suggested batch size |
|---|---:|---:|
| Shot chart (`/event/player`, FieldGoals) | ~180 | 50 |
| Tracking (`/game/player`, Tracking) | ~22 | 100–200 |
| Game lineups (`/game/lineups`, Base) | ~37 | 100–200 |
| Game lineups (`/game/lineups`, Advanced) | ~37 | 100–150 |

Notes:
- Keep headroom from 10k to avoid silent truncation.
- If `rowsReturned` gets close to the cap, split and retry.

---

## Robust retry/split pattern

```python
rows = payload.get("players") or payload.get("lineups") or payload.get("teams") or []
returned = (payload.get("meta") or {}).get("rowsReturned")

# suspicious: exactly at cap (or near cap if endpoint behavior varies)
if returned is not None and returned >= 9900:
    # split GameId batch and retry
    ...
elif len(rows) >= 9900:
    # fallback signal when meta missing
    ...
```

Also retry on:

- `429 Too Many Requests` (back off 10–15s)
- `504 Gateway Time-out` (back off/retry; especially season-heavy calls)
- `414 URI Too Long` (shrink batch size and retry)

---

## Refresh vs backfill usage

- **Daily refresh (5–15 games):** one batched call per endpoint is usually enough.
- **Season backfill:** split into fixed batches (e.g., 50/100/150), monitor
  `rowsReturned`, and adaptively split if needed.
