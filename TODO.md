# TODO — Draft Assets (Picks + Rights) + Endnotes Integration

Status: **2026-01-23**

This repo is already strong on **Salary Book / Team totals / Exceptions / Trade TPE math**.

The biggest gap vs “Sean-style” tooling is **draft assets**:
- **Draft picks** (owned/owed, protections, swaps, conditional branches)
- **Draft rights / returning rights** (who controls a player’s rights)
- A human-auditable **endnotes layer** that explains and powers those draft assets

The goal is the same pattern as existing tooling:
- **Tool-facing warehouse tables** in `pcms.*_warehouse`
- **Refresh functions** (`pcms.refresh_*`) called by `import_pcms_data.flow/refresh_caches.inline_script.py`
- **Assertion-style SQL checks** in `queries/sql/`

---

## 0) Ground rules / invariants (do not regress)

1) **Postgres is the source of truth**
- Tooling reads `pcms.*_warehouse` (not JSON, not ad-hoc parsing at runtime).

2) **Preserve missingness**
- Tool-friendly booleans are OK, but keep `has_*` / `*_source` / `*_id` fields so we can distinguish “false” from “unknown / absent in source”.

3) **Keep “raw fidelity” alongside derived fields**
- For draft assets, *raw text* is often the only authoritative representation of protections / conditionals.
- Warehouses should retain `raw_text`, `raw_fragment`, `endnote_refs[]`, etc. for debugging.

---

## 1) Current relevant tables (already exist)

### Draft picks
- `pcms.draft_pick_summaries` (2018–2032)
  - Per-team-per-year **human text** for 1st/2nd round pick situations.
- `pcms.draft_pick_trades` (trade events; years out to 2032)
  - Structured pick movement events from PCMS trade details.
  - Has: `is_swap`, `is_conditional`, `conditional_type_lk`, `original_team_*`, `from_team_*`, `to_team_*`.
- `pcms.draft_selections` (historical draft outcomes)
  - What actually happened for completed drafts.

### Rights signals
- `pcms.transactions.rights_team_id` / `rights_team_code`
  - Populated heavily (primarily DLG “returning rights” patterns show up via `transaction_type_lk='TRDRR'`, `to_player_status_lk='URETP'`, etc.).
- `pcms.people.dlg_returning_rights_team_id/team_code` and `dlg_returning_rights_salary_year`

### Endnotes scaffold
- `pcms.endnotes` table exists but is currently **empty**.
  - Columns include: `original_note`, `revised_note`, `explanation`, `conditions_json`, `metadata_json`, pick-ish columns, etc.

External curated source:
- `~/blazers/cba-docs/endnotes/revised/*.txt`

Important observation:
- The draft-pick summary strings include parenthetical endnote refs like `(194)`.
- The curated endnote files are keyed by the same IDs (e.g. `194_*.txt`).
- This gives us a clean bridge: **summary refs → `pcms.endnotes.endnote_id`**.

---

## 2) P0 — Ingest curated endnotes into `pcms.endnotes`

### Why
To reach Sean-level fidelity, we need to model constructs like:
- “less favorable of …”
- “swap right deemed exercised / extinguished”
- “Result Pick” definitions
- conditional substitutions based on other endnotes (dependency graph)

These are present in curated endnotes and are not reliably derivable from PCMS event tables alone.

### Deliverables

#### 2.1 Script: `scripts/import-endnotes.py` (or `.ts` on Bun, but Python is fine)
- Reads `~/blazers/cba-docs/endnotes/revised/*.txt`
- Extracts fields (best-effort):
  - `endnote_id` (required)
  - `trade_date`
  - `status`
  - `trade_summary` (if present)
  - `conveyance` section (if present)
  - `original_text` (the “ORIGINAL TEXT:” or “VERBATIM ORIGINAL:” block)
- Upserts into `pcms.endnotes`.

Storage strategy:
- Put the raw file + parsed fields into:
  - `revised_note` (verbatim “ORIGINAL TEXT”)
  - `explanation` (structured bullets if present)
  - `metadata_json` (everything else, including source file, parse_version)
  - `conditions_json` (optional JSON schema below)

