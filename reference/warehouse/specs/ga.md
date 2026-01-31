# GA (General Assistant / G-League Affiliate) Spec

**Source:** `reference/warehouse/ga.json`  
**Rows:** 80

---

## 1. Purpose

`GA` is a **team-level Salary Book / cap sheet** view nearly identical to `team.json`.

Given a selected team and base year, it:

- Lists the team's roster from `Y` and shows multi-year salaries (2025–2030)
- Computes salary as **% of cap** for each year
- Shows **Luxury Tax** and **Apron** salary columns
- Computes roster-fill charges (rookie mins / vet mins) to reach 12/14 players
- Computes team totals vs **Minimum / Cap / Tax / Apron 1 / Apron 2** thresholds
- Calculates **luxury tax payments** via `Tax Array`
- Shows the team's **draft pick assets** via `Pick Database`
- Includes "depth chart" labels and two contract calculator blocks

This sheet is functionally a variant/copy of `team.json`, possibly used as a secondary "general assistant" scratch sheet for scenario exploration. The snapshot shows `POR` selected.

---

## 2. Key Inputs / Controls

Top-row selectors (row 1):

| Cell | Meaning | Example |
|---|---|---|
| `D1` | Team code | `POR` |
| `E1` | Base year | `2025` |
| `F1` | Anchor date | `2026-02-02 00:00:00` |
| `H1` | Days remaining | `=DATE(2026,4,12)-F1+1` |
| `I1` | "Repeater in '25:" label | — |
| `J1` | Repeater in '25 | hard-coded IF chain by team |
| `L1` | "Repeater in '26:" label | — |
| `N1` | Repeater in '26 | hard-coded IF chain by team |

Repeater formula (`J1`):
```excel
=IF($D$1="POR","No",
IF($D$1="BOS","Yes",
IF($D$1="PHX","Yes",
IF($D$1="DEN","Yes",
IF($D$1="GSW","Yes",
IF($D$1="LAL","Yes",
IF($D$1="MIL","Yes",
IF($D$1="LAC","Yes","No"))))))))
```

Contract calculator inputs (row 3–4):
- `AH3` → contract total (e.g., `150000000`)
- `AH4` → raise % (e.g., `0.08`)
- `AO3` → alternative start salary (formula `=1.4*E25`)
- `AO4` → raise %

---

## 3. Layout / Zones

| Rows | Purpose |
|------|---------|
| 1 | Team / year selectors, repeater flags |
| 2 | Section headers: "Player Contracts", "Luxury Tax", "Apron", "Depth Chart", "Contract Calculator" |
| 3 | Column headers: "#", "Player", year labels (2025–2030), "TK" (trade kicker) |
| 4–43 | Player roster rows (pulled from `Y`) |
| 44 | Roster count |
| 45 | (+) Rookie Mins — cap holds to fill to 12 |
| 46 | (+) Vet Mins — cap holds to fill to 14 |
| 47 | Dead Money row |
| 48 | Sum totals for Tax/Apron columns |
| 49 | Team Salary (actual cap salary sum) |
| 50 | Team Salary (fill to 14) |
| 51 | Minimum Level (from SystemValues) |
| 52 | +/- Minimum |
| 53 | Cap Level (from SystemValues) |
| 54 | Cap Space |
| 55 | Tax Level (from SystemValues) |
| 56 | +/- Tax |
| 57 | Tax Payment (computed from `Tax Array`) |
| 58 | Tax Refund |
| 59 | Apron 1 Level |
| 60 | +/- Apron 1 |
| 61 | Apron 2 Level |
| 62 | +/- Apron 2 |
| 63 | Net Cost |
| 64 | Cost Savings |
| 65 | Baseline Cost (input) |
| 67–70 | Draft picks (1st/2nd round for 2026–2028) |
| W-AA cols | Depth chart labels (5 columns of player names) |
| AC-AO cols | Contract calculator blocks |

---

## 4. Key Outputs

### A) Player roster grid (rows 4–43)

