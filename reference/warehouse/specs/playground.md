# Playground Spec

**Source:** `reference/warehouse/playground.json`  
**Rows:** 70 (compact team-specific salary book view)

---

## 1. Purpose

The **Playground** sheet is an interactive team Salary Book viewer. Given a team code and base year, it:

- Lists all players on the team roster with salaries across 6 years (2025–2030)
- Shows % of cap for each player
- Displays trade kicker (TK) column
- Calculates roster fills (Rookie Mins, Vet Mins)
- Computes team totals vs Cap / Tax / Apron 1 / Apron 2 thresholds
- Calculates luxury tax payment estimates
- Shows draft pick ownership (1st/2nd round, 2026–2032)

Additionally includes:
- **Depth Chart** mini-view (columns S–W): roster by position / year
- **Contract Calculator** blocks (columns Y–AK): hypothetical contract modeling with % raises
- **Trade Machine input zone** (columns Z–AJ): expanded salary match logic

---

## 2. Key Inputs / Controls

| Cell | Label | Sample Value | Purpose |
|------|-------|--------------|---------|
| `D1` | Team Code | `POR` | User selects team (3-letter code) |
| `E1` | Base Year | `2025` | Starting year for multi-year grid |
| `F1` | `=TODAY()` | (dynamic) | Current date for proration calcs |
| `H1` | Days remaining | `=DATE(2026,4,12)-F1+1` | Days left in season (used for proration) |
| `J1` | Repeater in '25 | `Yes`/`No` | Hardcoded IF-chain based on team code |
| `N1` | Repeater in '26 | `Yes`/`No` | Hardcoded IF-chain based on team code |
| `AD3` | Contract total | `140000000` | User input for contract calculator |
| `AD4` | % Raise | `0.08` | User input raise percentage |
| `AK3` | Start salary | `19500000` | Alternate calculator start value |
| `AD24` | Trade mode | `Expanded` | Standard vs Expanded trade rules |
| `AF24` | Trade year | `2025` | Year context for trade calculations |

---

## 3. Key Outputs

### Player Roster (rows 4–41)

| Column | Header | Description |
|--------|--------|-------------|
| A | (sorted name) | LET formula filters Y!$B$3:$P$1137 by team, sorts descending by salary |
| C | # | Row count of players with salary >1000 |
| D | Player | Display name (mirrors A unless 0) |
| E,G,I,K,M,O | 2025–2030 | Cap salary from Y warehouse per year |
| F,H,J,L,N,P | % | Salary / cap total |
| Q | TK | Trade kicker % from Y column P |

### Team Totals Block (rows 42–63)

| Row | D label | Formula pattern |
|-----|---------|-----------------|
| 42 | Roster Count | `COUNTIF(E4:E38,">1")` |
| 43 | (+) Rookie Mins | Fill to 12 roster spots with Rookie Min from Y |
| 44 | (+) Vet Mins | Fill to 14 roster spots with Vet Min from Y |
| 45 | Dead Money | Team-specific dead cap from Y (e.g., "POR Dead Money") |
| 47 | Team Salary | `=SUM(E4:E41)+E45` |
| 48 | Team Salary (fill to 14) | Includes vet mins |
| 49 | Minimum Level | `=XLOOKUP(E3, SystemValues, [Minimum Level])` |
| 50 | +/- Minimum | `=E47-E49` |
| 51 | Cap Level | `=XLOOKUP(E3, SystemValues, [Salary Cap])` |
| 52 | Cap Space | `=(SUM(E4:E41)+E43+E45)-E51` |
| 53 | Tax Level | `=XLOOKUP(E3, SystemValues, [Tax Level])` |
| 54 | +/- Tax | `=SUM(E4:E41)+E44+E45-E53` |
| 55 | Tax Payment | SUMPRODUCT over 'Tax Array' brackets |
| 56 | Tax Refund | Bonus if under tax threshold |
| 57 | Apron 1 Level | `=XLOOKUP(E3, SystemValues, [Apron 1])` |
| 58 | +/- Apron 1 | `=SUM(E4:E41)+E44+E45-E57` |
| 59 | Apron 2 Level | `=XLOOKUP(E3, SystemValues, [Apron 2])` |
| 60 | +/- Apron 2 | `=SUM(E4:E41)+E44+E45-E59` |
| 61 | Net Cost | `=E47+E55+E56+E44` (salary + tax payment + refund + fills) |
| 62 | Cost Savings | `=E61-E63` (vs baseline) |
| 63 | Baseline Cost | (blank input cell for scenario comparison) |

### Draft Pick Ownership (rows 65–72)