#### 2.2 JSON schema (incremental) for `pcms.endnotes.conditions_json`
We should not try to solve “full CBA logic engine” immediately.
Start with a small vocabulary that covers real cases:

```json
{
  "assets": [
    {
      "kind": "PICK" | "SWAP_RIGHT",
      "year": 2031,
      "round": 2,
      "team": "MIA",
      "label": "Miami Pick",
      "via_endnote": 219,
      "selection": {
        "type": "DIRECT" | "LESS_FAVORABLE_OF" | "MORE_FAVORABLE_OF",
        "options": [
          {"team": "IND", "year": 2031, "round": 2, "label": "Indiana Pick"},
          {"team": "MIA", "year": 2031, "round": 2, "label": "Miami Pick"}
        ]
      },
      "conditions": [
        {
          "if": "IND pick more favorable than MIA pick",
          "then": [
            {"action": "EXERCISE_SWAP", "via_endnote": 219},
            {"action": "CONVEY", "pick": "Indiana Pick"}
          ]
        }
      ],
      "exercise_window": {
        "deadline_text": "11:59 p.m. (ET) two days prior to the 2029 NBA Draft",
        "notice_to": ["BKN", "League Office"]
      }
    }
  ],
  "depends_on_endnotes": [219, 193]
}
```

It’s fine if early versions store these fields sparsely.

#### 2.3 SQL checks
Add `queries/sql/050_endnotes_assertions.sql`:
- table exists
- not empty (after import)
- `endnote_id` unique
- `metadata_json->>'source_file'` present

---

## 3) P1 — Draft picks warehouses (tool-facing)

We likely want **two different shapes** because “Sean-style pick grids” mix:
- deterministic “pick slots” (original team / year / round) + provenance
- non-deterministic “assets / claims” (conditional branches, swaps, less favorable sets) + human text

### 3.1 Implemented (2026-01-23): `pcms.draft_picks_warehouse` (team-facing, summary-derived)

**Status:** implemented via `migrations/038_draft_picks_warehouses.sql`.

**Purpose:** Sean-style team/year pick grid, preserving raw fidelity while extracting endnote refs.

**Grain:** `(team_code, draft_year, draft_round, asset_slot)`

**Inputs:**
- `pcms.draft_pick_summaries.first_round` / `second_round`

**Behavior:**
- Explodes each round string on literal `|` into per-fragment rows.
- Preserves `raw_round_text` (full string) and `raw_fragment` (exact fragment for row).
- Extracts numeric ids in parentheses into:
  - `numeric_paren_refs int[]`: all ids found
  - `endnote_refs int[]`: ids filtered to `1..999` (heuristic for curated endnote corpus)
- Flags:
  - `is_forfeited` (fragment contains "forfeit")
  - `is_conditional_text` (keyword scan)
  - `is_swap_text` (keyword scan)
  - `needs_review` (any of the above)

**Important implementation note:**
- `pcms.refresh_draft_picks_warehouse()` is a **LANGUAGE SQL** function.
  - We hit a nasty bug where PL/pgSQL + CTE + correlated regexp extraction yielded empty arrays.
  - The SQL function version (with `CROSS JOIN LATERAL regexp_matches`) behaves correctly.

**Refresh:**
- `SELECT pcms.refresh_draft_picks_warehouse();`
- Wired into `import_pcms_data.flow/refresh_caches.inline_script.py`.

### 3.2 Implemented (2026-01-23): `pcms.draft_pick_slots_warehouse` (slot/provenance-derived)

**Status:** implemented via `migrations/038_draft_picks_warehouses.sql`.

**Purpose:** "who owns which original pick slot" queries with provenance.

**Grain:** `(draft_year, draft_round, original_team_id)`

**Inputs:**
- `pcms.draft_pick_trades`

**Behavior:**
- Latest movement row (by `trade_date desc, trade_id desc, id desc`) determines current holder.
- Carries `last_trade_id/last_trade_date` + from/to team codes.
- `needs_review=true` if `is_swap` or `is_conditional`.