- Column `A` is a dynamic list of players filtered from `Y` by team and sorted by salary.
- Column `D` mirrors player display name (allows manual override).
- Salary columns `E,G,I,K,M,O` = 2025–2030 cap salaries.
- % of cap columns `F,H,J,L,N,P` divide salary by cap level from row 53.
- Column `Q` = trade kicker (TK).
- Columns `R,S` = Luxury Tax / Apron for current year.
- Columns `T,U` = Luxury Tax / Apron for next year.

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

Salary lookup formula (cell `E4`):
```excel
=IFERROR(
  _xlfn.LET(
    _xlpm.r, MATCH(D4, Y!$B:$B, 0),
    _xlpm.c, MATCH($E$3, Y!$D$2:$J$2, 0),
    _xlpm.v, INDEX(Y!$D:$J, _xlpm.r, _xlpm.c),
    IF(_xlpm.v="-", 0, _xlpm.v)
  ),
0)
```

### B) Roster-fill charges (rows 44–46)

Rookie Min formula (row 45):
```excel
=IF(
  E44>=12,
  0,
  IFERROR(
    _xlfn.LET(
      _xlpm.r, MATCH("Rookie Min "&$E$3, Y!$B:$B, 0),
      _xlpm.c, MATCH($E$3, Y!$D$2:$J$2, 0),
      _xlpm.v, INDEX(Y!$D:$J, _xlpm.r, _xlpm.c),
      IF(_xlpm.v="-",0,_xlpm.v)
    ),
    0
  ) * (12-E44)
)*(H1/174)
```

Vet Min formula (row 46) uses similar logic but fills to 14.

### C) Team totals / thresholds (rows 49–62)

Each threshold is fetched from SystemValues:
```excel
=_xlfn.XLOOKUP(E3,SystemValues[[#All],[Season]],SystemValues[[#All],[Salary Cap]])
```

### D) Tax Payment (row 57)

Uses repeater status (`J1`) to select which Tax Array columns to use:
```excel
=IF(
  $J$1="Yes",
  SUMPRODUCT(
    (E56>'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$K$4:$K$200=$E$3) *
    (E56 - 'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$O$4:$O$200)
  ),
  SUMPRODUCT(
    (E56>'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$E$4:$E$200=$E$3) *
    (E56 - 'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$I$4:$I$200)
  )
)
```

### E) Draft picks (rows 67–70)

```excel
=INDEX('Pick Database'!$D$3:$D$32, MATCH($D$1, 'Pick Database'!$B$3:$B$32, 0))
```

---

## 5. Cross-Sheet Dependencies

### References FROM GA

| Sheet | Purpose |
|-------|---------|
| `Y` | Player salaries, team filtering, roster data |
| `SystemValues` | CBA constants (Cap, Tax, Apron 1, Apron 2, Minimum Level) |
| `Tax Array` | Luxury tax bracket computations |
| `Pick Database` | Draft pick ownership lookup |

### References TO GA

No other sheets reference `GA`.

---

## 6. Mapping to Our Postgres Model

| Sean Concept | Our Table(s) |
|--------------|--------------|
| Player salaries by year | `pcms.salary_book_warehouse` |
| CBA constants | `pcms.league_system_values` |
| Draft picks | `pcms.draft_picks_warehouse` |
| Luxury tax calculations | Not modeled (would need `Tax Array` spec + function) |
| Repeater status | Not modeled |

---

## 7. Key Differences from `team.json`

Both sheets are nearly identical in structure. Possible differences:

- `GA` may be a secondary scratch/analysis sheet (the "General Assistant" copy)
- Snapshot shows `POR` vs `MIL` in `team.json`
- Minor formula variations but same overall approach

---

## 8. Open Questions / TODO

- [ ] Clarify naming: "GA" = G-League Affiliate? General Assistant? Or something else?
- [ ] Consider consolidating logic with `team.json` spec since they're nearly identical
- [ ] Model repeater status in DB
- [ ] Add luxury tax payment function (see `Tax Array` spec)
