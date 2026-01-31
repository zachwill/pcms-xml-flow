# Team Spec

**Source:** `reference/warehouse/team.json`  
**Rows:** 90

---

## 1. Purpose

`Team` is a **single-team Salary Book / cap sheet** view.

Given a selected team and base year, it:

- Lists the team’s roster (from `Y`) and shows multi-year salaries (2025–2030)
- Computes salary as **% of cap** for each year
- Computes roster-fill charges (rookie mins / vet mins) to reach 12/14 players
- Computes team totals vs **Minimum / Cap / Tax / Apron 1 / Apron 2** thresholds
- Estimates **luxury tax payments** using `Tax Array`
- Shows the team’s **draft pick assets** via `Pick Database`
- Includes mini “depth chart” labels and two contract calculator blocks

This sheet overlaps heavily with `playground.json` and `finance.json`; the main difference is layout and which scenario/tool blocks are present.

---

## 2. Key Inputs / Controls

Top-row selectors:

| Cell | Meaning | Example |
|---|---|---|
| `D1` | Team code | `MIL` |
| `E1` | Base year | `2025` |
| `F1` | Today | `=TODAY()` |
| `H1` | Days remaining | `=DATE(2026,4,12)-F1+1` |
| `J1` | Repeater in '25 | hard-coded IF chain by team |
| `N1` | Repeater in '26 | hard-coded IF chain by team |

Example repeater logic (`J1`):
```excel
=IF($D$1="POR","No",
IF($D$1="BOS","Yes",
IF($D$1="PHX","Yes", ... )))
```

Contract calculator inputs:
- `AD3` (contract total)
- `AD4` (raise %)
- `AK3` (start salary)
- `AK4` (raise %)

---

## 3. Key Outputs

### A) Player roster grid (rows 4–46)

- Column `A` is a dynamic list of players filtered from `Y` by team and sorted by salary.
- Column `D` mirrors player display name.
- Salary columns `E,G,I,K,M,O` represent 2025–2030.
- % of cap columns `F,H,J,L,N,P` divide each salary by the cap level for that year (row 56).

Roster formula (cell `A4`):
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

### B) Totals / thresholds block (rows 47–66)

Key rows:
- `E52` = Team Salary (cap salaries + dead money)
- `E53` = Team Salary (fill to 14)
- `E56` = Cap Level (from `SystemValues`)
- `E58` = Tax Level (from `SystemValues`)
- `E60` = Tax Payment (SUMPRODUCT into `Tax Array`, repeater vs non-repeater)
- `E62` / `E64` = Apron 1 / Apron 2 levels

Example cap lookup (`E56`):
```excel
=_xlfn.XLOOKUP(E3,SystemValues[[#All],[Season]],SystemValues[[#All],[Salary Cap]])
```

Example tax payment (`E60`):
```excel
=IF(
  $J$1="Yes",
  SUMPRODUCT(
    (E59>'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$K$4:$K$200=$E$3) *
    (E59 - 'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$O$4:$O$200)
  ),
  SUMPRODUCT(
    (E59>'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$E$4:$E$200=$E$3) *
    (E59 - 'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$I$4:$I$200)
  )
)
```

### C) Draft pick ownership (rows 70–77)

Two columns:
- 1st round (col `E`)
- 2nd round (col `K`)

Example (row 71 for 2026):
```excel
E71: =_xlfn.XLOOKUP($D$1,'Pick Database'!$B$3:$B$33,'Pick Database'!$D$3:$D$33)
K71: =_xlfn.XLOOKUP($D$1,'Pick Database'!$B$33:$B$63,'Pick Database'!$D$33:$D$63)
```

---

## 4. Layout / Zones

- Row 1: Team/year selectors + repeater flags
- Rows 4–46: Player roster list + salaries + % of cap
- Rows 47–66: Roster counts, mins fill, dead money, totals, thresholds, tax payment
- Rows 70–77: Draft pick ownership summary
- Rows 2–3 and Y–AK columns: Contract calculator blocks (total-based and start-based)

---

## 5. Cross-Sheet Dependencies

### Team reads from:

| Sheet | Why |
|---|---|
| `Y` | roster + salary grid via `MATCH/INDEX` and `FILTER/SORTBY` |
| `SystemValues` | cap/tax/apron/minimum thresholds via `XLOOKUP` |
| `Tax Array` | tax payment bracket calc via `SUMPRODUCT` |
| `Pick Database` | draft pick ownership via `XLOOKUP` |

### Sheets that reference Team:

No direct `'Team'!` references were found in other JSON exports; this appears to be a terminal/presentation sheet.

---

## 6. Mapping to Postgres

| Team sheet concept | Our table/view |
|---|---|
| Player salaries by year | `pcms.salary_book_warehouse` (wide cap/tax/apron columns) |
| Yearly thresholds (cap/tax/aprons/minimum team salary) | `pcms.league_system_values` |
| Dead money | `pcms.dead_money_warehouse` (tool-facing drilldown) |
| Team totals | `pcms.team_salary_warehouse` (tool-facing totals) |
| Draft picks | `pcms.draft_picks_warehouse` (preferred) or `pcms.draft_picks` |
| Tax payment | Not currently a first-class warehouse table; would need a bracket table or a function |

---

## 7. Open Questions / TODO

- [ ] Repeater status is hard-coded to specific teams; for tooling we should derive from tax history (or store in a table).
- [ ] The tax bracket logic depends on `tax_array.json`; we still need a dedicated spec + schema mapping for tax brackets.
- [ ] Dead money is pulled from Y using a "{TEAM} Dead Money" naming convention; confirm that maps 1:1 to our `pcms.dead_money_warehouse` aggregation.
- [ ] There are stray `#REF!` formulas near rows 87–90; determine if these are harmless artifacts.
