# Dynamic Contracts Spec

**Source:** `reference/warehouse/dynamic_contracts.json`  
**Rows:** 1316 (header rows 1-2 + ~1127 contract-year rows + pivot zones)

---

## 1. Purpose

**Dynamic Contracts** is the raw contract data layer. Each row represents one **contract + salary year** combination with:

- Cap / Tax / Apron salary amounts
- Option type (Player Opt, Team Opt, etc.)
- Protection status (looked up from Contract Protections)

The sheet also includes **pivoted views** that transform the long-form data into wide-form summaries (one row per player) and **team aggregation zones** for quick Cap/Tax/Apron totals by team and year.

---

## 2. Key Inputs / Controls

| Cell | Value | Purpose |
|------|-------|---------|
| **BJ1** | `POR` | Team selector for "Check" zone (filters player list for a specific team) |

This appears to be a QA/check feature — filter to a team and see their players with salaries.

---

## 3. Key Outputs

### Zone A–P: Raw Contract-Year Data (rows 3–1127+)

One row per `(contract_id, version_number, player_id, salary_year)`:

| Col | Header | Notes |
|-----|--------|-------|
| A | `Contract ID` | |
| B | `Version Number` | |
| C | `Player ID` | NBA person_id |
| D | `Roster First Name` | |
| E | `Roster Last Name` | |
| F | `Signing Date` | datetime string |
| G | `Current Team` | 3-letter code (uses PCMS codes: BKN, SAS) |
| H | `Agent` | Format: "Last, First" |
| I | `DOB` | |
| J | `Salary Year` | 2025–2030 |
| K | `Cap Salary` | contract_cap_salary |
| L | `Tax Salary` | contract_tax_salary |
| M | `Apron Salary` | contract_tax_apron_salary |
| N | `Option` | Raw option string from source data |
| O | (Formula) | Lookup to Contract Protections sheet → guarantee status |
| P | `OPTION` | Derived short code: PO, TO, PC, NG, `-` |

### Zone U–BC: Pivoted Player View (rows 3+)

One row per unique player, salaries pivoted by year:

| Col | Header | Notes |
|-----|--------|-------|
| U | `PlayerID` | Looked up from V→R→S |
| V | `Name` | `=UNIQUE(R:R)` — "Last, First" format |
| W | `Team` | Mapped codes (BKN→BRK, SAS→SAN) |
| X–AD | `2025`–`2031` | Cap salary by year |
| AE–AK | `2025`–`2031` | Option code by year |
| AL–AR | `2025`–`2031` | Tax salary by year |
| AS–AY | `2025`–`2031` | Apron salary by year |
| AZ | `DOB` | |
| BA | `AGE` | `=(TODAY()-AZ)/365.25` |
| BB | `AGENT` | Agent last name only |
| BC | `TK` | Trade kicker (XLOOKUP to Y!$AI:$AI) |

### Zone BI–BT: "Check" View (team filter)

| Col | Header | Notes |
|-----|--------|-------|
| BI | `Player` | `=FILTER(T:T, W:W=BJ1)` — players for team in BJ1 |
| BJ–BO | `2025`–`2030` | Cap salary by year (XLOOKUP into pivot) |
| BP | `TK` | Trade kicker |
| BQ | `Age` | |
| BR | `Agent` | |
| BS | `Tax 2025` | |
| BT | `Apron 2025` | |

### Zone BX–CW: Team Totals (rows 3–32)

30 teams, one per row:

| Col Range | Header | Notes |
|-----------|--------|-------|
| BX | `Teams` | 3-letter team code (BRK format) |
| BY–CE | `2025`–`2031` | `=SUMIF(W:W, BX, X:X)` — Cap total by year |
| CG | `Teams` | (repeat) |
| CH–CN | `2025`–`2031` | Tax total (formulas present but may be incomplete) |
| CP | `Teams` | (repeat) |
| CQ–CW | `2025`–`2031` | Apron total |

---

## 4. Layout / Zones

```
Row 1:   Section headers (Copy & Paste | ... | Salary Cap | Options | Luxury Tax | Apron | Check | POR | Cap | Tax | Apron)
Row 2:   Column headers
Rows 3+: Contract-year data (A–P) + Pivoted player view (U–BC) + Check zone (BI–BT) + Team totals (BX–CW)
```

Key observation: **Same rows serve multiple purposes** — the long-form contract data in A–P, the pivoted player view in U–BC, and the team totals in BX–CW are all on the same row range but represent different logical tables.

---

## 5. Cross-Sheet Dependencies

### Dynamic Contracts references:

| Sheet | Usage | Example Formula |
|-------|-------|-----------------|
| `Contract Protections` | Lookup guarantee status by (player_id, salary_year) | `=INDEX('Contract Protections'!F:F, MATCH(1, ('Contract Protections'!C:C=C3) * ('Contract Protections'!E:E=J3), 0))` |
| `Y` | Trade kicker lookup by player name | `=XLOOKUP(V3, Y!$B:$B, Y!$AI:$AI)` |

**Reference counts:**
- `'Contract Protections'!` — 3702 occurrences
- `Y!` — 1004 occurrences

### Sheets that reference Dynamic Contracts:

Based on file inspection, no other sheets appear to directly reference `'Dynamic Contracts'!`. This sheet is **self-contained** — it transforms raw data into pivot views, which other sheets may replicate via Y or their own logic.

---

## 6. Key Formulas / Logic

### Option code derivation (col P):

```excel
=IFERROR(
  IF(OR(N3="Player Opt", N3="Early Termination Option"), "PO",
  IF(OR(O3="Partial", O3="Part./Cond"), "PC",
  IF(OR(O3="None", O3="None/Cond"), "NG",
  IF(N3="Team Opt", "TO",
  IF(O3="Full", "-",
  ""))))),
"NG")
```

