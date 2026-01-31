# Spec: `draft_picks.json`

**Status:** 2026-01-31

---

## 1. Purpose

The **Draft Picks** sheet is a comprehensive database tracking future NBA draft pick ownership, trades, protections, and conditional clauses. It answers questions like:

- "Which picks does OKC own?"
- "What protections exist on the WAS 2026 1st round pick?"
- "Which picks are involved in swap scenarios (MF/LF)?"

The sheet assigns a **Score** (column D) to each pick entry, presumably reflecting pick value/probability (higher = more valuable or certain).

---

## 2. Key Inputs / Controls

This sheet has **no user inputs or selectors**. It's a raw data table that other sheets reference.

---

## 3. Key Outputs

| Zone | Rows | Columns | Description |
|------|------|---------|-------------|
| **Header** | 1-2 | B-G | Title "DRAFT PICK COLLECTION" + column headers |
| **Round 1 data** | 3-221 | B-G | ~219 Round 1 pick entries |
| **Round 2 data** | 222-593+ | B-G | ~372 Round 2 pick entries |

**614 total rows** (including header + empty trailing rows).

Counts:
- **255 Round 1** entries
- **337 Round 2** entries
- Years covered: 2026-2032 (plus header "Year")

---

## 4. Layout / Zones

### Columns

| Column | Header | Meaning |
|--------|--------|---------|
| B | Team | Team code (3-letter: WAS, BOS, OKC, etc.) |
| C | Round | `1` or `2` |
| D | Score | Numeric value (e.g., `10`, `6.25`, `0.3`) — pick valuation/probability |
| E | Year | Draft year (2026-2032) |
| F | Pick Details | Human-readable description of ownership, protections, swaps |
| G | Short Hand | **Formula column** — computed shorthand version of pick details |

### Pick Details Notation (Column F)

Sean uses a domain-specific notation to express complex pick ownership:

| Pattern | Meaning |
|---------|---------|
| `Own` | Team owns their own pick outright |
| `Own to NYK (p. 1-8)` | Owned by team, but conveys to NYK if pick lands 1-8 |
| `MF [Own,PHX]` | "Most Favorable" — team gets better of Own or PHX pick |
| `LF [Own,NOP]` | "Least Favorable" — team gets worse of Own or NOP pick |
| `1st MF [Own, MIN, CLE]` | First pick from MF pool of 3 |
| `2nd MF [Own,DAL,PHX]` | Second pick from MF pool |
| `PHX` | Pick acquired from Phoenix |
| `BRK (p. 31-55)` | Pick from Brooklyn with protection range 31-55 |

**Nested expressions** are common:
```
MF [MF [Own, LF [BRK,PHI (p.1-8),PHX], LF [POR (p.1-14),MIL]]]
```

---

## 5. Cross-Sheet Dependencies

### Sheets that reference Draft Picks

**`pick_database.json`** heavily references this sheet via FILTER formulas:

```
=IFERROR(
  _xlfn.TEXTJOIN("; ", TRUE,
    _xlfn._xlws.FILTER(
      'Draft Picks'!$G$3:$G$1149,
      ('Draft Picks'!$B$3:$B$1149=$B3)*
      ('Draft Picks'!$E$3:$E$1149=D$2)*
      ('Draft Picks'!$C$3:$C$1149=1)*
      ('Draft Picks'!$G$3:$G$1149<>"")
    )
  ),
  ""
)
```

This aggregates all picks for a given team/year/round into a semicolon-separated list.

### Sheets that Draft Picks references

**None** — this sheet has no cross-sheet lookups. It's a standalone data entry table.

---

## 6. Key Formulas / Logic Patterns

### Column G: Short Hand formula

Every data row (3+) has a LET formula computing a simplified shorthand:

