# TODO — Draft Assets (Picks + Rights) + Endnotes Integration

Status: **2026-01-22**

This repo is already strong on **Salary Book / Team totals / Exceptions / Trade TPE math**.

The biggest gap vs "Sean-style" tooling is **draft assets**:
- **Draft picks** (owned/owed, protections, swaps, conditional branches)
- **Draft rights / returning rights** (who controls a player's rights)
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
- Tool-friendly booleans are OK, but keep `has_*` / `*_source` / `*_id` fields so we can distinguish "false" from "unknown / absent in source".

3) **Keep "raw fidelity" alongside derived fields**
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
  - Populated heavily (primarily DLG "returning rights" patterns show up via `transaction_type_lk='TRDRR'`, `to_player_status_lk='URETP'`, etc.).
- `pcms.people.dlg_returning_rights_team_id/team_code` and `dlg_returning_rights_salary_year`

### Endnotes
- `pcms.endnotes` — **323 rows imported** from curated source
  - Columns: `original_note`, `revised_note`, `explanation`, `conditions_json`, `metadata_json`, etc.
  - Flags: `is_swap` (47), `is_conditional` (108)
  - `conditions_json.depends_on_endnotes` tracks cross-references (168 endnotes reference others)

External curated source:
- `~/blazers/cba-docs/endnotes/revised/*.txt`

Important observation:
- The draft-pick summary strings include parenthetical endnote refs like `(194)`.
- The curated endnote files are keyed by the same IDs (e.g. `194_*.txt`).
- This gives us a clean bridge: **summary refs → `pcms.endnotes.endnote_id`** (97.2% match rate).

---

## 2) ✅ DONE — Ingest curated endnotes into `pcms.endnotes`

**Completed 2026-01-22**

### Deliverables

#### 2.1 ✅ Script: `scripts/import-endnotes.py`
- Reads `~/blazers/cba-docs/endnotes/revised/*.txt`
- Extracts fields:
  - `endnote_id` (from header or filename)
  - `trade_date` (parsed from "TRADE DATE:" line)
  - `status`, `trade_summary`, `conveyance`, `protections`, `contingency`, `exercise`
  - `original_text` (the "ORIGINAL TEXT:" or "VERBATIM ORIGINAL:" block)
- Detects: `is_swap`, `is_conditional`, `referenced_endnotes`
- Dedupes by `endnote_id` (keeps most recently modified file)
- Upserts into `pcms.endnotes`

Usage:
```bash
uv run scripts/import-endnotes.py --dry-run   # parse + show stats
uv run scripts/import-endnotes.py --write     # upsert to DB
```

Storage:
- `revised_note`: full raw file content
- `original_note`: verbatim PCMS endnote text
- `explanation`: conveyance section
- `metadata_json`: source_file, parse_version, parsed sections, team_codes_mentioned, etc.
- `conditions_json`: `is_swap`, `is_conditional`, `depends_on_endnotes[]`

#### 2.2 ✅ SQL checks: `queries/sql/050_endnotes_assertions.sql`
- Table not empty
- `endnote_id` unique
- `metadata_json->>'source_file'` present for all rows
- Rowcount >= 300
- Fixture: endnote 65 is swap + conditional
- Join test: 97%+ of `draft_picks_warehouse.endnote_refs` match `pcms.endnotes`

Included in `queries/sql/run_all.sql`.

#### 2.3 Stats (post-import)
| Metric | Value |
|--------|-------|
| Total endnotes | 323 |
| Swap rights | 47 |
| Conditional | 108 |
| References other endnotes | 168 |
| Unmatched refs in draft_picks_warehouse | 9 (very recent trades) |

---

## 3) ✅ DONE — Draft picks warehouses (tool-facing)

### 3.1 ✅ `pcms.draft_picks_warehouse` (team-facing, summary-derived)

**Implemented:** `migrations/archive/038_draft_picks_warehouses.sql`

**Purpose:** Sean-style team/year pick grid, preserving raw fidelity while extracting endnote refs.

**Grain:** `(team_code, draft_year, draft_round, asset_slot)`

**Behavior:**
- Explodes each round string on literal `|` into per-fragment rows
- Preserves `raw_round_text` and `raw_fragment`
- Extracts `endnote_refs int[]` (ids 1–999)
- Flags: `is_forfeited`, `is_conditional_text`, `is_swap_text`, `needs_review`

**Refresh:** `SELECT pcms.refresh_draft_picks_warehouse();`

**Rows:** 1,248

### 3.2 ✅ `pcms.draft_pick_trade_claims_warehouse` (trade-derived, evidence/claims)

**Implemented:** `migrations/archive/040_draft_pick_trade_claims_warehouse.sql`

**Purpose:** trade-derived pick *claims* per original slot (debug/provenance).

**Grain:** `(draft_year, draft_round, original_team_id)`

**Behavior:**
- Stores all trade-derived rows per slot in `trade_claims_json` (newest-first)
- Scalars: `claims_count`, `distinct_to_teams_count`, `has_conditional_claims`, `has_swap_claims`, `needs_review`

**Refresh:** `SELECT pcms.refresh_draft_pick_trade_claims_warehouse();`

**Rows:** 658

### 3.3 SQL checks: `queries/sql/051_draft_picks_warehouses_assertions.sql`
- Table existence + non-empty
- Year bounds sanity
- Regression fixtures for splitter + endnote extraction

---

## 4) ✅ DONE — Draft rights / returning rights warehouse

### 4.1 ✅ `pcms.player_rights_warehouse`

**Implemented:** `migrations/archive/035_player_rights_warehouse.sql` + fixes in 036, 037

**Purpose:** Team Master "Rights" section + Give/Get inputs.

**Grain:** one row per `player_id` where a team controls rights.

