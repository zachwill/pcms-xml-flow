# Draft Picks (PCMS + Endnotes + Shorthand)

Last updated: 2026-02-04

This repo needs to answer two related questions:

1) **What does PCMS say each team owns right now?** (provenance-first, text-heavy, conditional)
2) **How do we express the *net* pick logic cleanly?** (swap pools, protections, “result pick” cascades)

PCMS provides (1). Sean’s workbook shorthand provides (2). Our approach is to keep both, with clean joins.

---

## TL;DR — Conclusions we’ve reached

- **NBA picks are not in `draft_picks.json`** (the `dp-extract`); NBA pick ownership only comes from **`draft_pick_summaries.json`** (`dps-extract`).

- The parenthetical numbers in PCMS summary text (e.g. `To SAS(58)`) are best treated as **Draft List Endnote IDs** (the NBA’s published endnote corpus), not `trade_id`/`transaction_id`.
  - PCMS does not ship a lookup table.
  - We ingest/curate the endnote corpus into **`pcms.endnotes`**, and treat these numbers as join keys.

- **PCMS summaries are provenance-first** and use patterns like `Own`, `To`, `Has`, `May have`, `via`, `or to`, plus `|` and `;` separators.
  - They often describe branching outcomes but do **not** provide a compact MF/LF pool representation.

- Sean’s workbook uses a compact “pick shorthand” language for the *net logic*:
  - `MF [ ... ]` and `LF [ ... ]` pools
  - protections like `WAS (p. 1-8)`
  - nested pools to represent sequential swap rights
  - ordinals like `1st MF`, `2nd MF`, `3rd MF` when multiple picks come from one pool

- We will adopt a **Sean-style pick shorthand**, but with two strong rules:
  1) **Do not embed endnote numbers in the shorthand string** (so parentheses are reserved for protections).
  2) **Do not collapse/shortcut ownership** (e.g. avoid display-driven collapsing like “1st MF + 2nd MF → 2 MF …”).

- Shorthand must live in its own durable table (not a refresh-truncated warehouse). That table is:
  - **`pcms.draft_pick_shorthand_assets`** (migration `065_draft_pick_shorthand_assets.sql`)

---

## Data sources

### 1) PCMS (authoritative snapshot)

- **`draft_pick_summaries.json`** (`dps-extract`)
  - Per-team-per-year text describing pick assets (NBA).

- **`draft_pick_trades`** (PCMS)
  - Trade movement rows that can be aggregated into “possible outcomes” per original pick.

### 2) Endnotes corpus (human-readable trade rules)

- Source files live in: `~/blazers/cba-docs/endnotes/{original,revised}`
- We ingest them into: **`pcms.endnotes`**
  - Including dependencies (`depends_on_endnotes`) and split-out fields like `conveyance_text`, `protections_text`, `exercise_text`, etc.

### 3) Sean workbook shorthand (net-effect representation)

- Exported evidence/spec:
  - `reference/warehouse/draft_picks.json`
  - `reference/warehouse/specs/draft_picks.md`

This is a great *seed* for shorthand, but it is messy (spacing inconsistencies, occasional bracket mismatches, analyst notes embedded in strings).

---

## PCMS `draft_pick_summaries` format (what we parse)

PCMS provides two fields per team/year:
- `first_round`
- `second_round`

Common patterns:

| Pattern | Meaning | Example |
|---|---|---|
| `Own` | Team owns its own pick | `Own` |
| `To TEAM(N)` | pick traded away to TEAM | `To SAS(58)` |
| `Has TEAM(N)` | acquired pick from TEAM | `Has HOU(81)` |
| `May have TEAM(N)` | conditional ownership | `May have MIL(202)` |
| `(via TEAM(N))` | provenance routing | `(via PHX(173))` |
| `or to TEAM(N)` | alternative destination branch | `or to DET(317)` |
| `|` | splits this team’s pick status from other teams’ picks owned/controlled (max 2 fragments in practice) | `Own | Has DAL(70)` |
| `;` | splits multiple pieces within a fragment (multiple picks and/or branch clauses) | `may have ORL(...); may have PHX(...)` |

### Important: parenthetical numbers

The numeric ids like `(58)` in `To SAS(58)` are treated as **endnote IDs**.

- PCMS does not ship an official mapping.
- Our working assumption (validated on many complex cases) is:
  - these ids correspond to the “Draft List Endnotes” corpus,
  - which we ingest into `pcms.endnotes`.

When an id is present in summaries but missing from `pcms.endnotes`, we treat it as **needs review**.

---

