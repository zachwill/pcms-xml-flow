# Draft Pick Shorthand — Curation Backlog (pcms)

This file is the **single source of truth** for the durable, curated NBA draft-pick shorthand we maintain in Postgres.

Scope:
- Data lives in Postgres (`pcms.*` schema).
- We curate **durable shorthand assets** in `pcms.draft_pick_shorthand_assets`.
- We do **not** hand-edit refresh-derived assets in `pcms.draft_pick_summary_assets` / `pcms.draft_pick_summary_assets`.

Hard requirement:
- For any DB work, use:

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1
```

---

## Goal

Reduce the missing shorthand backlog by curating **Sean-style** shorthand strings for draft picks (esp. `draft_year >= 2026`).

Canonical query surface:
- `pcms.vw_draft_pick_assets`
  - `display_text` is what humans should read.
  - `display_text` is **direction-aware** for outgoing rows where `raw_part` begins with `To ...`.

Work queue:
- `pcms.vw_draft_pick_shorthand_todo`
  - prioritize rows where `primary_todo_reason='missing_shorthand'`
  - focus on `draft_year >= 2026`

---

## Authoritative sources / tables

- PCMS truth snapshot: `pcms.draft_pick_summaries`
- Refresh-derived pieces (**do not hand edit**):
  - `pcms.draft_pick_summary_assets` (rebuilt by `pcms.refresh_draft_pick_summary_assets()`)
- Durable curated shorthand (**upsertable**):
  - `pcms.draft_pick_shorthand_assets`

---

## Shorthand rules (must follow)

- Use NBA **3-letter** team codes.
- Parentheses are reserved for protections:
  - `TEAM (p. 1-8)`
- **No endnote numbers** inside shorthand strings.
- Use Sean-style pools:
  - `MF [A, B, C]` (more favorable)
  - `LF [A, B, C]` (less favorable)
  - nesting allowed: `LF [A, MF [B, C]]`
  - ordinals allowed: `2nd MF [A, B, C]`, etc.
- Don’t compress multiple picks into “2 MF …” shortcuts; keep each asset row granular.
- For “outgoing” meaning:
  - **do not embed** `To XYZ:` in shorthand.
  - direction is rendered by `pcms.vw_draft_pick_assets.display_text`.
  - put narrative/explanations in `notes` if needed.

---

## Endnotes corpus

Endnotes are already imported into `pcms.endnotes`.
Raw text files are also available on disk:

- `/Users/zachwill/blazers/cba-docs/endnotes/revised/`

---

## Standard workflow (one endnote cluster per iteration)

### 0) Pick the next endnote cluster

```sql
with todo as (
  select *
  from pcms.vw_draft_pick_shorthand_todo
  where primary_todo_reason='missing_shorthand'
    and draft_year >= 2026
)
select unnest(effective_endnote_ids) as endnote_id, count(*) as rows
from todo
group by 1
order by rows desc, endnote_id desc
limit 20;
```

### 1) Pull all affected asset rows

```sql
select
  team_code, draft_year, draft_round, asset_slot, sub_asset_slot,
  asset_type, is_swap, is_conditional,
  counterparty_team_code, via_team_codes,
  raw_part,
  primary_endnote_id, effective_endnote_ids,
  has_shorthand, shorthand, display_text,
  endnote_explanation
from pcms.vw_draft_pick_assets
where <ENDNOTE_ID> = any(effective_endnote_ids)
  and draft_year >= 2026
order by draft_year, draft_round, team_code, asset_slot, sub_asset_slot;
```

Also pull endnote details:

```sql
select
  endnote_id, trade_date, is_swap, is_conditional, depends_on_endnotes,
  explanation,
  metadata_json->>'source_file' as source_file
from pcms.endnotes
where endnote_id in (<ENDNOTE_ID>, <DEPENDENCIES...>)
order by endnote_id;
```

### 2) Draft consistent shorthand

- Identify the **underlying asset** (what pick / which pool) and apply it consistently across branches.
- Duplicate shorthand across branches if they represent the same underlying asset.

### 3) Upsert into `pcms.draft_pick_shorthand_assets`

Rules:
- Always use `ON CONFLICT (...) DO UPDATE`.
- Set:
  - `source_lk='manual_endnote'`
  - `endnote_ids` (include the relevant cluster + dependencies)
  - `referenced_team_codes`
  - `notes` (short explanation / why this shorthand is correct)

Template:

```sql
insert into pcms.draft_pick_shorthand_assets (
  team_code, draft_year, draft_round, asset_slot, sub_asset_slot,
  shorthand_input, shorthand,
  endnote_ids, referenced_team_codes,
  notes, source_lk, needs_review
)
values
  (...)
on conflict (team_code, draft_year, draft_round, asset_slot, sub_asset_slot)
do update set
  shorthand_input = excluded.shorthand_input,
  shorthand = excluded.shorthand,
  endnote_ids = excluded.endnote_ids,
  referenced_team_codes = excluded.referenced_team_codes,
  notes = excluded.notes,
  source_lk = excluded.source_lk,
  needs_review = excluded.needs_review,
  updated_at = now();
```

### 4) Verify direction-aware `display_text`

```sql
select
  team_code, draft_year, draft_round, asset_slot, sub_asset_slot,
  raw_part, shorthand, display_text
from pcms.vw_draft_pick_assets
where <ENDNOTE_ID> = any(effective_endnote_ids)
  and draft_year >= 2026
order by draft_year, draft_round, team_code, asset_slot, sub_asset_slot;
```

### 5) Run only the relevant assertions

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/062_draft_pick_assets_views_assertions.sql
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/063_draft_pick_assets_display_text_direction_assertions.sql
```

---

## Backlog — missing_shorthand (draft_year >= 2026)

Guideline: one checkbox = one endnote cluster.

- [x] (bootstrap) Create SHORTHAND backlog file + agent wiring

---

## Done (append-only)

When you complete a cluster, add a bullet here with:
- endnote_id
- 1–2 sentence description
- key shorthand(s)
- quick verification query link/snippet (optional)