| Row | Description |
|-----|-------------|
| 65 | Headers: "1st Round" (D), "2nd Round" (K) |
| 66–72 | 2026–2032 picks via `XLOOKUP($D$1, 'Pick Database'!)` |

### Depth Chart (rows 4–17, columns S–W)

Shows roster by position grouping per year:
- S–W: Player names by position for 2025
- Row 11 onwards: 2026, 2027 depth charts

### Contract Calculator (rows 3–12, columns Y–AK)

Two calculator blocks:
- **Total-based** (Y–AD): Given total, compute annual salaries with raises
- **Start-based** (AF–AK): Given start salary, compute annual salaries

---

## 4. Layout / Zones

```
Row 1:     [D1: Team] [E1: Year] [F1: TODAY()] [H1: Days] [I1-N1: Repeater flags]
Row 2:     Section titles: "Player Contracts" | "Depth Chart" | "Contract Calculator"
Row 3:     Column headers: # | Player | 2025 | % | 2026 | % | ... | TK
Rows 4-22: Player roster (LET/FILTER from Y, sorted by salary descending)
Row 23:    "Trade:" label
Rows 24-41: Additional players / Trade input zone
Row 42:    Roster Count
Rows 43-45: Mins + Dead Money
Row 47-63: Team totals dashboard
Rows 65-72: Draft pick ownership grid
```

---

## 5. Cross-Sheet Dependencies

### Playground reads from:

| Sheet | Range/Table | Purpose |
|-------|-------------|---------|
| **Y** | `Y!$B$3:$P$1137` | Player name + salary matrix |
| **Y** | `Y!$D$2:$J$2` | Year headers (2025–2031) |
| **Y** | `Y!$B:$B` | Player name lookup column |
| **SystemValues** | Named table | Cap/Tax/Apron/Minimum levels by season |
| **'Tax Array'** | `$E$4:$O$200` | Tax bracket calculations (repeater vs non-repeater) |
| **'Pick Database'** | `$B$4:$J$63` | Draft pick ownership by team/year |

### What references Playground:

- **Y Warehouse** contains a row named "Playground" (row ~2054) — likely a reference marker, not a formula dependency

---

## 6. Key Formulas

### Player name list (A4)

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
Filters Y warehouse by team, extracts player names sorted descending by salary for selected year.

### Salary lookup (E4 and similar)

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
Looks up player salary from Y by name + year column.

### Tax payment (E55)

```excel
=IF(
  $J$1="Yes",
  SUMPRODUCT(
    (E54>'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$K$4:$K$200=$E$3) *
    (E54 - 'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$O$4:$O$200)
  ),
  SUMPRODUCT(
    (E54>'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$E$4:$E$200=$E$3) *
    (E54 - 'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$I$4:$I$200)
  )
)
```
Computes luxury tax using repeater (J1=Yes) or standard brackets from Tax Array.

### Expanded trade match (AC25)

```excel
=IF(
  $AF$24=2024,
  IF(AA26="","",
    IF($AD$24="Expanded",
      IF(AA26<7493424, AA26*2+250000,
        IF(AA26<=33208001, AA26+7752000,
          IF(AA26>33208001, AA26*1.25+250000, AA26)
        )
      ),
      AA26
    )
  ),
  ... (similar for 2025 thresholds)
)
```
Computes expanded trade matching salary (125% + $250K rules).

---

## 7. Mapping to Postgres

| Playground Concept | Our Table(s) |
|--------------------|--------------|
| Player salaries by year | `pcms.salary_book_warehouse` |
| Team selector + roster | `pcms.salary_book_warehouse WHERE team_code = ?` |
| Cap/Tax/Apron levels | `pcms.league_system_values` |
| Dead money | `pcms.dead_money_warehouse` |
| Trade kicker display | `pcms.salary_book_warehouse.trade_kicker_display` |
| Draft pick ownership | `pcms.draft_picks` |
| Tax bracket calcs | `pcms.luxury_tax_brackets` (if exists) or computed |
| Team totals | `pcms.team_salary_warehouse` |

---

## 8. Open Questions / TODO

- [ ] `por.json` appears to be a frozen snapshot of Playground with D1=POR. Verify if it's just a copy or has distinct logic.
- [ ] Repeater status (J1/N1) is hardcoded — should come from `pcms.teams` or computed from 3-year tax history.
- [ ] Contract Calculator blocks (Y–AK) are standalone scenario tools — may warrant separate utility functions.
- [ ] Tax Array integration: verify our luxury tax calculation matches Sean's SUMPRODUCT pattern.
- [ ] Baseline Cost (row 63) appears to be user-input for scenario comparison — not populated by formula.
