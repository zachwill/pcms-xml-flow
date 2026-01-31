# the_matrix.json — "The Matrix" (Multi-Team Trade Scenario Calculator)

**Source file:** `reference/warehouse/the_matrix.json`
**Rows:** 60
**Purpose:** Interactive multi-team trade scenario calculator supporting up to 4 teams with full CBA salary matching validation

---

## 1. Purpose / Why This Sheet Exists

The Matrix is Sean's **trade scenario planning tool**. It allows an analyst to:

1. Select up to **4 teams** participating in a trade
2. Enter players moving between teams (outgoing/incoming)
3. Calculate salary matching under different apron/tax conditions
4. Validate trade legality per CBA rules
5. Model roster count and cap space impact post-trade

This is distinct from `machine.json` which focuses on single-trade mechanics — The Matrix handles **complex multi-team scenarios** with side-by-side team comparison.

---

## 2. Key Inputs / Controls

### Team Selectors (Row 1)
| Cell | Description | Example Value |
|------|-------------|---------------|
| `AK1` | Team 1 code | `"POR"` |
| `AW1` | Team 2 code | `"MIL"` |
| `BI1` | Team 3 code | `"BRK"` |
| `BU1` | Team 4 code | `"PHI"` |

### Mode Selectors (Row 1)
| Cell | Description | Values |
|------|-------------|--------|
| `AM1` | Team 1 apron mode | `"Expanded"` / `"Standard"` |
| `AY1` | Team 2 apron mode | `"Expanded"` / `"Standard"` |
| `BK1` | Team 3 apron mode | `"Expanded"` / `"Standard"` |
| `BW1` | Team 4 apron mode | `"Expanded"` / `"Standard"` |

### Trade Parameters (Rows 3-10)
| Cell | Description |
|------|-------------|
| `AI3` | Season year (`2025`) |
| `AI4` | Season start date (for proration) |
| `AI5` | Date of trade (`=TODAY()`) |
| `AI6` | Outgoing days responsible (calculated from trade date) |
| `AI7` | Incoming days responsible (`=174-AI6`) |
| `AI10` | Day of season for proration |

### Salary Constants (Rows 11-16)
| Cell | Description | Example |
|------|-------------|---------|
| `AI11` | Rookie minimum (prorated) | `=1272870*((174-AI10+1)/174)` |
| `AI12` | Vet minimum (prorated) | `=2296274*((174-AI10+1)/174)` |
| `AI14` | Trade bracket 1 threshold | 8277000 |
| `AI15` | TPE allowance | 8527000 |
| `AI16` | Trade bracket multiplier threshold | 33208000 |

### Player Input Zones (Rows 4-14, each team pair)
- **Outgoing players:** columns AK, AW, BI, BU (Team 1-4)
- **Incoming players:** columns AR, BD, BP, CB
- Players can be typed by name or looked up from roster

---

## 3. Key Outputs

### Team Roster Display (Rows 3-22, columns A-AE)
Four side-by-side roster views showing for each team:
- Column A/I/Q/Y: Player names (auto-populated via FILTER from Y warehouse)
- Cap / Tax / Apron salary lookups (C/D/E, K/L/M, S/T/U, AA/AB/AC)
- Salary Earned / Remaining based on trade date proration

### Trade Buildup Calculations (Rows 3-18)
For each of 4 team pairings:
| Label | Outgoing Col | Incoming Col |
|-------|--------------|--------------|
| Team 1 Out | AL | - |
| Team 1 In | - | AS |
| Team 2 Out | AX | - |
| Team 2 In | - | BE |
| Team 3 Out | BJ | - |
| Team 3 In | - | BQ |
| Team 4 Out | BV | - |
| Team 4 In | - | CC |

### Summary Totals (Row 15)
```
AK15: "Outgoing"  AL15: =SUM(AL4:AL14)  (Cap)  AM15: (Tax)  AN15: (Apron)
AR15: "Incoming"  AS15: =SUM(AS4:AS14)
```