**Refresh:**
- `SELECT pcms.refresh_draft_pick_slots_warehouse();`
- Wired into `import_pcms_data.flow/refresh_caches.inline_script.py`.

### 3.3 Future / optional: richer `draft_assets_warehouse` (endnotes-enriched)

**Purpose:** make Team Master / Give-Get trivial.

**Grain:** `(team_code, draft_year, draft_round, asset_slot)`
- `asset_slot` is the Nth asset described for that team/year/round.
- Because a single summary field can contain multiple assets separated by `|` and `;`.

**Inputs:**
- `pcms.draft_pick_summaries.first_round` / `second_round`
- Optional enrichment: join `pcms.endnotes` via endnote refs found in text

**Required columns (minimum):**
- identity:
  - `team_id`, `team_code`, `draft_year`, `draft_round`, `asset_slot`
- classification:
  - `asset_type` (OWN / HAS / TO / MAY_HAVE / SWAP_RIGHT / OTHER)
  - `is_conditional` boolean
  - `is_swap` boolean
- counterparties / provenance:
  - `counterparty_team_code` (if parseable)
  - `via_team_codes text[]` (from “via …” chains)
  - `endnote_refs int[]`
  - `primary_endnote_id int` (nullable)
- raw fidelity:
  - `raw_round_text` (full `first_round`/`second_round` string)
  - `raw_fragment` (exact fragment for this row)
- derived text:
  - `protection_text` (nullable)
  - `condition_text` (nullable)
- missingness flags:
  - `has_endnote_match` boolean
  - `has_counterparty_team_code` boolean
- metadata:
  - `confidence` (`high|medium|low`)
  - `needs_review` boolean
  - `refreshed_at`

**Refresh:**
- `pcms.refresh_draft_assets_warehouse()`
- Called from `refresh_caches.inline_script.py`.

**Parsing strategy (safe + incremental):**
- Split by `|` into major fragments.
- Within each fragment, split conditional branches by `;`.
- Extract:
  - keywords: `Own`, `To XXX(n)`, `Has XXX(n)`, `May have XXX(n)`, `or to XXX(n)`
  - endnote refs: `\((\d+)\)`
  - via chain: repeated `(via XXX(n))`
- Keep raw strings always; never discard.

### 3.4 SQL checks (implemented)

Added: `queries/sql/051_draft_picks_warehouses_assertions.sql`
- table existence + non-empty
- year bounds sanity
- regression fixtures:
  - **splitter regression**: POR 2025 round-2 should be exactly one fragment and match `To TOR(259) (via SAC(15))`
  - **endnote extraction regression**: CHI 2023 round-1 `To ORL(96)` must yield `endnote_refs={96}`

Included in `queries/sql/run_all.sql`.

---

## 4) P2 — Draft rights / returning rights warehouse

### 4.1 Warehouse: `pcms.player_rights_warehouse`

**Purpose:** Team Master “Rights” section + Give/Get inputs.

**Grain:** one row per `player_id` where we believe a team controls rights.

**Critical discovery (2026-01-23):**
- `transactions.rights_team_id` is **DLG-only** in this dataset (not NBA draft rights).
- NBA “draft rights list” movement is represented in **trade details**: `pcms.trade_team_details.trade_entry_lk='DRLST'`.
- `lookups.json` in this extract does **not** include NBA `team_code` abbreviations; backfill `team_code` from `pcms.teams` after upsert.

**Inputs (current implementation):**
- NBA draft rights:
  - base set: `pcms.people` filtered to `league_lk='NBA'`, `record_status_lk='ACT'`, `player_status_lk='CDL'`
  - rights holder: latest `pcms.trade_team_details` DRLST row for that player (see below)
  - fallback: `pcms.people.team_id` then `pcms.people.draft_team_id`
- DLG returning rights:
  - `pcms.people.dlg_returning_rights_team_id/team_code` (when present)

