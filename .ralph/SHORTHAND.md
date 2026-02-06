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

### Top clusters (3-row clusters) (refreshed 2026-02-06)

As of this refresh: **128 rows** remain with `primary_todo_reason='missing_shorthand'` for `draft_year >= 2026`.

Ordered by rows in `pcms.vw_draft_pick_shorthand_todo` where `primary_todo_reason='missing_shorthand'` and `draft_year >= 2026`.

Note: there are currently **no 4+ row clusters**; the largest clusters are 3 rows.

There are currently 10 3-row clusters; ordered by endnote_id desc.

- [x] Endnote 235 (3 rows) - San Antonio conveys to Sacramento: → The future conditional first round draft pick (Charlotte's own) that San Antonio is entitled to receive from Atlanta (per endnote 59)
- [x] Endnote 169 (3 rows) - Dallas conveys to Charlotte: → DAL 2027 1st
- [x] Endnote 146 (3 rows) - Milwaukee conveys to Portland: → Right to swap POR 2028 1st for MIL 2028 1st
- [x] Endnote 59 (3 rows) - ATL conveys to SAS: → CHA 1st (via NYK/endnote 41)
- [x] Endnote 41 (3 rows) - NYK conveys to ATL: → CHA 1st (via NYK/endnote 28)
- [x] Endnote 37 (3 rows) - POR conveys to CHI: → POR 1st (First allowable draft, 2022-2028)
- [ ] Endnote 28 (3 rows) - CHA conveys to NYK: → CHA 1st
- [ ] Endnote 25 (3 rows) - LAC conveys to ORL: → DET 2026 2nd (via endnote 6)
- [ ] Endnote 6 (3 rows) - DET conveys to LAC: → DET 2026 2nd
- [ ] Endnote 5 (3 rows) - MIL conveys to ORL: → MIL 2026 2nd

### Smaller clusters / follow-ups (2-row clusters) (refreshed 2026-02-06)

All entries below are currently tied at 2 rows; ordered by endnote_id desc.

- [ ] Endnote 322 (2 rows) - Brooklyn conveys to Miami: → Brooklyn's own 2026 2nd round pick
- [ ] Endnote 317 (2 rows) - Sacramento conveys to Detroit: → Charlotte's own 2026 2nd round pick (via endnote 235)
- [ ] Endnote 311 (2 rows) - Golden State conveys to Memphis: → Golden State's own 2032 2nd round pick
- [ ] Endnote 290 (2 rows) - Orlando conveys to Boston: → MF [ORL, DET, MIL] 2026 2nds (via endnotes 25/5)
- [ ] Endnote 288 (2 rows) - Utah conveys to Washington: → MF [IND, MIA] 2031 2nds (via endnote 258)
- [ ] Endnote 262 (2 rows) - Toronto conveys to Indiana: → TOR 2026 2nd
- [ ] Endnote 258 (2 rows) - Miami conveys to Utah: → The Resulting Pick
- [ ] Endnote 244 (2 rows) - Boston conveys to Houston: → LF [NOP, POR] 2027 2nds (via endnote 176)
- [ ] Endnote 242 (2 rows) - Sacramento conveys to Washington: → DEN 2028 2nd (via endnote 238)
- [ ] Endnote 238 (2 rows) - San Antonio conveys to Sacramento: → DEN 2028 2nd (via endnote 42)
- [ ] Endnote 209 (2 rows) - Denver conveys to Charlotte: → DEN 2029 2nd
- [ ] Endnote 203 (2 rows) - Brooklyn conveys to New York: → LF [DET, MIL, ORL] 2026 2nds (via endnote 170)
- [ ] Endnote 201 (2 rows) - Memphis conveys to Minnesota: → MEM 2030 2nd
- [ ] Endnote 197 (2 rows) - Portland conveys to Washington: → 2nd MF [POR, BOS, MIL] 2029 1sts (origin rows outstanding)
- [ ] Endnote 194 (2 rows) - Phoenix conveys to New York: → BOS 2028 2nd (via endnote 144)
- [ ] Endnote 176 (2 rows) - Portland conveys to Boston: → LF [POR, NOP] 2027 2nds (via endnote 45)
- [ ] Endnote 170 (2 rows) - Phoenix conveys to Brooklyn: → LF [DET, MIL, ORL] 2026 2nds (via endnote 143)
- [ ] Endnote 149 (2 rows) - Boston conveys to Portland: → BOS 2029 1st
- [ ] Endnote 147 (2 rows) - Milwaukee conveys to Portland: → MIL 2029 1st
- [ ] Endnote 144 (2 rows) - Orlando conveys to Phoenix: → BOS 2028 2nd (via endnote 48)
- [ ] Endnote 143 (2 rows) - Orlando conveys to Phoenix: → LF [ORL, DET, MIL] 2026 2nds (via endnotes 25/5)
- [ ] Endnote 95 (2 rows) - Portland conveys to Charlotte: → MF [POR, NOP] 2027 2nds (via endnote 45)
- [ ] Endnote 71 (2 rows) - LAL conveys to WAS: → LF [LAL, WAS] 2028 2nd (via endnote 32)
- [ ] Endnote 63 (2 rows) - MIN conveys to UTA: → MIN 2029 1st (conditional; see endnote text for protections)
- [ ] Endnote 49 (2 rows) - PHI conveys to BKN: → PHI "First Allowable Draft" 1st
- [ ] Endnote 48 (2 rows) - BOS conveys to ORL: → BOS 2028 2nd
- [ ] Endnote 42 (2 rows) - DEN conveys to SAS: → DEN 2028 2nd
- [ ] Endnote 36 (2 rows) - SAS swap right affecting IND/MIA/SAS 2026 2nd (feeds endnote 55)
- [ ] Endnote 4 (2 rows) - HOU conveys to OKC: → HOU 2026 1st (conditional)

### One-offs (1-row clusters)

There are currently many 1-row endnote clusters (130 as of this refresh). Use the work-queue query to pull the next one when you're done with the 2-row clusters.

- [ ] Endnote 246 (1 row) - BOS 2031 2nd MAY_HAVE: `may have HOU(246)`
- [ ] Endnote 211 (1 row) - MIN 2031 2nd MAY_HAVE: `May have GSW(211)`
- [ ] Endnote 193 (1 row) - ORL 2031 2nd MAY_HAVE: `May have NOP(193)` (swap right conveyed from NOP)
- [ ] Endnote 50 (1 row) - BOS 2028 2nd outgoing row: "Own or to SAS(50) or to NYK(194)" (likely shorthand `BOS`)
- [ ] Endnote 9 (1 row) - MIL 2026 1st MAY_HAVE: `May have NOP(9)`

---

## Done (append-only)

When you complete a cluster, add a bullet here with:
- endnote_id
- 1-2 sentence description
- key shorthand(s)
- quick verification query link/snippet (optional)

Note: any `To XYZ: ...` snippets mentioned below are examples of `pcms.vw_draft_pick_assets.display_text` (direction-aware rendering), not the underlying `shorthand` value.

- Endnote 125 - DET→WAS conveys the MF of BKN/DAL 2027 2nds (via DET); DET retains the LF. Added shorthands: `MF [BKN, DAL]` (WAS) and `LF [BKN, DAL]` (DET), plus origin rows `BKN`/`DAL` for direction-aware outgoing display.
- Endnote 64 - NYK conveys to DET the MF of NYK/MIN 2026 2nds (Burks/Noel, 7/11/2022). Added origin shorthands `NYK` and `MIN` (including the NYK "may have MIN" branch) so outgoing rows render direction-aware `To ...` display.
- Endnote 52 - OKC→NYK conveys WAS future conditional 1st (Dieng trade, 6/23/2022). Full chain: Endnotes 15→27→52 (Wall-Westbrook → Sengün → Dieng). NYK receives WAS 2026 1st if 9-30 (top-8 protected); if not conveyed, NYK instead receives WAS 2026+2027 2nds. Shorthands: `WAS (p. 1-8)` for the 1st, `WAS` for the fallback 2nds, `Own to NYK (p. 1-8)` / `Own to NYK` for WAS outgoing rows.
- Endnote 50 - BOS↔SAS 2028 1st swap (White-Langford-Richardson trade, 2/10/2022). SAS has right to swap their 2028 1st for BOS's 2028 1st (top-1 protected). If swap lapses (BOS gets #1), SAS gets BOS 2028 2nd (picks 31-45 only). Shorthands: `BOS`/`SAS` for 1st round OWN/MAY_HAVE rows, `BOS (p. 1)` for SAS swap right, `BOS (p. 31-45)` for 2nd round fallback.
- Endnote 45 - NOP→POR 2027 2nd (McCollum trade, 2/8/2022). NOP conveys 2027 2nd to POR, which then feeds into pool logic: CHA gets MF [POR, NOP] (endnote 95), HOU gets LF [NOP, POR] via BOS (endnotes 176, 244). Shorthand: `NOP` for all 4 rows representing the NOP pick's flow through the chain.
- Endnote 27 - Already covered by endnote 52 (Sengün trade, 7/30/2021). This was the middle step in the HOU→OKC→NYK chain for WAS 1st. All 6 rows already have shorthand from endnote 52 curation: `WAS (p. 1-8)` / `WAS` for NYK's MAY_HAVE, `Own to NYK (p. 1-8)` / `Own to NYK` for WAS outgoing.
- Endnote 15 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (this endnote is already covered by the Endnote 52 chain; Wall/Westbrook → Sengün → Dieng).
- Endnote 197 - Cleanup: removed embedded "To WAS:" prefix from POR's shorthand (`2nd MF [POR, BOS, MIL]`) so direction stays with `vw_draft_pick_assets.display_text`.
- Endnote 197 (follow-up) - As of 2026-02-06, `pcms.vw_draft_pick_shorthand_todo` still shows 2 `missing_shorthand` rows tied to endnote 197; keep this cluster in the active backlog until the origin rows are fully filled in.
- Endnote 16 - PHI→OKC Horford trade (12/8/2020). PHI conveys conditional 1st (2026/2027 top-4 protected); fallback is PHI 2027 2nd unconditionally. Shorthands: `PHI (p. 1-4)` for 1st round rows, `PHI` for 2nd round fallback.
- Endnote 321 - BOS→UTA Luis/Niang trade (8/6/2025). UTA receives MF [BOS, CLE] 2031 2nd. CLE pick flows via ATL (endnote 272) then BOS (endnote 313). Shorthands: `MF [BOS, CLE]` for UTA's primary MAY_HAVE, `BOS`/`CLE` for origin picks.
- Endnote 320 - BOS→UTA Luis/Niang trade (8/6/2025). UTA receives MF [BOS, ORL] 2027 2nd. BOS pick originally went to ORL (endnote 23), then ORL/BOS pool via endnote 291. Shorthands: `MF [BOS, ORL]` for UTA's MAY_HAVE rows, `BOS`/`ORL` for origin picks.
- Endnote 319 - SAS→WAS Olynyk/Branham trade (7/9/2025). WAS receives LF [DAL, OKC, PHI] 2026 2nd (via SAS→MIA→OKC chain). OKC holds 3-pick pool (own, DAL via endnote 14, PHI via endnote 21): MF stays with OKC, 2nd MF to PHX (endnote 307 via HOU/endnote 70), LF to WAS. Shorthands: `OKC`/`DAL`/`PHI` for origin rows, direction-aware `To WAS: DAL`/`To WAS: PHI` for outgoing.
- Endnote 316 - DET→SAC Schröder trade (7/7/2025). SAC receives LF [DET, MIL, NYK] 2029 2nd; DET retains the other two. MIL pick flows via BKN→DET (endnotes 80/115), NYK pick flows via endnote 165. Shorthands: `DET`/`MIL`/`NYK` for origin rows, direction-aware `To SAC: MIL`/`To SAC: NYK` for outgoing.
- Endnote 310 - PHX→MIN Durant trade (7/6/2025). MIN receives MF [HOU, PHX] 2032 2nd. HOU pick flows via PHX (endnote 308). Shorthands: `MF [HOU, PHX]` for MIN's MAY_HAVE rows, `PHX`/`HOU` for origin picks, direction-aware `To MIN: HOU` for outgoing.
- Endnote 307 - Already curated as part of endnote 319 (WAS receives LF). PHX receives 2nd MF [DAL, OKC, PHI] 2026 2nd via HOU (endnote 70). All 8 rows have shorthand: PHX MAY_HAVE rows get `2nd MF [DAL, OKC, PHI]`, OKC keeps MF (own pick + DAL/PHI via endnotes 14/21), origin rows show direction-aware outgoing to WAS.
- Endnote 295 - PHX→CHA Micic-Williams trade (6/30/2025). CHA receives the 2029 1st that PHX is entitled to from UTA (per endnote 231): the LF of [CLE, MIN, UTA] 2029 1sts. Chain: CLE→UTA (endnote 68 Mitchell), MIN→UTA (endnote 63 Gobert, conditional), UTA→PHX (endnote 231), PHX→CHA (endnote 295). CHA MAY_HAVE rows already had `LF [CLE, MIN, UTA]`. Added origin shorthands: `CLE`/`MIN`/`UTA` for direction-aware outgoing (CLE shows `To CHA: CLE`).
- Endnote 291 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 320 (BOS↔ORL pool → UTA) curation.
- Endnote 231 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 295 (UTA→PHX → CHA) chain curation.
- Endnote 308 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 310 (PHX→MIN) curation.
- Endnote 123 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319/307 OKC 2026 2nd pool curation.
- Endnote 70 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319/307 OKC 2026 2nd pool curation.
- Endnote 46 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote fully covered by the Endnote 319 OKC→WAS chain curation.
- Endnote 293 - UTA→CHA MF [UTA, LAC] 2030 2nd (Sexton-Nurkic trade, 6/29/2025). CHA receives the MF of UTA's own 2030 2nd and the LAC 2030 2nd (which flows to UTA via endnote 232 Eubanks trade). Shorthands: `MF [UTA, LAC]` for CHA's MAY_HAVE rows, `UTA`/`LAC` for origin picks, direction-aware `To CHA: LAC` for LAC outgoing.
- Endnote 248 - PHI→WAS Butler-Jackson trade (2/6/2025). PHI conveys to WAS the 2026 1st they receive from OKC (per endnote 156 Harden trade). The pick is the LF of [LAC, OKC, HOU (p. 1-4)]. Added origin shorthands: `HOU (p. 1-4)` for HOU OWN and OKC MAY_HAVE HOU rows, `LAC` for LAC TO OKC and OKC MAY_HAVE LAC rows, `OKC` for OKC OWN. Direction-aware display: `To WAS: LAC` for outgoing LAC row.
- Endnote 230 - UTA→PHX Suns-Jazz trade (1/21/2025). PHX receives LF [CLE, MIN, UTA] 2027 1st. CLE pick flows via endnote 66 (Mitchell), MIN pick flows via endnote 62 (Gobert). PHX MAY_HAVE rows already had `LF [CLE, MIN, UTA]`. Added origin shorthands: `CLE`/`MIN`/`UTA` for origin and UTA MAY_HAVE rows. Direction-aware display: `To PHX: CLE` and `To PHX: MIN` for outgoing.
- Endnote 202 - NOP→ATL Murray trade (7/6/2024). ATL receives LF [NOP, MIL] 2027 1st (top-4 protected, obligation extinguished if not conveyed). MIL pick flows via Holiday trade (endnote 8). Shorthands: `LF [NOP, MIL] (p. 1-4)` for ATL MAY_HAVE rows, `NOP (p. 1-4)` for NOP origin, `MIL` for MIL origin. Direction-aware: `To ATL: MIL` for MIL outgoing.
- Endnote 190 - NYK→POR Kolek trade (6/27/2024). POR receives LF [IND, WAS] 2029 2nd (via NYK). Chain: WAS→IND (endnote 109 Beal), IND→NYK (endnote 129 Toppin), NYK→POR (endnote 190 Kolek). Shorthands: `LF [IND, WAS]` for POR MAY_HAVE, `IND`/`WAS` for origin rows. Direction-aware: `To POR: WAS` for WAS outgoing.
- Endnote 129 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote covered by the Endnote 190 chain curation (IND→NYK step).
- Endnote 109 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote covered by the Endnote 190 chain curation (WAS→IND step).
- Endnote 8 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; endnote covered by the Endnote 202 curation (MIL pick source in the NOP/ATL pool).
- Endnote 128 - IND→NYK Toppin trade (7/7/2023). NYK receives LF [IND, PHX] 2028 2nd. PHX pick flows to IND via endnote 107 (Beal trade). Shorthands: `LF [IND, PHX]` for NYK MAY_HAVE rows, `IND`/`PHX` for origin rows. Direction-aware: `To NYK: PHX` for PHX outgoing.
- Endnote 101 - DEN→OKC "First Allowable Draft" 1st (Pickett-Strawther trade, 6/23/2023). OKC receives DEN 1st 2 years after endnote 53 pick conveys (determined to be 2029). Top-5 protected 2029 and 2030; if not conveyed by 2030, OKC gets DEN 2030 2nd unconditionally. Shorthands: `DEN (p. 1-5)` for OKC MAY_HAVE and DEN OWN 1st round rows, `DEN` for 2nd round fallback. Direction-aware: `To OKC: DEN` for 2nd round outgoing.
- Endnote 47 - UTA→SAS LF [HOU, IND, MIA, OKC] 2027 2nd (Ingles trade, 2/9/2022). Added origin shorthands `HOU`, `IND`, `MIA` for the 3 TO rows feeding into OKC's pool. Direction-aware display: `To SAS: MIA`, `To NYK: HOU`, `To NYK: IND`.
- Endnote 107 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; this endnote is fully covered by the Endnote 128 (IND→NYK) curation.
- Endnotes 210 + 239 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; these are now covered by Endnote 101's DEN 2030 2nd fallback chain.
- Endnotes 10 + 12 + 19 + 20 + 30 + 124 + 187 + 188 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (covered by the Endnote 47 OKC 2027 2nd pool work); removed from active backlog.
- Endnote 50 (follow-up) - As of 2026-02-06, `pcms.vw_draft_pick_shorthand_todo` still shows 1 `missing_shorthand` row tied to endnote 50 (BOS 2028 2nd outgoing row). Keep this endnote in the One-offs section until resolved.
- Endnote 304 - HOU→ATL swap rights for 2031 2nd (massive trade, 7/6/2025). ATL has right to swap their 2031 2nd for HOU's, but only if HOU's pick is in picks 31-55. Shorthands: `ATL` for ATL OWN and HOU MAY_HAVE ATL rows, `HOU (p. 31-55)` for ATL MAY_HAVE HOU (reflects protection), `HOU` for HOU OWN.
- Endnote 283 - NOP→ATL "Resulting Pick" (Newell-Queen trade, 6/25/2025). ATL receives MF [MIL, NOP] 2026 1st: NOP either keeps their own or swaps for MIL's via endnote 9 (Holiday trade), conveying the more favorable to ATL. Shorthands: `MIL`/`NOP` for ATL MAY_HAVE origin rows, `MIL`/`NOP` for MIL OWN and NOP TO outgoing. Direction-aware: `To ATL: NOP` for NOP outgoing.
- Endnote 256 - GSW→DET "Resulting Pick" 2031 2nd (massive trade, 2/6/2025). DET receives either GSW's own 2031 2nd or MIN's 2031 2nd (if MIN exercises swap right via endnote 211). Shorthands: `GSW`/`MIN` for DET MAY_HAVE rows, `GSW` for GSW TO (outgoing), `MIN` for MIN OWN. Direction-aware: `To DET: GSW` for GSW outgoing.
- Endnote 241 - NOP→OKC "Result Pick" 2031 2nd (Theis trade, 2/5/2025). OKC receives either NOP's own 2031 2nd or ORL's 2031 2nd (if ORL exercises swap right per endnote 193 Reeves trade). Shorthands: `NOP` for NOP TO and OKC MAY_HAVE NOP rows, `ORL` for OKC MAY_HAVE ORL and ORL OWN rows. Direction-aware: `To OKC: NOP` for NOP outgoing.
- Endnote 212 - SAC→SAS swap right for 2031 1st (DeRozan trade, 7/8/2024). SAS has the right to swap their 2031 1st for SAC's 2031 1st (auto-exercise if SAC pick more favorable). Shorthands: `SAC` for SAC OWN and SAS MAY_HAVE SAC rows, `SAS` for SAS OWN and SAC MAY_HAVE SAS rows.
- Endnote 192 - NOP→ORL swap right for 2030 2nd (Reeves trade, 6/27/2024). ORL has right to swap their 2030 2nd for NOP's 2030 2nd. Shorthands: `NOP` for NOP OWN and ORL MAY_HAVE NOP rows, `ORL` for ORL OWN and NOP MAY_HAVE ORL rows.
- Endnote 163 - DAL→OKC swap right for 2028 1st (trade, 2/8/2024). OKC has the right to swap their 2028 1st for DAL's 2028 1st. Shorthands: `DAL` for DAL OWN and OKC MAY_HAVE DAL rows, `OKC` for OKC OWN and DAL MAY_HAVE OKC rows.
- Endnote 159 - MIA→CHA Rozier-Lowry trade (1/23/2024). CHA receives MIA 1st in "First Allowable Draft" (2027), top 14 protected; if not conveyed, rolls to 2028 unprotected. Shorthands: `MIA (p. 1-14)` for 2027 rows, `MIA` for 2028 fallback rows.
- Endnote 154 - LAC→PHI Harden trade (11/1/2023). PHI receives swap right: can swap their 2029 1st for LAC's 2029 1st, top-3 protected (extinguished if LAC pick is 1-3). Shorthands: `LAC`/`PHI` for OWN rows, `PHI` for LAC MAY_HAVE, `LAC (p. 1-3)` for PHI MAY_HAVE (swap right).
- Endnote 152 - LAC→OKC swap right for 2027 1st (Harden trade, 11/1/2023). OKC has right to swap the "Result Pick" (OKC own or LF [OKC, DEN (p. 1-5)] per endnote 53) for LAC's 2027 1st. Shorthands: `LAC` for LAC OWN and OKC MAY_HAVE LAC rows, `OKC` for OKC OWN and LAC MAY_HAVE OKC rows.
- Endnote 148 - MIL→POR swap right for 2030 1st (Lillard trade, 9/27/2023). POR has right to swap their 2030 1st for MIL's 2030 1st (auto-exercise if MIL pick more favorable). Shorthands: `MIL` for MIL OWN and POR MAY_HAVE MIL rows, `POR` for POR OWN and MIL MAY_HAVE POR rows.
- Endnote 116 - GSW→WAS Paul/Poole trade (7/6/2023). WAS receives GSW 2030 1st (top-20 protected); if not conveyed, WAS receives GSW 2030 2nd unconditionally. Shorthands: `GSW (p. 1-20)` for 1st round rows, `GSW` for 2nd round fallback rows.
- Endnote 99 - UTA→MIN→SAS→MIL chain for UTA 2026 2nd. UTA's own 2026 2nd flows via MIN (endnote 78 Russell trade) to SAS (endnote 99 Miller trade), then conditionally to MIL (endnote 266 Kuzma/Middleton). Shorthand: `UTA` for all 3 rows. Direction-aware: `To MIL: UTA` for UTA outgoing.
- Endnote 89 - NOP→SAS LF [NOP, POR] 2026 2nd (Richardson-Graham trade, 2/9/2023). SAS receives the LF of NOP's own 2026 2nd and POR's 2026 2nd (which flows to NOP via endnote 26 Brown III trade). Shorthands: `LF [NOP, POR]` for SAS MAY_HAVE rows, `NOP`/`POR` for origin picks. Direction-aware: `To WAS: NOP` and `To WAS: POR` for outgoing.
- Endnote 266 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; covered by the Endnote 99 chain (SAS→MIL conveys UTA 2026 2nd). Shorthand: `UTA`.
- Endnote 78 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; covered by the Endnote 99 chain (UTA→MIN conveys UTA 2026 2nd). Shorthand: `UTA`.
- Endnote 60 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (POR→DET conveys MF [NOP, POR] 2026 2nd, via endnote 44). Key shorthands: `MF [MF [NYK, MIN], MF [NOP, POR]]` (upstream pool-of-pools), plus origin `NOP` / `POR`.
- Endnote 44 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (NOP→POR conveys MF [NOP, POR] 2026 2nd; includes POR 2026 2nd via endnote 26). Key shorthands: `NOP` / `POR`.
- Endnote 26 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (POR→NOP conveys POR 2026 2nd). Key shorthands: `POR` (origin) and downstream `LF [NOP, POR]`.
- Endnote 112 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (DET→BOS conveys MF of MF [NYK, MIN] and MF [NOP, POR] 2026 2nds). Key shorthands: `MF [MF [NYK, MIN], MF [NOP, POR]]`.
- Endnote 157 - No remaining `missing_shorthand` rows for `draft_year >= 2026` (DET→WAS conveys LF of MF [NYK, MIN] and MF [NOP, POR] 2026 2nds). Key shorthands: `LF [MF [NYK, MIN], MF [NOP, POR]]`.
- Endnote 77 - LAL→UTA Beasley-Russell-Vanderbilt trade (2/9/2023). LAL conveys 2027 1st to UTA, top-4 protected; if not conveyed, UTA receives LAL 2027 2nd unconditionally. Shorthands: `LAL (p. 1-4)` for 1st round rows, `LAL` for 2nd round fallback rows. Direction-aware: `To BKN: LAL` for LAL outgoing 2nd round (downstream to BKN via endnote 223).
- Endnote 55 - IND→MIN "Result Pick" 2026 2nd (Brown trade, 6/24/2022). MIN receives either `LF [IND, MIA]` or `SAS` own 2026 2nd, depending on whether SAS exercises swap per endnote 36 (McDermott trade). Shorthands: `IND`/`MIA`/`SAS` for MIN MAY_HAVE rows, `SAS` for SAS OWN row.
- Endnote 51 - LAL→ORL MF [LAL, WAS] 2028 2nd (Christie trade, 6/23/2022). WAS 2028 2nd flows to LAL via endnote 32 (Westbrook trade). LAL conveys MF to ORL (endnote 51); LF goes to WAS (endnote 71). Shorthands: `MF [LAL, WAS]` for ORL MAY_HAVE pool, `LAL`/`WAS` for origin rows. Direction-aware: `To WAS: LAL`, `To ORL: WAS`.
- Endnote 33 - MEM→UTA→multiple destinations chain for MEM 2026 2nd (Aldama/Butler trade, 8/7/2021). MEM's own 2026 2nd flows to UTA (endnote 33), then splits: GSW (endnote 34) → POR (endnote 87, conditional), or ATL (endnote 130) → LAC (endnote 273). Shorthand: `MEM` for all 3 rows. Direction-aware: `To LAC: MEM` for MEM outgoing.
- Endnote 17 - BKN/HOU 2027 1st swap (Harden trade, 1/16/2021). HOU has right to swap their 2027 1st for BKN's 2027 1st. Shorthands: `BKN` for BKN OWN and HOU MAY_HAVE BKN rows, `HOU` for HOU OWN and BKN MAY_HAVE HOU rows.
- Endnote 264 - PHX→CHA "Result Pick" 2026 1st (Nurkic-Martin-Micic trade, 2/6/2025). CHA receives the "Result Pick" which is `LF [PHX, ORL, WAS (p. 1-8), MEM]` depending on swap chain: WAS (endnote 102), ORL (endnote 145), MEM (endnote 173). Added origin shorthands: `PHX`/`ORL`/`MEM` for the 3 TO/OWN rows. Direction-aware: `To MEM: PHX`, `To MEM: ORL`.
- Endnotes 145 + 173 + 275 - No remaining `missing_shorthand` rows for `draft_year >= 2026`; these are all covered by the Endnote 264 "Result Pick" swap chain work.
- Endnotes 34 + 87 + 130 + 273 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; these are all covered by the Endnote 33 MEM 2026 2nd chain work.
- Endnote 235 — SAS→SAC CHA pick chain (Fox trade, 2/3/2025). CHA's own pick flows CHA→NYK(28)→ATL(41)→SAS(59)→SAC(235)→DET(317). Shorthand: `CHA` for CHA origin and SAC MAY_HAVE rows. Direction-aware: `To DET: CHA` for CHA outgoing.
- Endnote 169 — DAL→CHA P.J. Washington trade (2/8/2024). DAL 2027 1st (top-2 protected) to CHA; fallback is MIA 2028 2nd (via SAS/DAL per endnotes 76/142). Shorthands: `DAL (p. 1-2)` for CHA MAY_HAVE, `DAL` for DAL OWN, `MIA` for 2028 2nd fallback.
- Endnote 146 — MIL→POR swap right for 2028 1st (Lillard trade, 9/27/2023). POR has right to swap their 2028 1st for MIL's 2028 1st (auto-exercise if MIL pick more favorable and POR not obligated to CHI per endnote 37). Shorthands: `POR` for POR OWN, `MIL` for POR MAY_HAVE MIL (swap right).
- Endnote 59 — ATL→SAS conveys CHA protected 1st via NYK (endnotes 28/41); since CHA never conveyed the 1st (2022-2025), it converted into CHA 2026+2027 2nds. Shorthand on the resulting assets: `CHA`.
- Endnote 41 — No remaining `missing_shorthand` rows for `draft_year >= 2026`; this endnote is fully covered by the Endnote 235/59 chain (NYK→ATL step in the CHA→NYK→ATL→SAS→SAC→DET flow).
- Endnote 37 — POR→CHI 1st (Jones-Markkanen-Nance trade, 8/28/2021). POR 1st conveys to CHI in first allowable draft 2022-2028, top-14 protected each year. 1st round rows already had `POR (p. 1-14)` / `Own to CHI (p. 1-14)`. Added fallback 2nd round shorthands: `POR` for CHI MAY_HAVE, `Own to CHI` for POR OWN (if 1st never conveys, CHI receives POR 2028 2nd unconditionally).