Logic:
1. Player Option / ETO → `PO`
2. Partial or Part./Cond guarantee → `PC`
3. None or None/Cond guarantee → `NG`
4. Team Option → `TO`
5. Fully guaranteed → `-`
6. Default fallback → `NG`

### Name formatting (col R):

```excel
=IF(OR(RIGHT(E3, 3) = "Jr.", RIGHT(E3, 2) = "II", RIGHT(E3, 3) = "III", RIGHT(E3, 2) = "IV"),
    LEFT(E3, FIND(" ", E3) - 1) & ", " & D3,
    E3 & ", " & D3)
```

Handles suffixes (Jr., II, III, IV) — e.g., "Tim Hardaway Jr." → "Hardaway, Tim"

### Team code remapping (col W):

```excel
=IFERROR(
  IF(INDEX(G:G, MATCH(U3, C:C, 0)) = "BKN", "BRK",
  IF(INDEX(G:G, MATCH(U3, C:C, 0)) = "SAS", "SAN",
  INDEX(G:G, MATCH(U3, C:C, 0)))),
"-")
```

Remaps: `BKN` → `BRK`, `SAS` → `SAN` (Y-style team codes)

### Cap salary pivot (cols X–AD):

```excel
=IFERROR(INDEX($K$2:$K$1299, MATCH(1, ($C$2:$C$1299=$U3) * ($J$2:$J$1299=X$2), 0)), "-")
```

Looks up cap salary for player U3 in year X$2 (2025).

### Team total (cols BY–CE):

```excel
=SUMIF(W:W, BX3, X:X)
```

Sums cap salary column X for all players where team = BX3.

---

## 7. Data Values

### Option values (col N — raw source):
| Value | Meaning |
|-------|---------|
| (blank) | No option |
| `Player Opt` | Player option |
| `Player Opt (Team Fav)` | Player option with team-favorable terms |
| `Team Opt` | Team option |

### Option codes (col P — derived):
| Code | Meaning |
|------|---------|
| `-` | Fully guaranteed, no option |
| `PO` | Player option |
| `TO` | Team option |
| `PC` | Partially guaranteed (partial/conditional) |
| `NG` | Non-guaranteed |

### Team codes (col G vs col W):
- Col G: PCMS native codes (`BKN`, `SAS`)
- Col W: Y-warehouse codes (`BRK`, `SAN`)

---

## 8. Mapping to Postgres

| Dynamic Contracts Column | PCMS Table | Column |
|--------------------------|------------|--------|
| A (Contract ID) | `pcms.contracts` | `contract_id` |
| B (Version Number) | `pcms.contract_versions` | `version_number` |
| C (Player ID) | `pcms.people` | `person_id` |
| D, E (First, Last) | `pcms.people` | `first_name`, `last_name` |
| F (Signing Date) | `pcms.contracts` | `signing_date` |
| G (Current Team) | `pcms.contracts` / `salary_book_warehouse` | `team_code` |
| H (Agent) | `pcms.agents` | `last_name, first_name` |
| I (DOB) | `pcms.people` | `dob` |
| J (Salary Year) | `pcms.salaries` | `salary_year` |
| K (Cap Salary) | `pcms.salaries` | `contract_cap_salary` |
| L (Tax Salary) | `pcms.salaries` | `contract_tax_salary` |
| M (Apron Salary) | `pcms.salaries` | `contract_tax_apron_salary` |
| N (Option) | `pcms.salaries` | `option_lk` |
| O (Protection lookup) | `pcms.contract_protections` | `protection_coverage_lk`, `protection_amount`, `effective_protection_amount` |
| V–BC (pivot view) | `pcms.salary_book_warehouse` | Wide-form player view |
| BY–CW (team totals) | `pcms.team_salary_warehouse` | Team totals by year |

### Relationship to other caches:

- **Pivoted player view (U–BC)** ≈ `pcms.salary_book_warehouse`
- **Team totals (BX–CW)** ≈ `pcms.team_salary_warehouse`
- **Raw contract-year data (A–P)** ≈ `pcms.salaries` joined with `pcms.contracts`, `pcms.people`

---

## 9. Open Questions

1. **What's the source of the raw data (A–P)?** — Appears to be copy-pasted from a PCMS export (note row 1: "Copy & Paste").

2. **Why are team totals incomplete in Tax/Apron zones?** — Only Cap totals (BY–CE) have formulas populated in the sample; Tax (CH–CN) and Apron (CQ–CW) columns are null in some rows.

3. **Is the "Check" zone (BI–BT) actively used?** — Seems like a QA tool. The team selector in BJ1 filters players, but the columns BS–BT only show Tax/Apron for 2025.

4. **Why 2031 in some columns?** — The raw data only has 2025–2030, but the pivot headers include 2031. Likely for future-proofing.

---

## 10. Summary

Dynamic Contracts is the **data transformation hub**:

1. **Raw input**: Contract-year rows (A–P) from PCMS export
2. **Pivot**: Wide-form player view (U–BC) with salaries/options by year
3. **Aggregation**: Team totals by year (BX–CW)

It references:
- `Contract Protections` for guarantee status
- `Y` for trade kicker values

Our Postgres equivalents:
- Raw data → `pcms.salaries` + `pcms.contracts` + `pcms.people`
- Pivot view → `pcms.salary_book_warehouse`
- Team totals → `pcms.team_salary_warehouse`

This sheet is largely **internal scaffolding** — it transforms raw data that feeds the Y warehouse, which is then used by presentation sheets.