**Required columns (implemented + recommended):**
- identity:
  - `player_id`, `player_name`, `league_lk`
- rights:
  - `rights_team_id`, `rights_team_code`
  - `rights_kind` (`NBA_DRAFT_RIGHTS` | `DLG_RETURNING_RIGHTS`)
  - `rights_source` (`trade_team_details` vs `people`)
- provenance (for NBA draft rights via trades):
  - `source_trade_id`, `source_trade_date`, `source_trade_team_detail_id`
- draft metadata:
  - `draft_year`, `draft_round`, `draft_pick`, `draft_team_id`, `draft_team_code`
- UI helpers:
  - `has_active_nba_contract` (optional; for our CDL-filtered set it should generally be false)
  - `needs_review` boolean
- `refreshed_at`

**Refresh:**
- `pcms.refresh_player_rights_warehouse()`
- Called from `import_pcms_data.flow/refresh_caches.inline_script.py`.

**Implementation notes:**
- Use `pcms.trade_team_details` rows with `trade_entry_lk='DRLST'`.
- Empirical semantics: for DRLST, the *controlling rights team* corresponds to the **sender** row (`is_sent=true`).
  - Regression fixture: Daniel Díez (`player_id=1626229`) → `rights_team_code='NYK'` via `trade_id=2023055`.

### 4.2 SQL checks
Add `queries/sql/052_player_rights_warehouse_assertions.sql`:
- `player_id` unique
- rowcount sanity (>0)
- for `rights_kind='NBA_DRAFT_RIGHTS'`, ensure `rights_team_code` is usually populated (track blanks)
- fixture spot-check: `player_id=1626229` (Díez) returns NYK (post-refresh)

---

## 5) Wiring into the flow (post-import refresh)

Update: `import_pcms_data.flow/refresh_caches.inline_script.py`

Implemented refresh wiring:
- `SELECT pcms.refresh_draft_pick_slots_warehouse();`
- `SELECT pcms.refresh_draft_picks_warehouse();`
- `SELECT pcms.refresh_player_rights_warehouse();`

Endnotes are not from PCMS, so they may be refreshed separately:
- Option A: keep endnotes import as a manual/local step (`scripts/import-endnotes.py`).
- Option B: add a Windmill step (with an input for `endnotes_dir`) that runs the importer.

---

## 6) Stretch goals / hard problems (explicitly acknowledged)

1) **Outcome resolution engine**
- Determining the *actual* conveyed pick in swap/less-favorable constructs requires standings/lottery outcomes.
- For now, the warehouse should represent the logic + dependencies, not attempt to resolve.

2) **Linking endnotes to `pcms.trades.trade_id`**
- Not required for usefulness.
- Endnote IDs already provide a stable handle and match summary refs.
- If we later infer `trade_id`, store it in `pcms.endnotes.trade_id` with `metadata_json.source='inferred'`.

3) **First-class “asset expressions”**
- e.g. “Result Pick = less favorable of (OKC 2027 1st, DEN 2027 1st)”
- We can model as JSON in `endnotes.conditions_json`, and optionally materialize to a warehouse view.

---

## 7) Acceptance examples (use these as regression fixtures)

From curated endnotes (examples that should be representable):
- Simple pick conveyance: `21`, `204`, `245`
- Less favorable set: `129`
- Swap right with auto exercise/extinguish: `212`
- Result pick dependent on entitlement to another pick: `152`
- Conditional substitution based on another endnote’s swap: `241`, `258`

At minimum, these should appear in `draft_assets_warehouse` with:
- correct `endnote_refs` / `primary_endnote_id`
- correct `draft_year` / `round`
- `condition_text` capturing the “provided however…” logic (even if not parsed into structured JSON yet)

---

## 8) Notes

- Keep migrations append-only.
- Prefer `TRUNCATE/INSERT` refresh functions for warehouses.
- Add indexes that match primary access patterns:
  - Team Master: `(team_code, draft_year)`
  - Give/Get: `(draft_year, draft_round)`
  - Rights: `(rights_team_code)`
