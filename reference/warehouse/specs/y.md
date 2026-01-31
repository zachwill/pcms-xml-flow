# Y Warehouse Spec

**Source:** `reference/warehouse/y.json`  
**Rows:** 1457 (1 header + ~610 player rows + zones for Trade Bonus/Minimums/Rookie Scale)

---

## 1. Purpose

The **Y Warehouse** is the central salary matrix for the workbook. It provides:

- **One row per player/entry** with multi-year cap/tax/apron amounts (2025–2031)
- **Option indicators** by year (TO, PO, NG, QO, CH, etc.)
- **Player metadata** (DOB, Age, Agent, Trade Kicker, Tier, Position)
- **Reference rows** for Rookie Scale Amounts, Minimums, and Trade Bonus lookups

Other sheets (playground, team, machine, the_matrix, high_low, etc.) lookup into Y to get salaries.

---

## 2. Key Inputs / Controls

**No user inputs** — Y is a read-only warehouse. Data populates from:

- Literal values (cap/tax/apron salary amounts) — presumably from PCMS export
- Lookup formulas to `Trade Bonus Amounts` sheet (rows 615+)
- Lookup formulas to `RSC` (Rookie Scale) and `Minimums` named tables (rows 740+)

---

## 3. Key Outputs

| Zone | Rows | Description |
|------|------|-------------|
| **Headers** | 1–2 | Section titles and column headers |
| **Player data** | 3–612 | Active players with contract salaries |
| **Trade Bonus** | 614–740 | Trade bonus add-ons pulled via XLOOKUP from `'Trade Bonus Amounts'!` |
| **Minimums** | ~740 | Minimum salary lookup by YOS |
| **Rookie Scale** | 741–1457 | Draft pick → rookie scale salary for each season |

---

## 4. Layout / Column Map

### Row 1: Section Headers
| Col | Value |
|-----|-------|
| A | `Contract Details` |
| D | `Salary Cap` |
| K | `Options` |
| R | `Luxury Tax` |
| Y | `Apron` |

### Row 2: Column Headers
| Col | Header | Notes |
|-----|--------|-------|
| A | `PlayerID` | NBA person_id |
| B | `Name` | Format: "Last, First" |
| C | `Team` | 3-letter team code (or `-` if unsigned) |
| D–J | `2025`–`2031` | Cap salary by year (D=2025, E=2026, …) |
| K–Q | `2025`–`2031` | Option type per year (TO, PO, NG, QO, CH, `-`) |
| R–X | `2025`–`2031` | Tax salary (mirrors cap in most cases) |
| Y–AE | `2025`–`2031` | Apron salary |
| AF | `DOB` | Date of birth (datetime string) |
| AG | `Age` | Formula: `=(TODAY()-AF)/365.25` |
| AH | `Agent` | Agent last name |
| AI | `TK` | Trade kicker (e.g., `0.15`, `Used`, `1/18`, `1-YB`, `-`) |
| AJ | `Tier` | Contract tier (1–10, or `-`) |
| AK | `Top` | Ranking formula within tier |
| AL | `Bottom` | Ranking formula within tier |
| AM | `SB` | Salary Band display: `=AJ&" | "&AK&"-"&AL` |
| AN | `Pos` | Position (PG, SG, SF, PF, C) |

---

## 5. Cross-Sheet Dependencies

### Y references:
| Sheet | Usage | Example |
|-------|-------|---------|
| `Trade Bonus Amounts` | XLOOKUP to pull trade bonus salary add-ons | `=_xlfn.XLOOKUP(B615, 'Trade Bonus Amounts'!$B:$B, 'Trade Bonus Amounts'!U:U, "-")` |
| `RSC` (named table) | Rookie scale amounts by pick + season | `=IFERROR(INDEX(RSC[Year 1], MATCH(1, (RSC[Pick]=B743)*(RSC[Season]=$D$2), 0)),"-")` |
| `Minimums` (named table) | Minimum salary by YOS + season | `=IFERROR(INDEX(Minimums[Year 1], MATCH(1, (Minimums[Minimums]=$B740)*(Minimums[Season]=$F$2), 0)),"-")` |

### Sheets that reference Y:

| Sheet | Reference Count | Pattern |
|-------|-----------------|---------|
| `high_low.json` | 4051 | Salary projections per player |
| `dynamic_contracts.json` | 502 | Contract detail cross-ref |
| `the_matrix.json` | 500 | Extension calculator |
| `ga.json` | 371 | G-League / two-way |
| `2025.json` | 369 | Season snapshot |
| `team.json` | 276 | Team roster view |
| `playground.json` | 253 | Team salary book |
| `por.json` | 253 | Portland snapshot |
| `team_summary.json` | 240 | Team dashboard |
| `finance.json` | 225 | Team financials |
| `machine.json` | 95 | Trade machine |
| `buyout_calculator.json` | 4 | Buyout scenarios |

**Typical lookup pattern** (from `playground.json`):

```excel
=_xlfn.LET(
  _xlpm.team,    $D$1,
  _xlpm.yr,      E1,
  _xlpm.hdrs,    Y!$D$2:$P$2,
  _xlpm.tbl,     Y!$B$3:$P$1137,
  _xlpm.colIx,   MATCH(_xlpm.yr, _xlpm.hdrs, 0) + 2,
  _xlpm.teamRows,_xlfn._xlws.FILTER(_xlpm.tbl, INDEX(_xlpm.tbl,,2)=_xlpm.team),
  _xlpm.names,   INDEX(_xlpm.teamRows,,1),
  _xlpm.sal,     INDEX(_xlpm.teamRows,,_xlpm.colIx),
  _xlpm.key,     IFERROR(--_xlpm.sal, -10000000000),
  _xlfn.SORTBY(_xlpm.names, _xlpm.key, -1)
)
```

