# Trade Machine Spec

**Source:** `reference/warehouse/machine.json`  
**Rows:** 97 (4 trade scenarios × ~25 rows each + reference tables)

---

## 1. Purpose

The **Trade Machine** is an interactive salary-matching calculator for evaluating NBA trades. It enables:

- **2-team trade scenarios** — select teams, add/remove players, check if salaries match
- **Salary matching rules** — calculates expanded/standard trade multipliers based on CBA rules
- **Year-sensitive** — supports 2024 vs 2025 matching thresholds
- **TPE lookup** — shows available trade exceptions for each team
- **"Can Bring Back"** — helper table showing which players a team can acquire based on outgoing salary

---

## 2. Key Inputs / Controls

| Cell | Control | Values |
|------|---------|--------|
| `B1` | **Team 1 selector** (outgoing) | 3-letter team code (e.g., `POR`) |
| `G1` | **Team 2 selector** (incoming) | 3-letter team code (e.g., `MIN`) |
| `F1` | **Multiplier mode** | `Expanded` or `Standard` |
| `J1` | **Season year** | `2024` or `2025` |
| `B3`, `B6`, `B9`, … | **Player names** (Team 1) | Player name to include in trade |
| `G3`, `G6`, `G9`, … | **Player names** (Team 2) | Player name to include in trade |

Each scenario block (rows 1–29, 31–59, 61–89, 91–119) has its own team selectors at the header row.

---

## 3. Key Outputs

| Zone | Rows | Description |
|------|------|-------------|
| **Scenario 1** | 1–29 | First trade scenario |
| **Scenario 2** | 31–59 | Second trade scenario |
| **Scenario 3** | 61–89 | Third trade scenario |
| **Scenario 4** | 91–119 | Fourth trade scenario (final rows) |

Within each scenario:

| Element | Row offset | Columns | Description |
|---------|------------|---------|-------------|
| **Header** | +0 | B, G | Team codes |
| **Controls** | +0 | F (multiplier), J (year) | Mode toggles |
| **TPE list** | +1 | L, O | Team 1/2 available TPEs |
| **Player entries** | +2, +5, +8, … | B/G (name), C/H (salary), E/J (can-bring-back) | Alternating player rows |
| **Roster lookup** | +9 | L, O | Dynamic team roster lists (sorted by salary) |
| **Salary totals** | +26 | B/G="Total", C/H=sum | Total outgoing salaries |
| **Trade works?** | +28 | F | `=IF(E27>=H27,"Yes","No")` — does expanded/matched salary pass? |
| **Reference table** | side panel | S–U | Salary matching tiers (low/high thresholds + rule descriptions) |

---

## 4. Layout / Column Map

### Per-Scenario Columns

| Col | Content |
|-----|---------|
| A | (unused) |
| B | Team 1 player name (or "Total") |
| C | Team 1 player's cap salary (from Y lookup) |
| D | `{` (visual bracket) |
| E | **Expanded matching** — what Team 2 can send back for C |
| F | Trade status (`Yes`/`No`) or multiplier control |
| G | Team 2 player name (or "Total") |
| H | Team 2 player's cap salary |
| I | `{` (visual bracket) |
| J | **Expanded matching** — what Team 1 can send back for H |
| L–M | Team 1 TPE list + amounts |
| O–P | Team 2 TPE list + amounts |
| S–U | Reference table: salary matching tiers |

### Salary Matching Reference Table (cols S–U, rows 2–7 per scenario)

Example from Scenario 1 (2023 cap = $136,021,000 referenced in U2):

| Row | S (Out Low) | T (Out High) | U (Rule) |
|-----|-------------|--------------|----------|
| 4 | 0 | 7,250,000 | 200% of outgoing salary + 250K |
| 5 | 7,250,000 | 29,000,000 | Outgoing salary + 7.5M |
| 6 | 29,000,000 | Up | 125% of outgoing salary + 250K |
| 7 | Over Apron 1 | — | 1 (factor for apron teams) |

This table encodes the CBA salary-matching brackets.

---

## 5. Cross-Sheet Dependencies

### Machine references:

