# AGENTS.md — `scripts/`

This folder is for **local development runners** and one-off utilities.

If you’re debugging an ingest, start with the `test-*-import.py` scripts — they let you run Windmill inline scripts locally, with a consistent `--dry-run` / `--write` interface.

---

## The three local runners

### PCMS (XML → JSON → `pcms.*`)
- Runner: `scripts/test-import.py`
- Runs scripts from: `import_pcms_data.flow/`

```bash
# default is dry-run
uv run scripts/test-import.py lookups

# write to DB
uv run scripts/test-import.py transactions --write

# all steps
uv run scripts/test-import.py all --write
```

### NBA official API → `nba.*`
- Runner: `scripts/test-nba-import.py`
- Runs scripts from: `import_nba_data.flow/`

```bash
uv run scripts/test-nba-import.py teams
uv run scripts/test-nba-import.py game_data --run-mode date_backfill --start-date 2024-10-01 --end-date 2024-10-02 --write
uv run scripts/test-nba-import.py all --run-mode season_backfill --season-label 2023-24 --write
```

### SportRadar → `sr.*`
- Runner: `scripts/test-sr-import.py`
- Runs scripts from: `import_sr_data.flow/`

```bash
uv run scripts/test-sr-import.py games --source-api nba --date 2026-01-28
uv run scripts/test-sr-import.py all --write
```

---

## JSON generation / inspection helpers

### `scripts/xml-to-json.py`
Local **PCMS XML → clean JSON** converter (mirrors Step A).

```bash
uv run scripts/xml-to-json.py \
  --xml-dir shared/pcms/nba_pcms_full_extract_xml \
  --out-dir shared/pcms/nba_pcms_full_extract
```

### TypeScript scratch tools
These are convenience utilities for poking at nested JSON:
- `inspect-json-structure.ts`
- `show-all-paths.ts`
- `parse-xml-to-json.ts`

(They’re optional; most production ingest code is Python.)

---

## Common env vars

- `POSTGRES_URL` — required for any `--write` mode
- `NBA_API_KEY` — required for NBA API imports (`import_nba_data.flow/`)
- `NGSS_API_KEY` — required if running the NBA NGSS step (`import_nba_data.flow/ngss.inline_script.py`)
- `SPORTRADAR_API_KEY` — required for SportRadar imports (`import_sr_data.flow/`)

---

## Gotchas

- All runners default to **dry-run** unless you pass `--write`.
- If edits to inline scripts don’t seem to take, clear pycache:
  ```bash
  rm -rf import_pcms_data.flow/__pycache__ import_nba_data.flow/__pycache__ import_sr_data.flow/__pycache__
  ```