**Inputs:**
- NBA draft rights: `pcms.people` (CDL status) + `pcms.trade_team_details` (DRLST)
- DLG returning rights: `pcms.people.dlg_returning_rights_*`

**Key columns:**
- `rights_team_id`, `rights_team_code`, `rights_kind`, `rights_source`
- `source_trade_id`, `source_trade_date` (for trade-derived)
- `draft_year`, `draft_round`, `draft_pick`, `draft_team_id`

**Refresh:** `SELECT pcms.refresh_player_rights_warehouse();`

**Rows:** 453

### 4.2 SQL checks: `queries/sql/052_player_rights_warehouse_assertions.sql`
- `player_id` unique
- Rowcount > 0
- Fixture: Daniel Díez → NYK via trade 2023055

---

## 5) ✅ DONE — Wiring into the flow

`import_pcms_data.flow/refresh_caches.inline_script.py` calls:
- `SELECT pcms.refresh_draft_pick_trade_claims_warehouse();`
- `SELECT pcms.refresh_draft_picks_warehouse();`
- `SELECT pcms.refresh_player_rights_warehouse();`

Endnotes import is a **separate manual step** (`scripts/import-endnotes.py`) since the source is not from PCMS.

---

## 6) ✅ DONE — `draft_assets_warehouse` (endnotes-enriched)

**Implemented:** `migrations/archive/044_draft_assets_warehouse_v3_fix_backslashes.sql`

**Purpose:** make Team Master / Give-Get trivial by joining `draft_picks_warehouse` with `pcms.endnotes`.

**Grain:** `(team_code, draft_year, draft_round, asset_slot, sub_asset_slot)`
- `asset_slot` comes from splitting `draft_pick_summaries` round strings on `|` (via `draft_picks_warehouse`)
- `sub_asset_slot` comes from additionally splitting each fragment on `;` to produce atomic clauses

**Key columns (current):**
- identity: `team_id`, `team_code`, `draft_year`, `draft_round`, `asset_slot`, `sub_asset_slot`
- classification:
  - `asset_type` (OWN / HAS / TO / MAY_HAVE / OTHER)
  - `is_conditional`, `is_swap`
- counterparties / provenance:
  - `counterparty_team_code` (first recipient)
  - `counterparty_team_codes text[]` (all recipients mentioned)
  - `via_team_codes text[]`
  - `endnote_refs int[]`, `primary_endnote_id int`, `has_endnote_match`
- endnotes join:
  - `endnote_trade_date`, `endnote_explanation`, `endnote_is_swap`, `endnote_is_conditional`, `endnote_depends_on int[]`
- raw fidelity: `raw_round_text`, `raw_fragment`, `raw_part`
- metadata: `needs_review`, `refreshed_at`

**Refresh:** `SELECT pcms.refresh_draft_assets_warehouse();`

**Notes / gotchas:**
- `LANGUAGE sql` functions using `$$...$$` bodies treat backslashes as literal.
  - Regex escapes should use single backslashes (e.g. `\s`, `\b`, `\d`) inside the function body.
  - Double-escaping caused all rows to fall through to `asset_type='OTHER'` until fixed.

**Parsing strategy:**
- Split by `|` (already done in `draft_picks_warehouse`)
- Then split by `;` into `raw_part` clauses
- Extract:
  - `Own`, `To XXX(n)`, `Has XXX(n)`, `May have XXX(n)`
  - `via XXX(n)` chains
- Join `pcms.endnotes` on first endnote ref

---

## 7) P2 — Trade planner expansion

**Status:** Not started

The current planner is **TPE-only** and single-team-centric.

Next layers:
- Multi-team plans (two+ team proposals, still legged)
- Aggregation constraint windows (Dec 15 → deadline rules)
- MLE-as-vehicle + apron hard-cap restrictions

---

## 8) P3 — Fidelity / reconciliation artifact

**Status:** Not started

Add one canonical query/view to reconcile:
- `team_salary_warehouse` totals
- vs roster sums from `salary_book_warehouse`
- explained by `team_budget_snapshots.budget_group_lk`

This becomes the debugging hammer for Team Master + trade tooling.

---

## 9) Stretch goals / hard problems (explicitly acknowledged)

1) **Outcome resolution engine**
- Determining the *actual* conveyed pick in swap/less-favorable constructs requires standings/lottery outcomes.
- For now, the warehouse should represent the logic + dependencies, not attempt to resolve.

2) **Linking endnotes to `pcms.trades.trade_id`**
- Not required for usefulness.
- Endnote IDs already provide a stable handle and match summary refs.
- If we later infer `trade_id`, store it in `pcms.endnotes.trade_id` with `metadata_json.source='inferred'`.

3) **First-class "asset expressions"**
- e.g. "Result Pick = less favorable of (OKC 2027 1st, DEN 2027 1st)"
- We can model as JSON in `endnotes.conditions_json`, and optionally materialize to a warehouse view.

---

## 10) Acceptance examples (regression fixtures)

From curated endnotes (examples that should be representable):
- Simple pick conveyance: `21`, `204`, `245`
- Less favorable set: `129`
- Swap right with auto exercise/extinguish: `212`
- Result pick dependent on entitlement to another pick: `152`
- Conditional substitution based on another endnote's swap: `241`, `258`

At minimum, these should appear in `draft_assets_warehouse` with:
- correct `endnote_refs` / `primary_endnote_id`
- correct `draft_year` / `round`
- `condition_text` capturing the "provided however…" logic

---

## 11) Notes

- Keep migrations append-only.
- Prefer `TRUNCATE/INSERT` refresh functions for warehouses.
- Add indexes that match primary access patterns:
  - Team Master: `(team_code, draft_year)`
  - Give/Get: `(draft_year, draft_round)`
  - Rights: `(rights_team_code)`