### Roster Adjustments (Rows 17-18)
- Row 17: (+) Rookie Mins — adds minimum salary slots if roster < 12
- Row 18: (+) Vet Mins — adds minimum salary slots if roster < 14

### Trade Validity Check (Rows 50-52)
| Row | Label | Formula Pattern |
|-----|-------|-----------------|
| 50 | Multiplier check | Validates salary matching math works |
| 51 | Apron 1 check | `=IF(AL$1="Apron 1", IF(AT34>0,"No","Yes")...)` |
| 52 | Apron 2 check | Similar logic for Apron 2 |

### Final Verdict (Row 40)
```
AR40: =IF(OR(ISNUMBER(SEARCH("No", AR50)), ...), "Does Not Work", "Trade Works")
```

### Team Cap/Tax Summary (Rows 24-36)
For each team buildup block:
| Row | Label | Meaning |
|-----|-------|---------|
| 24 | Team Salary | Current roster salary |
| 25 | Minimum Level | From SystemValues lookup |
| 26 | +/- Minimum | Over/under minimum floor |
| 27 | Cap Level | From SystemValues |
| 28 | Cap Space | Available space |
| 29 | Tax Level | From SystemValues |
| 30 | +/- Tax | Over/under tax threshold |

---

## 4. Layout / Zones

| Zone | Rows | Columns | Description |
|------|------|---------|-------------|
| Header | 1-2 | All | Team selectors, mode selectors, "Trade Details" label |
| Trade Config | 3-16 | AH-AI | Season, dates, salary constants |
| Roster View 1 | 3-26 | A-G | Team 1 roster with salary breakdown |
| Roster View 2 | 3-26 | I-O | Team 2 roster |
| Roster View 3 | 3-26 | Q-W | Team 3 roster |
| Roster View 4 | 3-26 | Y-AE | Team 4 roster |
| Team Status Lookup | 19-48 | AG-AI | 30-team apron/tax status reference |
| Trade Pair 1 | 3-52 | AK-AU | Team 1↔2 buildup |
| Trade Pair 2 | 3-52 | AW-BG | Team 2↔3 buildup |
| Trade Pair 3 | 3-52 | BI-BS | Team 3↔4 buildup |
| Trade Pair 4 | 3-52 | BU-CE | Team 4↔1 buildup |
| Draft Picks | 28-36 | A-AC | Pick ownership display per team |
| Validity Checks | 50-52 | AR+ | Trade works/doesn't work |

---

## 5. Cross-Sheet Dependencies

### References OUT to other sheets:

| Sheet | Usage | Example Formula |
|-------|-------|-----------------|
| **Y** (y.json) | Player salary lookups | `=INDEX(Y!$D:$J, MATCH(...), ...)` |
| **SystemValues** | CBA constants | `=XLOOKUP($AI$3, SystemValues[[Season]], SystemValues[[Salary Cap]])` |
| **Pick Database** | Draft pick ownership | `=XLOOKUP(A$1,'Pick Database'!$B$4:$B$33,...)` |
| **Tax Array** | Tax calculations | (Referenced but not heavily used here) |

### Roster Population Formula (Row 3, Column A):
```excel
=LET(
  team,    $AK$1,
  yr,      AI3,
  hdrs,    Y!$D$2:$P$2,
  tbl,     Y!$B$3:$P$1137,
  colIx,   MATCH(yr, hdrs, 0) + 2,
  teamRows, FILTER(tbl, INDEX(tbl,,2)=team),
  names,   INDEX(teamRows,,1),
  sal,     INDEX(teamRows,,colIx),
  key,     IFERROR(--sal, -10000000000),
  SORTBY(names, key, -1)
)
```

### Salary Lookup Pattern:
```excel
=IFERROR(
  LET(
    r, MATCH(A3, Y!$B:$B, 0),
    c, MATCH($AI$3, Y!$D$2:$J$2, 0),
    v, INDEX(Y!$D:$J, r, c),
    IF(v="-", 0, v)
  ),
0)
```

---

## 6. Key Formulas / Logic Patterns

