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

### Top clusters (5-row clusters) (refreshed 2026-02-05)

As of this refresh: **228 rows** remain with `primary_todo_reason='missing_shorthand'` for `draft_year >= 2026`.

Ordered by rows in `pcms.vw_draft_pick_shorthand_todo` where `primary_todo_reason='missing_shorthand'` and `draft_year >= 2026`.

- [x] Endnote 293 (5 rows) - UTA→CHA MF [UTA, LAC] 2030 2nd
- [x] Endnote 248 (5 rows) - PHI→WAS LF [LAC, OKC, HOU (p. 1-4)] 2026 1st (via PHI/endnote 156)
- [x] Endnote 230 (5 rows) - UTA→PHX LF [CLE, MIN, UTA] 2027 1st
- [x] Endnote 202 (5 rows) - NOP→ATL LF [NOP, MIL] 2027 1st (p. 1-4)
- [x] Endnote 190 (5 rows) - NYK→POR LF [IND, WAS] 2029 2nd
- [ ] Endnote 129 (5 rows) - IND→NYK LF [IND, WAS] 2029 2nd
- [ ] Endnote 128 (5 rows) - IND→NYK LF [IND, PHX] 2028 2nd
- [ ] Endnote 101 (5 rows) - DEN→OKC "First Allowable Draft" 1st (DEN 2029/2030 1sts)
- [ ] Endnote 47 (5 rows) - UTA→SAS LF [HOU, IND] 2027 2nd
- [ ] Endnote 30 (5 rows) - OKC→UTA LF [OKC, HOU] 2027 2nd
- [ ] Endnote 19 (5 rows) - DET→OKC HOU 2027 2nd (via DET; depends on endnote 10)
- [ ] Endnote 12 (5 rows) - IND→OKC IND 2027 2nd
- [ ] Endnote 10 (5 rows) - HOU→DET HOU 2027 2nd (Wood trade)

#### Next up (4-row clusters)

All entries below are currently tied at 4 rows; ordered by endnote_id desc.

- [ ] Endnote 304 (4 rows) - ATL/HOU 2031 2nd (swap rights)
- [ ] Endnote 283 (4 rows) - ATL/MIL/NOP 2026 1st ("Resulting Pick" swap/conditional chain)
- [ ] Endnote 256 (4 rows) - DET/GSW/MIN 2031 2nd
- [ ] Endnote 241 (4 rows) - NOP/OKC/ORL 2031 2nd
- [ ] Endnote 212 (4 rows) - SAC/SAS 2031 1st
- [ ] Endnote 211 (4 rows) - DET/GSW/MIN 2031 2nd
- [ ] Endnote 193 (4 rows) - NOP/OKC/ORL 2031 2nd
- [ ] Endnote 192 (4 rows) - NOP/ORL 2030 2nd
- [ ] Endnote 163 (4 rows) - DAL/OKC 2028 1st
- [ ] Endnote 159 (4 rows) - CHA/MIA 2027-2028 1st
- [ ] Endnote 154 (4 rows) - LAC/PHI 2029 1st
- [ ] Endnote 152 (4 rows) - LAC/OKC 2027 1st
- [ ] Endnote 148 (4 rows) - MIL/POR 2030 1st
- [ ] Endnote 116 (4 rows) - GSW/WAS 2030 (rounds 1+2)
- [ ] Endnote 109 (4 rows) - IND/POR/WAS 2029 2nd
- [ ] Endnote 107 (4 rows) - IND/NYK/PHX 2028 2nd
- [ ] Endnote 99 (4 rows) - MIL/SAS/UTA 2026 2nd
- [ ] Endnote 89 (4 rows) - NOP/POR/SAS 2026 2nd
- [ ] Endnote 78 (4 rows) - MIL/SAS/UTA 2026 2nd
- [ ] Endnote 77 (4 rows) - LAL/UTA 2027 (rounds 1+2)
- [ ] Endnote 60 (4 rows) - NOP/POR 2026 2nd
- [ ] Endnote 55 (4 rows) - MIN/SAS 2026 2nd
- [ ] Endnote 51 (4 rows) - LAL/ORL/WAS 2028 2nd
- [ ] Endnote 44 (4 rows) - NOP/POR 2026 2nd
- [ ] Endnote 36 (4 rows) - MIN/SAS 2026 2nd
- [ ] Endnote 33 (4 rows) - LAC/MEM/POR 2026 2nd
- [ ] Endnote 26 (4 rows) - POR/SAS 2026 2nd
- [ ] Endnote 17 (4 rows) - BKN/HOU 2027 1st
- [ ] Endnote 9 (4 rows) - ATL/MIL/NOP 2026 1st
- [ ] Endnote 8 (4 rows) - ATL/MIL/NOP 2027 1st