| Sheet | Usage | Example |
|-------|-------|---------|
| `Y` | Player salary lookup | `=IFERROR(INDEX(Y!$D:$J,MATCH($B3,Y!$B:$B,0),MATCH($J$1,Y!$D$2:$J$2,0)),"")` |
| `Exceptions Warehouse - 2024` | TPE list for team | `=IFERROR(_xlfn._xlws.FILTER('[2]Exceptions Warehouse - 2024'!$C$4:$C$70, '[2]Exceptions Warehouse - 2024'!$B$4:$B$70=B1),"None")` |
| `X` (external) | Cap constants | `=[2]X!AN9` (cap for 2024) |

### Dynamic roster lookup (cols L, O):

The roster is dynamically built using `LET` + `FILTER` + `SORTBY`:

```excel
=_xlfn.LET(
  _xlpm.team,    $B$1,
  _xlpm.yr,      J1,
  _xlpm.hdrs,    Y!$D$2:$P$2,
  _xlpm.tbl,     Y!$B$3:$P$2022,
  _xlpm.colIx,   MATCH(_xlpm.yr, _xlpm.hdrs, 0) + 2,
  _xlpm.teamRows,_xlfn._xlws.FILTER(_xlpm.tbl, INDEX(_xlpm.tbl,,2)=_xlpm.team),
  _xlpm.names,   INDEX(_xlpm.teamRows,,1),
  _xlpm.sal,     INDEX(_xlpm.teamRows,,_xlpm.colIx),
  _xlpm.key,     IFERROR(--_xlpm.sal, -10000000000),
  _xlfn.SORTBY(_xlpm.names, _xlpm.key, -1)
)
```

This filters Y data by team and sorts players by salary descending.

### Sheets that reference Machine:

No other sheets appear to reference Machine — it's a leaf/tool sheet.

---

## 6. Key Formulas / Logic

### Player salary lookup (C3, H3, etc.):

```excel
=IF($B3="","",IFERROR(INDEX(Y!$D:$J,MATCH($B3,Y!$B:$B,0),MATCH($J$1,Y!$D$2:$J$2,0)),""))
```

Looks up player's cap salary from Y for the selected year (`$J$1`).

### Expanded matching formula (E3, J3):

This is the core salary-matching logic. For a player's outgoing salary, calculates **max incoming salary allowed**:

```excel
=IF(
  $J$1=2024,
  IF(C3="","",
    IF($F$1="Expanded",
      IF(C3<7493424,
        C3*2+250000,                    -- Low tier: 200% + 250K
      IF(C3<=29973695,
        C3+7752000,                     -- Mid tier: salary + 7.752M
      IF(C3>29973695,
        C3*1.25+250000,                 -- High tier: 125% + 250K
        C3
      ))),
      C3                                 -- Standard mode: 1:1
    )
  ),
  IF(C3="","",
    IF($F$1="Expanded",
      IF(C3<8277000,
        C3*2+250000,                    -- 2025 low: 200% + 250K
      IF(C3<=29973695,
        C3+8527000,                     -- 2025 mid: salary + 8.527M
      IF(C3>29973695,
        C3*1.25+250000,                 -- 2025 high: 125% + 250K
        C3
      ))),
      C3
    )
  )
)
```

**CBA salary-matching tiers (2025 values):**

| Outgoing Salary | Max Incoming |
|-----------------|--------------|
| $0 – $8,277,000 | 200% + $250K |
| $8,277,001 – $29,973,695 | salary + $8,527,000 |
| > $29,973,695 | 125% + $250K |

For 2024, the thresholds are slightly different ($7,493,424 / $7,752,000).

### Reverse matching formula (E5, J5):

Given an incoming (expanded) amount, calculates the **minimum outgoing salary needed**:

```excel
=IF(C3="","",
  IF($F$1="Expanded",
    IF($J$1=2024,
      IF(C3-7752000<=7493424,(C3-250000)/2,
        IF(C3-7752000>29973695,(C3-250000)/1.25,
          C3-7752000)),
    IF(C3-8527000<=8277000,(C3-250000)/2,
      IF(C3-8527000>33208000,(C3-250000)/1.25,
        C3-8527000))),
  IF($F$1="Standard",
    IF($J$1=2024,C3-7752000,C3-8527000),
    C3)))
```

This inverts the matching formula — used for "Can Bring Back" calculations.

### Salary totals (C27, H27):

```excel
C27: =SUM(C3:C26)
H27: =SUM(H3:H26)
```