### Trade Salary Matching (Expanded Apron Mode) — Row 50
```excel
=IF(
  IF(AM1="Expanded",
    IF(SUM(AL4:AL11) < $AI$14,
      SUM(AL4:AL11)*2 + 250000,
      IF(AND(SUM(AL4:AL11) > $AI$14, SUM(AL4:AL11) < $AI$16),
        SUM(AL4:AL11) + $AI$15,
        IF(SUM(AL4:AL11) > $AI$16,
          SUM(AL4:AL11)*1.25 + 250000,
          SUM(AL4:AL11)
        )
      )
    ),
    IF(AM1="Standard", SUM(AL4:AL11), SUM(AL4:AL11))
  ) > SUM(AS4:AS11),
  "Yes", "No"
)
```

This implements the CBA's tiered trade matching rules:
- Under $8.277M: 2x + $250K allowance
- $8.277M - $33.208M: salary + $8.527M TPE allowance  
- Over $33.208M: 1.25x + $250K

### Proration Calculation
```excel
F3: =C3*($AI$6/174)    -- Salary already earned
G3: =C3-F3             -- Salary remaining
```
Uses 174-day season standard.

### Roster Fill Logic (Row 17)
```excel
=IF(AM21>=12, 0,
  IFERROR(
    LET(
      r, MATCH("Rookie Min "&$AI$3, Y!$B:$B, 0),
      c, MATCH($AI$3, Y!$D$2:$J$2, 0),
      v, INDEX(Y!$D:$J, r, c),
      IF(v="-",0,v)
    ), 0
  ) * (12-AM21)
)
```
Adds rookie minimum slots to reach 12-player floor.

### Trade Kicker Paid (Row 20)
Placeholder input cells (`AM20`, etc.) for entering trade bonus amounts.

---

## 7. Mapping to Our Postgres Model

| Matrix Concept | Our Table/View |
|----------------|----------------|
| Y warehouse lookups | `pcms.salary_book_warehouse` |
| SystemValues (Cap/Tax/Apron) | `pcms.league_system_values` |
| Team rosters | `pcms.salary_book_warehouse` filtered by team |
| Pick Database | `pcms.draft_picks` |
| Trade matching validation | `pcms.fn_trade_plan_tpe()` (partial) |
| Apron status per team | `pcms.team_salary_warehouse` |

### What's Missing From Our Schema

1. **Multi-team trade planner** — We have `fn_trade_plan_tpe()` for TPE trades but not a full multi-team scenario calculator
2. **Proration math** — Trade date → days responsible calculation not in SQL
3. **Roster fill logic** — Auto-adding minimum salary slots to reach 12/14 floor

---

## 8. Open Questions / TODO

- [ ] Should we build a `pcms.fn_multi_team_trade_validation(...)` function?
- [ ] The team apron/tax status lookup (rows 19-48) appears manually maintained — should we auto-generate?
- [ ] Trade kicker logic input cells — how do we model user-entered trade bonus amounts?
- [ ] Pick exchange tracking in trades — not modeled in current trade functions
- [ ] The "Expanded" vs "Standard" mode toggle represents pre/post trade-deadline apron rules — need to document when each applies

---

## 9. Representative Sample Data

### Row 1 (Team Selectors):
```json
{
  "AK": "POR",
  "AM": "Expanded",
  "AW": "MIL", 
  "AY": "Expanded",
  "BI": "BRK",
  "BK": "Expanded",
  "BU": "PHI",
  "BW": "Expanded"
}
```

### Row 3 (Config + First Player Row):
```json
{
  "A": "=LET(_xlpm.team, $AK$1, ...SORTBY(names, key, -1))",
  "C": "=IFERROR(LET(...INDEX(Y!$D:$J, r, c)...),0)",
  "AH": "Season:",
  "AI": "2025",
  "AK": "Buildup Out:",
  "AR": "Buildup In:"
}
```

### Row 12 (Trade Exception placeholder):
```json
{
  "AK": "Trade Exception - Out",
  "AR": "Trade Exception - In"
}
```