Filters Y data by team, sorts by salary descending.

---

## 6. Key Formulas / Logic

### Age calculation (all player rows):
```excel
AG3: =(TODAY()-AF3)/365.25
```
Returns decimal years.

### Tier ranking:
```excel
AK3: =IF(AJ3="","",COUNTIF($AJ:$AJ,"<"&AJ3)+1)
AL3: =COUNTIF($AJ:$AJ, "<=" & AJ3)
AM3: =AJ3&" | "&AK3&"-"&AL3
```
Computes salary-band style rank within tier.

### Tax/Apron columns (most player rows):
```excel
R3: =D3    (tax = cap for most contracts)
Y3: =D3    (apron = cap for most contracts)
```

### Trade Bonus zone (rows 615+):
```excel
B615: ='Trade Bonus Amounts'!B17
D615: =_xlfn.XLOOKUP(B615, 'Trade Bonus Amounts'!$B:$B, 'Trade Bonus Amounts'!U:U, "-")
```
Pulls bonus amounts per year for players with trade kickers.

### Rookie Scale zone (rows 743+):
```excel
B743: =INDEX(RSC[Pick], 1)
D743: =IFERROR(INDEX(RSC[Year 1], MATCH(1, (RSC[Pick]=B743)*(RSC[Season]=$D$2), 0)),"-")
```
Looks up Year 1 salary for pick 1 in 2025 season.

---

## 7. Data Values

### Option codes (K–Q columns):
| Code | Meaning |
|------|---------|
| `-` | No option / not applicable |
| `TO` | Team Option |
| `PO` | Player Option |
| `NG` | Non-Guaranteed |
| `QO` | Qualifying Offer |
| `CH` | Club Holds (rookie scale context) |

### Trade Kicker values (AI column):
| Value | Meaning |
|-------|---------|
| `-` | No trade kicker |
| `0.15`, `0.075`, etc. | Trade kicker percentage |
| `Used` | Trade kicker already exercised |
| `1/18`, `2/26` | Prorated kicker (e.g., 1 year of 18 remaining) |
| `1-YB` | One-year bonus variant |

### Tier values (AJ column):
| Value | Meaning |
|-------|---------|
| `1` | Highest salary tier (supermax) |
| `2`–`10` | Descending tiers |
| `-` | No tier (unsigned / G-League) |

---

## 8. Mapping to Postgres

| Y Column | PCMS Table | Column |
|----------|------------|--------|
| A (PlayerID) | `pcms.people` | `person_id` |
| B (Name) | `pcms.people` | `display_name` (we use "First Last") |
| C (Team) | `pcms.contracts` / `salary_book_warehouse` | `team_code` |
| D–J (Cap) | `pcms.salary_book_warehouse` | `cap_2025`–`cap_2030` |
| K–Q (Options) | `pcms.salary_book_warehouse` | `option_2025`–`option_2030` |
| R–X (Tax) | `pcms.salary_book_warehouse` | `tax_2025`–`tax_2030` |
| Y–AE (Apron) | `pcms.salary_book_warehouse` | `apron_2025`–`apron_2030` |
| AF (DOB) | `pcms.people` | `dob` |
| AG (Age) | `pcms.salary_book_warehouse` | `age` (decimal) |
| AH (Agent) | `pcms.agents` + `salary_book_warehouse` | `agent_name` |
| AI (TK) | `pcms.contract_versions` | `trade_bonus_percent` → `trade_kicker_display` |
| AN (Pos) | `pcms.people` | `position_lk` |

### Coverage gaps:

- **Tier (AJ)**: Not in PCMS — would need derived logic based on salary tier buckets.
- **Rookie Scale zone (rows 740+)**: We have `pcms.rookie_scale_amounts` but not pivoted into `salary_book_warehouse`.
- **Trade Bonus add-on rows (615–740)**: These are computed kicker amounts — our warehouse includes kicker in `trade_kicker_display` but not as separate rows.

---

## 9. Open Questions

1. **How is Y populated?** — The player rows (3–612) appear to be static values, not formulas. This suggests Sean exports from PCMS/another source and pastes values.

2. **Year range**: Y covers 2025–2031 (7 years). Our `salary_book_warehouse` currently covers 2025–2030 (6 years). May need to extend.

3. **Tier logic**: What defines tier 1–10? Likely based on salary % of cap or max contract eligibility. Need to reverse-engineer if we want to replicate.

4. **Option code "CH"**: Appears on rookie scale rows for years 3–4 (club holds). Verify this maps to our `TEAM` option type.

---

## 10. Summary

Y is the **central salary lookup table** for the workbook. It's the source-of-truth for:

- Player cap/tax/apron amounts by year
- Option types per year
- Player metadata (age, agent, trade kicker, position)

Our `pcms.salary_book_warehouse` is the direct analog — same structure, same purpose. Key differences:

- Sean's Y includes Tier ranking (we don't)
- Sean's Y includes Trade Bonus add-on rows (we embed in the contract)
- Sean's Y includes Rookie Scale lookup rows (we have a separate table)

For Salary Book / Playground features, our warehouse should be drop-in compatible.