### Smaller clusters / follow-ups (<=2 rows) (refreshed 2026-02-05)

- [ ] Endnote 322 (2 rows) - BKN/MIA 2026 2nd
- [ ] Endnote 317 (2 rows) - CHA/SAC 2026 2nd
- [ ] Endnote 311 (2 rows) - GSW/MEM 2032 2nd
- [ ] Endnote 244 (2 rows) - BOS→HOU LF [NOP, CLE] 2027 2nd
- [ ] Endnote 197 (2 rows) - BOS/MIL outgoing rows to WAS in the POR 2029 1st pool chain (finish origin shorthands)
- [ ] Endnote 194 (2 rows) - PHX→NYK BOS 2028 2nd (via PHX; overlaps endnote 50 swap chain)
- [ ] Endnote 176 (2 rows) - POR→BOS LF [POR, UTA] 2027 2nd
- [ ] Endnote 157 (2 rows) - DET→WAS LF [NYK, WAS] 2026 2nd
- [ ] Endnote 63 (2 rows) - MIN→UTA MIN 2029 1st (conditional; see endnote text for protections)
- [ ] Endnote 4 (2 rows) - HOU→OKC HOU 2026 1st (conditional)
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
- Endnote 197 (follow-up) — As of 2026-02-05, `pcms.vw_draft_pick_shorthand_todo` still shows 2 `missing_shorthand` rows tied to endnote 197; keep this cluster in the active backlog until the origin rows are fully filled in.
- Endnote 16 — PHI→OKC Horford trade (12/8/2020). PHI conveys conditional 1st (2026/2027 top-4 protected); fallback is PHI 2027 2nd unconditionally. Shorthands: `PHI (p. 1-4)` for 1st round rows, `PHI` for 2nd round fallback.
- Endnote 321 — BOS→UTA Luis/Niang trade (8/6/2025). UTA receives MF [BOS, CLE] 2031 2nd. CLE pick flows via ATL (endnote 272) then BOS (endnote 313). Shorthands: `MF [BOS, CLE]` for UTA's primary MAY_HAVE, `BOS`/`CLE` for origin picks.
- Endnote 320 — BOS→UTA Luis/Niang trade (8/6/2025). UTA receives MF [BOS, ORL] 2027 2nd. BOS pick originally went to ORL (endnote 23), then ORL/BOS pool via endnote 291. Shorthands: `MF [BOS, ORL]` for UTA's MAY_HAVE rows, `BOS`/`ORL` for origin picks.
- Endnote 319 — SAS→WAS Olynyk/Branham trade (7/9/2025). WAS receives LF [DAL, OKC, PHI] 2026 2nd (via SAS→MIA→OKC chain). OKC holds 3-pick pool (own, DAL via endnote 14, PHI via endnote 21): MF stays with OKC, 2nd MF to PHX (endnote 307 via HOU/endnote 70), LF to WAS. Shorthands: `OKC`/`DAL`/`PHI` for origin rows, direction-aware `To WAS: DAL`/`To WAS: PHI` for outgoing.
- Endnote 316 — DET→SAC Schröder trade (7/7/2025). SAC receives LF [DET, MIL, NYK] 2029 2nd; DET retains the other two. MIL pick flows via BKN→DET (endnotes 80/115), NYK pick flows via endnote 165. Shorthands: `DET`/`MIL`/`NYK` for origin rows, direction-aware `To SAC: MIL`/`To SAC: NYK` for outgoing.
- Endnote 310 — PHX→MIN Durant trade (7/6/2025). MIN receives MF [HOU, PHX] 2032 2nd. HOU pick flows via PHX (endnote 308). Shorthands: `MF [HOU, PHX]` for MIN's MAY_HAVE rows, `PHX`/`HOU` for origin picks, direction-aware `To MIN: HOU` for outgoing.
- Endnote 307 — Already curated as part of endnote 319 (WAS receives LF). PHX receives 2nd MF [DAL, OKC, PHI] 2026 2nd via HOU (endnote 70). All 8 rows have shorthand: PHX MAY_HAVE rows get `2nd MF [DAL, OKC, PHI]`, OKC keeps MF (own pick + DAL/PHI via endnotes 14/21), origin rows show direction-aware outgoing to WAS.
- Endnote 295 — PHX→CHA Micic-Williams trade (6/30/2025). CHA receives the 2029 1st that PHX is entitled to from UTA (per endnote 231): the LF of [CLE, MIN, UTA] 2029 1sts. Chain: CLE→UTA (endnote 68 Mitchell), MIN→UTA (endnote 63 Gobert, conditional), UTA→PHX (endnote 231), PHX→CHA (endnote 295). CHA MAY_HAVE rows already had `LF [CLE, MIN, UTA]`. Added origin shorthands: `CLE`/`MIN`/`UTA` for direction-aware outgoing (CLE shows `To CHA: CLE`).
- Endnote 291 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 320 (BOS↔ORL pool → UTA) curation.
- Endnote 231 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 295 (UTA→PHX → CHA) chain curation.
- Endnote 308 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 310 (PHX→MIN) curation.
- Endnote 123 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319/307 OKC 2026 2nd pool curation.
- Endnote 70 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319/307 OKC 2026 2nd pool curation.
- Endnote 46 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319 OKC→WAS chain curation.
- Endnote 293 — UTA→CHA MF [UTA, LAC] 2030 2nd (Sexton-Nurkic trade, 6/29/2025). CHA receives the MF of UTA's own 2030 2nd and the LAC 2030 2nd (which flows to UTA via endnote 232 Eubanks trade). Shorthands: `MF [UTA, LAC]` for CHA's MAY_HAVE rows, `UTA`/`LAC` for origin picks, direction-aware `To CHA: LAC` for LAC outgoing.
- Endnote 248 — PHI→WAS Butler-Jackson trade (2/6/2025). PHI conveys to WAS the 2026 1st they receive from OKC (per endnote 156 Harden trade). The pick is the LF of [LAC, OKC, HOU (p. 1-4)]. Added origin shorthands: `HOU (p. 1-4)` for HOU OWN and OKC MAY_HAVE HOU rows, `LAC` for LAC TO OKC and OKC MAY_HAVE LAC rows, `OKC` for OKC OWN. Direction-aware display: `To WAS: LAC` for outgoing LAC row.
- Endnote 230 — UTA→PHX Suns-Jazz trade (1/21/2025). PHX receives LF [CLE, MIN, UTA] 2027 1st. CLE pick flows via endnote 66 (Mitchell), MIN pick flows via endnote 62 (Gobert). PHX MAY_HAVE rows already had `LF [CLE, MIN, UTA]`. Added origin shorthands: `CLE`/`MIN`/`UTA` for origin and UTA MAY_HAVE rows. Direction-aware display: `To PHX: CLE` and `To PHX: MIN` for outgoing.
- Endnote 202 — NOP→ATL Murray trade (7/6/2024). ATL receives LF [NOP, MIL] 2027 1st (top-4 protected, obligation extinguished if not conveyed). MIL pick flows via Holiday trade (endnote 8). Shorthands: `LF [NOP, MIL] (p. 1-4)` for ATL MAY_HAVE rows, `NOP (p. 1-4)` for NOP origin, `MIL` for MIL origin. Direction-aware: `To ATL: MIL` for MIL outgoing.
- Endnote 190 — NYK→POR Kolek trade (6/27/2024). POR receives LF [IND, WAS] 2029 2nd (via NYK). Chain: WAS→IND (endnote 109 Beal), IND→NYK (endnote 129 Toppin), NYK→POR (endnote 190 Kolek). Shorthands: `LF [IND, WAS]` for POR MAY_HAVE, `IND`/`WAS` for origin rows. Direction-aware: `To POR: WAS` for WAS outgoing.