## Postgres tables (what exists / how it’s used)

### Raw

- `pcms.draft_pick_summaries`
  - Stores PCMS snapshot text per team/year.

- `pcms.draft_pick_trades`
  - Trade movements (provenance/movement granularity).

### Summary-derived pieces (refreshable, do not hand-edit)

- `pcms.draft_pick_summary_assets`
  - Splits `pcms.draft_pick_summaries.first_round/second_round` by:
    - `|` → `asset_slot` (PCMS uses at most 2 today: **own-pick status** | **other teams’ picks**)

    - `;` → `sub_asset_slot`
  - Keeps both:
    - `raw_fragment` (pipe fragment)
    - `raw_part` (semicolon piece)
  - Extracts endnote ids **per raw_part** into `endnote_refs` (this is the key fix vs legacy warehouses).
  - Adds helper fields:
    - `missing_endnote_refs`
    - `counterparty_team_codes`, `via_team_codes`
    - `primary_endnote_id` + joined `endnote_*` helper columns

> Design note: this table is still provenance-first and intentionally **does not resolve** protections/swaps into a deterministic final pick. It surfaces the NBA summary text + endnote refs in an analyzable shape.

### Curated shorthand (durable, hand-authored or imported)

- `pcms.draft_pick_shorthand_assets`
  - One row per `(team_code, draft_year, draft_round, asset_slot, sub_asset_slot)`.
  - Stores:
    - `shorthand_input` (raw, messy)
    - `shorthand` (canonical pretty-printed)
    - `endnote_ids int[]` (kept *out* of shorthand string)
    - `referenced_team_codes text[]` (search/filter)
    - `notes`, `source_lk`, `needs_review`

Migrations:
- `migrations/065_draft_pick_shorthand_assets.sql`
- `migrations/068_draft_pick_shorthand_assets_sub_asset_slot.sql`

---

## Pick Shorthand language (Sean-style) — what we’re adopting

### Atoms

- `Own` = the current row team’s own pick
- `BKN`, `SAS`, `PHX`, etc = another team’s pick
- Protections use parentheses:
  - `WAS (p. 1-8)`
  - `POR (p. 1-14)`
  - `MIN (p. 1)`

### Operators

- `MF [ ... ]` = **Most Favorable** pick in the pool
- `LF [ ... ]` = **Least Favorable** pick in the pool

Semantics:
- “More favorable” == earlier pick (smaller pick number).
- Applies to both rounds (e.g. pick 31 is the most favorable 2nd).

### Ordinals (multiple picks out of one pool)

- `1st MF [A, B, C]`
- `2nd MF [A, B, C]`
- `3rd MF [A, B, C]`

We keep ordinals explicitly per asset slot; we do **not** compress them into display-only hacks.

### Nesting

Nested pools represent sequential swap rights.

Key mental model:
- If Team X has a swap right between pick A and pick B and will exercise when favorable:
  - X’s outcome is typically `MF [A, B]`
  - the counterparty’s outcome is typically `LF [A, B]`

“Result Pick” cascades (multiple swaps into the same pick) often become a multi-team `LF [...]`.

### Canonical formatting

We accept messy input but canonicalize to:

- `MF [A, B]`
- `LF [A, MF [B, C]]`

### Directionality (outgoing vs incoming)

PCMS summary text is provenance-first and includes directionality in `raw_part` via tokens like `To XYZ(...)`.

Our curated `shorthand` is **not** a sentence and should remain a pure MF/LF-style pick-expression.
That means the *same* shorthand may appear on both:
- an outgoing row (`To XYZ(...)`), and
- an incoming/receiver row (`Has XYZ(...)` / `May have XYZ(...)`),
when they refer to the same underlying pick right.

To avoid confusion for human readers, the overlay view **renders outgoing directionality in `display_text`**:

- If `raw_part` begins with `To ...`, then:
  - `display_text = "To XYZ: " || coalesce(shorthand, raw_part)`
- Otherwise:
  - `display_text = coalesce(shorthand, raw_part)`

So a team that has traded away a pick will display like:

- `To UTA: LF [DET (p. 31-55), LF [NYK, LF [CHA, LAC], MIA]]`

while the receiving side displays the same underlying pick-expression without the `To ...` prefix.

Spacing rules:
- Always `MF [ ... ]` / `LF [ ... ]`
- Comma+space between elements
- Protections: `TEAM (p. 1-8)` (normalize `p.1-8` → `p. 1-8`)

