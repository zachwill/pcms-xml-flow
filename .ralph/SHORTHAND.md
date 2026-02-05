# Draft Pick Shorthand - Curation Backlog (pcms)

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
- Don't compress multiple picks into "2 MF …" shortcuts; keep each asset row granular.
- For "outgoing" meaning:
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

## Backlog - missing_shorthand (draft_year >= 2026)

Guideline: one checkbox = one endnote cluster.

- [x] (bootstrap) Create SHORTHAND backlog file + agent wiring

### Top clusters (refreshed 2026-02-05)

Ordered by rows in `pcms.vw_draft_pick_shorthand_todo` where `primary_todo_reason='missing_shorthand'` and `draft_year >= 2026`.

- [x] Endnote 16 (6 rows) - PHI→OKC PHI conditional 1st
- [x] Endnote 321 (5 rows) - BOS→UTA MF [BOS, CLE] 2031 2nd
- [ ] Endnote 320 (5 rows) - BOS→UTA MF [BOS, NOP] 2027 2nd
- [ ] Endnote 319 (5 rows) - SAS→WAS LF [DAL, SAS, TOR] 2027 2nd
- [ ] Endnote 316 (5 rows) - DET→SAC LF [DET, NYK, WAS] 2029 2nd
- [ ] Endnote 310 (5 rows) - PHX→MIN MF [HOU, PHX] 2032 2nd
- [ ] Endnote 307 (5 rows) - HOU→PHX 2nd MF [DAL, HOU, UTA] 2027 2nd
- [ ] Endnote 295 (5 rows) - PHX→CHA CLE/MIN/UTA 2029 1st (via PHX)
- [ ] Endnote 293 (5 rows) - UTA→CHA MF [UTA, PHX] 2030 2nd
- [ ] Endnote 291 (5 rows) - ORL→BOS MF [ORL, POR] 2027 2nd
- [ ] Endnote 248 (5 rows) - PHI→WAS HOU 2026 1st (via PHI)
- [ ] Endnote 231 (5 rows) - UTA→PHX (3-pick conditional logic)
- [ ] Endnote 230 (5 rows) - UTA→PHX LF [UTA 2027, 2028, 2029] 1st
- [ ] Endnote 202 (5 rows) - NOP→ATL LF [NOP, CLE] 2028 2nd
- [ ] Endnote 190 (5 rows) - NYK→POR LF [IND, MIL, DEN] 2029 2nd
- [ ] Endnote 156 (5 rows) - OKC→PHI LF [LAC, OKC] 2026 1st (Harden; feeds endnote 248)
- [ ] Endnote 129 (5 rows) - IND→NYK LF [IND, WAS] 2029 2nd
- [ ] Endnote 128 (5 rows) - IND→NYK LF [IND, PHX] 2028 2nd
- [ ] Endnote 123 (5 rows) - MIA→SAS LF [DAL, OKC, PHI] 2026 2nd (Okpala dependency)
- [ ] Endnote 101 (5 rows) - DEN→OKC "First Allowable Draft" 1st (DEN 2029/2030 1sts)

### Smaller clusters / follow-ups (refreshed 2026-02-05)

- [ ] Endnote 244 (2 rows) - BOS→HOU LF [NOP, CLE] 2027 2nd
- [ ] Endnote 194 (2 rows) - PHX→NYK BOS 2028 2nd (via PHX; overlaps endnote 50 swap chain)
- [ ] Endnote 176 (2 rows) - POR→BOS LF [POR, UTA] 2027 2nd
- [ ] Endnote 157 (2 rows) - DET→WAS LF [NYK, WAS] 2026 2nd
- [ ] Endnote 50 (1 row) - BOS 2028 2nd outgoing row: "Own or to SAS(50) or to NYK(194)" (likely shorthand `BOS`)

---

## Done (append-only)

When you complete a cluster, add a bullet here with:
- endnote_id
- 1-2 sentence description
- key shorthand(s)
- quick verification query link/snippet (optional)

- Endnote 125 - DET→WAS conveys the MF of BKN/DAL 2027 2nds (via DET); DET retains the LF. Added shorthands: `MF [BKN, DAL]` (WAS) and `LF [BKN, DAL]` (DET), plus origin rows `BKN`/`DAL` for direction-aware outgoing display.
- Endnote 64 - NYK conveys to DET the MF of NYK/MIN 2026 2nds (Burks/Noel, 7/11/2022). Added origin shorthands `NYK` and `MIN` (including the NYK "may have MIN" branch) so outgoing rows render direction-aware `To ...` display.
- Endnote 52 - OKC→NYK conveys WAS future conditional 1st (Dieng trade, 6/23/2022). Full chain: Endnotes 15→27→52 (Wall-Westbrook → Sengün → Dieng). NYK receives WAS 2026 1st if 9-30 (top-8 protected); if not conveyed, NYK instead receives WAS 2026+2027 2nds. Shorthands: `WAS (p. 1-8)` for the 1st, `WAS` for the fallback 2nds, `Own to NYK (p. 1-8)` / `Own to NYK` for WAS outgoing rows.
- Endnote 50 - BOS↔SAS 2028 1st swap (White-Langford-Richardson trade, 2/10/2022). SAS has right to swap their 2028 1st for BOS's 2028 1st (top-1 protected). If swap lapses (BOS gets #1), SAS gets BOS 2028 2nd (picks 31-45 only). Shorthands: `BOS`/`SAS` for 1st round OWN/MAY_HAVE rows, `BOS (p. 1)` for SAS swap right, `BOS (p. 31-45)` for 2nd round fallback.
- Endnote 45 - NOP→POR 2027 2nd (McCollum trade, 2/8/2022). NOP conveys 2027 2nd to POR, which then feeds into pool logic: CHA gets MF [POR, NOP] (endnote 95), HOU gets LF [NOP, POR] via BOS (endnotes 176, 244). Shorthand: `NOP` for all 4 rows representing the NOP pick's flow through the chain.
- Endnote 27 - Already covered by endnote 52 (Sengün trade, 7/30/2021). This was the middle step in the HOU→OKC→NYK chain for WAS 1st. All 6 rows already have shorthand from endnote 52 curation: `WAS (p. 1-8)` / `WAS` for NYK's MAY_HAVE, `Own to NYK (p. 1-8)` / `Own to NYK` for WAS outgoing.
- Endnote 15 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (this endnote is already covered by the Endnote 52 chain; Wall/Westbrook → Sengün → Dieng).
- Endnote 197 — Cleanup: removed embedded "To WAS:" prefix from POR's shorthand (`2nd MF [POR, BOS, MIL]`) so direction stays with `vw_draft_pick_assets.display_text`.
- Endnote 16 — PHI→OKC Horford trade (12/8/2020). PHI conveys conditional 1st (2026/2027 top-4 protected); fallback is PHI 2027 2nd unconditionally. Shorthands: `PHI (p. 1-4)` for 1st round rows, `PHI` for 2nd round fallback.
- Endnote 321 — BOS→UTA Luis/Niang trade (8/6/2025). UTA receives MF [BOS, CLE] 2031 2nd. CLE pick flows via ATL (endnote 272) then BOS (endnote 313). Shorthands: `MF [BOS, CLE]` for UTA's primary MAY_HAVE, `BOS`/`CLE` for origin picks.