### Trade validation (F29):

```excel
=IF(E27>=H27,"Yes","No")
```

If Team 1's expanded outgoing amount ≥ Team 2's actual outgoing, the trade works.

### Net salary difference (F28):

```excel
=H27-C27
```

Shows raw salary delta between sides.

---

## 7. "Can Bring Back" Helper (cols L–O, rows 32+)

The sheet includes a **"Can Bring Back"** zone showing:

| Col L | Col M | Col O |
|-------|-------|-------|
| Player Name | Max incoming | Min incoming |

For each player on Team 1's roster, shows the salary range they could acquire in return.

Example (row 34):
```
Ayton, Deandre | 44688517.5 (max) | 27023814 (min)
```

This helps the analyst quickly scan which players fit the salary-matching window.

---

## 8. Mapping to Postgres

| Machine Concept | Our Tables/Functions |
|-----------------|---------------------|
| Player salary lookup | `pcms.salary_book_warehouse` (cap_20XX columns) |
| Team roster | `pcms.salary_book_warehouse WHERE team_code = ?` |
| TPE list | `pcms.exceptions_warehouse` |
| Salary matching tiers | `pcms.league_system_values` (for thresholds) |
| Matching calculation | `pcms.fn_tpe_trade_math()` |
| Trade planner | `pcms.fn_trade_plan_tpe()` |

### Functions we have:

- **`pcms.fn_tpe_trade_math()`** — implements salary matching logic
- **`pcms.fn_trade_plan_tpe()`** — TPE-based trade planner (produces structured output)
- **`pcms.salary_book_yearly`** — unpivoted view for trade math

### Gaps:

1. **Multi-scenario UI** — Machine supports 4 parallel scenarios; our functions are single-trade.
2. **"Can Bring Back" helper** — we don't have a dedicated function for this; could derive from salary matching.
3. **Expanded vs Standard toggle** — our functions currently assume expanded; may need a parameter.
4. **Year-sensitive thresholds** — we should parameterize the matching brackets by year.

---

## 9. Salary Matching Thresholds

Extracted from Machine formulas:

| Year | Tier | Outgoing Range | Incoming Formula |
|------|------|----------------|------------------|
| 2024 | Low | $0 – $7,493,424 | 200% + $250K |
| 2024 | Mid | $7,493,425 – $29,973,695 | salary + $7,752,000 |
| 2024 | High | > $29,973,695 | 125% + $250K |
| 2025 | Low | $0 – $8,277,000 | 200% + $250K |
| 2025 | Mid | $8,277,001 – $29,973,695 | salary + $8,527,000 |
| 2025 | High | > $29,973,695 | 125% + $250K |

For **Apron 1 teams**, the multiplier is `1` (dollar-for-dollar matching).

---

## 10. Open Questions

1. **Apron team rules**: Row 7 shows "Over Apron 1" with factor `1`. How does Machine handle apron-team restrictions (no aggregation, etc.)?

2. **Standard mode**: What exactly does "Standard" matching mean? The formulas suggest it's just `salary + 7.75M` (no tiered expansion). Verify against CBA.

3. **TPE usage**: The TPE list appears but doesn't seem integrated into the matching calculation. Is TPE absorption handled separately?

4. **2024 vs 2025 thresholds**: The formula has hardcoded values. Should pull from `system_values.json` or our `league_system_values` table.

5. **Multiple scenarios**: Why 4 scenarios? Likely for comparing trade variations side-by-side.

---

## 11. Summary

Machine is the **trade salary-matching calculator**. Core workflow:

1. **Select teams** (B1, G1)
2. **Add player names** to each side (B3, G3, B6, G6, …)
3. **Salaries auto-populate** from Y
4. **Matching formulas** calculate expanded/allowed amounts
5. **"Yes/No" indicator** shows if trade balances

Our Postgres functions (`fn_tpe_trade_math`, `fn_trade_plan_tpe`) implement similar logic but with different ergonomics. Key alignment:

| Machine Feature | Our Equivalent |
|-----------------|----------------|
| Salary lookup | `salary_book_warehouse` |
| Matching tiers | `fn_tpe_trade_math()` |
| Trade validation | `fn_trade_plan_tpe()` |
| TPE list | `exceptions_warehouse` |

The Machine sheet is self-contained and doesn't feed other sheets.