Team codes:
- Canonical NBA abbreviations (e.g. `BKN`, `SAS`).
- Import-time alias mapping allowed (e.g. `BRK→BKN`, `SAN→SAS`).
- DB gotcha: `pcms.teams.team_code` is **not globally unique** (NBA/WNBA/UNK share codes). When joining by `team_code`, filter `pcms.teams.league_lk='NBA'` (or prefer `team_id` where available).

---

## Why shorthand is separate from endnotes

Endnotes contain a lot of information that is *not* pick-ranking logic:
- notice windows
- deadlines
- “not prior to the lottery” constraints
- cash contingencies
- descriptive “Result Pick” definitions

Shorthand is meant to encode **ranking resolution** (MF/LF + protections).

Therefore:
- **Do not embed endnote numbers in shorthand strings.**
- Store the join keys in `endnote_ids`.
- Store extra narrative constraints in `notes` (or by joining to `pcms.endnotes.*_text`).

---

## Worked examples (endnotes → shorthand)

These are representative of the “hard” cases and validate the MF/LF approach.

### Endnote 264 (Nurkic/Martin/Micic)

Endnote: Phoenix conveys to Charlotte the “Result Pick”, but WAS/ORL/MEM can swap into it first.

Shorthand (CHA 2026 1st):

```text
LF [PHX, ORL, WAS (p. 1-8), MEM]
```

Endnotes to attach:

```text
{264, 102, 145, 173}
```

### Endnote 268 (LeVert/Hunter)

Endnote: ATL can swap ATL/SAS pick for CLE/UTA/MIN pick, but both sides have upstream swap logic.

Shorthand (ATL 2026 1st, conceptual):

```text
MF [
  LF [Own, SAS],
  LF [CLE, MF [UTA (p. 1-8), MIN]]
]
```

### Endnote 183 (Dillingham)

MIN conveys to SAS a swap right vs MIN 2030 1st; the “Result Pick” is SAS 2030 unless SAS upgrades to DAL.

Shorthand (SAS 2030 1st, conceptual):

```text
MF [Own, DAL, MIN (p. 1)]
```

### Endnote 134 (Brooks/Garuba/Mills)

HOU gets LAC 2026 2nd unless MEM swaps, in which case HOU gets the “Result Pick” from a MF/LF chain.

Shorthand (BRK 2026 2nd in Sean workbook; similar structure):

```text
LF [LAC, MF [BOS, IND, MIA]]
```

---

## Import strategy (Sean → `draft_pick_shorthand_assets`)

Recommendation: **hybrid**.

- Import Sean to seed the table quickly (he’s already composed the hardest swap stacks).
- Then selectively rewrite/override rows using `pcms.endnotes` as the audit trail.

High-level import steps:

1) Read Sean `reference/warehouse/draft_picks.json` **Pick Details** (column `F`) — not the display shorthand column.
2) Normalize team codes (BRK→BKN, SAN→SAS).
3) Canonicalize formatting (spacing, commas, `p.` spacing).
4) Map rows to `(team_code, draft_year, draft_round, asset_slot, sub_asset_slot)` (summary piece keys).
   - attach endnotes by copying `pcms.draft_pick_summary_assets.endnote_refs` into `endnote_ids` (and optionally add dependencies).
5) Insert with `source_lk='imported_sean'`.
6) Mark `needs_review=true` if the string is malformed (e.g. unbalanced brackets) or if mapping is ambiguous.

---

## Rewrite strategy (endnotes-first)

Rewriting from scratch is feasible and desirable for:
- **our team’s picks**
- the most complicated/high-leverage endnotes

Rewriting the entire league from scratch implies building a full evaluator that:
- resolves global dependency chains across many endnotes
- handles protection rollovers
- models notice windows / conditional exercise rules

That is possible but is a distinct project.

---

## Open questions / next steps

- Implement a minimal parser/pretty-printer that:
  - accepts messy shorthand input
  - outputs canonical `shorthand`
  - extracts `referenced_team_codes`
  - optionally builds `shorthand_ast`

- Decide how we want to represent true branching (“or … if …”) in shorthand:
  - keep it out of shorthand and in `notes`?
  - or allow an explicit branch operator in AST?

- Overlay/workbench views (implemented):
  - `pcms.vw_draft_pick_assets` — wide overlay of summary + shorthand + endnotes
    - `display_text = coalesce(shorthand, raw_part)`
  - `pcms.vw_draft_pick_shorthand_todo` — work queue (missing shorthand / needs_review / missing endnotes)
  - `pcms.vw_draft_pick_shorthand_orphans` — shorthand rows whose key no longer exists in the current summary parse