```
=_xlfn.LET(
  _xlpm.team, B3,
  _xlpm.yr, E3,
  _xlpm.txt, F3,
  _xlpm.isMF, ISNUMBER(SEARCH(" MF [", _xlpm.txt)),
  _xlpm.mfPart, IF(_xlpm.isMF, _xlfn.TEXTAFTER(_xlpm.txt, "MF "), ""),
  _xlpm.pairExists, IF(
    _xlpm.isMF,
    AND(
      COUNTIFS($B$3:$B$1149, _xlpm.team, $E$3:$E$1149, _xlpm.yr, $F$3:$F$1149, "1st MF "&_xlpm.mfPart) > 0,
      COUNTIFS($B$3:$B$1149, _xlpm.team, $E$3:$E$1149, _xlpm.yr, $F$3:$F$1149, "2nd MF "&_xlpm.mfPart) > 0
    ),
    FALSE
  ),
  _xlpm.result, IF(
    _xlpm.pairExists,
    IF(LEFT(_xlpm.txt, 1) = "1", "2 MF "&_xlpm.mfPart, ""),
    _xlpm.txt
  ),
  _xlpm.result
)
```

**Logic:**
1. Check if pick details contain " MF [" (Most Favorable pool)
2. If team has BOTH "1st MF [...]" and "2nd MF [...]" for same year/pool, collapse to "2 MF [...]"
3. Otherwise, pass through the original Pick Details text

This deduplicates paired MF entries for cleaner display in `pick_database.json`.

### Score Column (D)

Scores appear to be a pick valuation metric. Examples:
- `10` — high-value picks (top lottery-likely)
- `5` — mid-value
- `1.25` — standard own pick
- `0.3-0.5` — conditional/unlikely picks

Exact scoring methodology is not documented in formulas (likely entered manually or imported).

---

## 7. Mapping to Our Postgres Model

### Current table

`pcms.draft_picks` exists but may have a simpler schema than what Sean tracks.

### Required fields to match Sean's sheet

| Sean Column | Field Needed |
|-------------|--------------|
| Team (B) | `team_code` |
| Round (C) | `round` |
| Score (D) | `pick_value_score` (new?) |
| Year (E) | `draft_year` |
| Pick Details (F) | `ownership_description` / parse into structured fields |

### Parsing Pick Details

The notation should ideally be parsed into structured columns:
- `original_owner` — whose pick it originally was
- `current_owner` — team that controls it
- `protection_low` / `protection_high` — e.g., p. 1-8 → low=1, high=8
- `swap_type` — `MF` / `LF` / `NONE`
- `swap_pool` — array of teams in swap

This would require a dedicated parser for Sean's DSL.

---

## 8. Open Questions / TODO

- [ ] **Score methodology**: How is column D calculated? Manual entry or imported?
- [ ] **Historical picks**: Does Sean track picks that already conveyed/rolled over?
- [ ] **Parser for Pick Details DSL**: Build a Postgres function to parse `MF [Own,PHX]` etc.
- [ ] **Validation against PCMS**: Compare Sean's data to `pcms.draft_picks` for discrepancies
- [ ] **Conditional chains**: Some picks have complex multi-year conditions (e.g., "if no 1st by '26") — how to model these?

---

## 9. Sample Data

### Row 3 (Round 1, WAS 2026)
```json
{
  "B": "WAS",
  "C": "1",
  "D": "10",
  "E": "2026",
  "F": "Own to NYK (p. 1-8) or MF [Own,PHX]",
  "G": "<formula>"
}
```

### Row 222 (Round 2, BOS 2026)
```json
{
  "B": "BOS",
  "C": "2",
  "D": "0.35",
  "E": "2026",
  "F": "MF [NYK,MIN,NOP,POR]",
  "G": "<formula>"
}
```

### Year distribution
| Year | Pick Entries |
|------|--------------|
| 2026 | 95 |
| 2027 | 99 |
| 2028 | 86 |
| 2029 | 89 |
| 2030 | 81 |
| 2031 | 76 |
| 2032 | 66 |
