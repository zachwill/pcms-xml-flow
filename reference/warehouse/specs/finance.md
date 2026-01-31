# Spec: `finance.json`

**Source:** `reference/warehouse/finance.json`
**Rows:** 71

---

## 1. Purpose

Team-level **financial forecast / planning sheet**. Lets analysts:

1. View a single team's multi-year salary commitments (2025–2030)
2. Calculate **cap space, tax liability, apron position** per year
3. Model future roster additions (draft picks, MLE signings)
4. View total **Net Cost** (committed salaries + tax payments + bonuses + other cash)
5. Run quick **Trade Machine** lookups for incoming/outgoing salary matching
6. See draft pick ownership (1st and 2nd round, 2026-2032)
7. Use a **Renegotiation Calculator** for extension scenarios

Essentially a "Team Financial Dashboard" for cap planning.

---

## 2. Key Inputs / Controls

| Cell | Type | Description |
|------|------|-------------|
| `D2` | Selector | **Team code** (e.g. `POR`) |
| `E2` | Selector | **Base year** (e.g. `2025`) |
| `J2` | Formula | **Repeater in '25** — "Yes"/"No" (controls tax multiplier) |
| `N2` | Formula | **Repeater in '26** — "Yes"/"No" |
| `AD25` | Selector | Trade Machine mode: `"Expanded"` or `"Standard"` |
| `AF25` | Selector | Trade Machine year (e.g. `2025`) |
| `AD4`, `AK4` | Input | **Contract Calculator - Total** target (e.g. `50000000`) |
| `AD5`, `AK5` | Input | **% Raise** (e.g. `0.08`) |

Row 2 formula `J2` (Repeater):
```excel
=IF($D$2="POR","No",
 IF($D$2="BOS","Yes",
 IF($D$2="PHX","Yes", ... )))
```
Hard-coded repeater lookup for known repeater teams.

---

## 3. Key Outputs

### Player Salary Table (rows 5–35)

| Col | Description |
|-----|-------------|
| A | Sorted player names (via LET/SORTBY formula in A5) |
| C | Row number (for players with salary >1000) |
| D | Player name (=A if non-zero) |
| E, G, I, K, M, O | Salary amount per year (2025, 2026, 2027, 2028, 2029, 2030) |
| F, H, J, L, N, P | Salary as % of cap for that year |
| Q | Option info from Y warehouse |

### Depth Chart (cols S–W, rows 5–30)

Four depth-chart blocks by year:
- 2025 (rows 5–10)
- 2026 (rows 13–18)
- 2027 (rows 25–28)

Each block: 5 positions × 5 columns of player last names.

### Signings / Picks Section (rows 29–35)

Manual entries for projected signings:
- `R-MLE 2026`, `#13 2026`, `#20 2027`, `SRP 2027`, `#23 2028`

### Roster Counts & Cap Fill (rows 36–38)

| Row | Label | Formula |
|-----|-------|---------|
| 36 | Roster Count | `=COUNTIF(E5:E35,">1")` |
| 37 | (+) Rookie Mins | Fills to 12 players at rookie min |
| 38 | (+) Vet Mins | Fills to 14 players at vet min |

### Cash / Bonus Items (rows 39–45)

| Row | Label |
|-----|-------|
| 39 | Signing Bonus Paid |
| 40 | Proj. Two-Ways (3) |
| 41 | Ex. 10 Bonuses (6) |
| 42 | Cash in Trade |
| 43 | Waiver Claim |
| 44 | International Buyout |
| 45 | `<team> Dead Money` |

### Financial Summary (rows 47–62)

| Row | Label | Description |
|-----|-------|-------------|
| 47 | Total Committed | `=SUM(E5:E35)+E45` |
| 48 | Minimum Level | From SystemValues |
| 49 | +/- Minimum | =Total - Min level |
| 50 | Cap Level | From SystemValues |
| 51 | Cap Space | =Total + holds + dead - Cap |
| 52 | Tax Level | From SystemValues |
| 53 | +/- Tax | =Total + vet mins + dead - Tax |
| 54 | Tax Payment | SUMPRODUCT against Tax Array (repeater/non-repeater brackets) |
| 55 | Tax Refund | Refund if under tax |
| 56 | Apron 1 Level | From SystemValues |
| 57 | +/- Apron 1 | |
| 58 | Apron 2 Level | From SystemValues |
| 59 | +/- Apron 2 | |
| 60 | Net Cost | =Total Committed + Tax + Refund + bonuses + cash |
| 61 | Cost Savings | =Net Cost - Baseline |
| 62 | Baseline Cost | (manual input) |

### Legend (row 63)

Color coding labels:
- Projected Salary, Player Option, Team Option, Partial Guarantee, Non-Guarantee, Cap Hold

### Draft Pick Ownership (rows 64–71)

| Row | Label | 1st Round (col E) | 2nd Round (col K) |
|-----|-------|-------------------|-------------------|
| 65 | 2026 | XLOOKUP from Pick Database | XLOOKUP from Pick Database |
| 66 | 2027 | ... | ... |
| ... | ... | ... | ... |
| 71 | 2032 | ... | ... |

### Trade Machine Block (cols Y–AK, rows 24–46)

| Cell | Description |
|------|-------------|
| Z24 | "Trade Machine" header |
| AD25 | Mode: "Expanded" / "Standard" |
| AF25 | Year selector |
| Z27–Z42, AG27–AG42 | Player names for trade scenarios |
| AA, AH | Player salary looked up from Y warehouse |
| AC, AJ | Calculated "incoming salary can receive" per expanded/standard trade rules |
| Z45, AA45 | Total incoming |
| AG45, AH45 | Total outgoing |

Trade math formulas (AC/AJ columns) implement:
- Standard: salary + $8.527M (2025) offset
- Expanded: 2× + $250K for small salaries, +$8.527M for mid, 1.25× for large

### Renegotiation Calculator (cols S–W, rows 32–40)

| Row | Col | Description |
|-----|-----|-------------|
| 33 | S-W | Headers: Season, Current, Renegotiate, Levers, Extn. Raise |
| 34-38 | S | 2026, 2027, 2028, 2029, 2030 |
| 34-38 | T | Current salary |
| 34-38 | U | Renegotiated amount |
| 34-38 | V | "Levers" multiplier (0.92, 0.6, etc.) |
| 39 | U | Total |
| 40 | U | New Money |

### Contract Calculator (cols Y–AK, rows 4–13)

Two calculators side by side:
- "Contract Calculator - Total" (cols Y-AD): Given total and % raise, compute yearly amounts
- "Contract Calculator - Start Number" (cols AF-AK): Given start salary and % raise, compute yearly amounts

---

## 4. Layout / Zones

| Rows | Cols | Zone |
|------|------|------|
| 1-2 | C-N | Title + Team/Year selectors + Repeater flags |
| 3-4 | C-Q | Column headers (years, #, Player) |
| 5-35 | A-Q | Player salary matrix |
| 5-30 | S-W | Depth chart by year |
| 36-45 | D-P | Roster count, min fills, bonuses, dead money |
| 47-62 | D-P | Financial summary (cap/tax/apron) |
| 63 | E-O | Color legend |
| 64-71 | D-K | Draft pick ownership |
| 24-46 | Y-AK | Trade Machine block |
| 32-40 | S-W | Renegotiation Calculator |
| 4-13 | Y-AK | Contract Calculator |

---

## 5. Cross-Sheet Dependencies

### References OUT (Finance → other sheets)

| Sheet | Usage | Count |
|-------|-------|-------|
| `Y!` | Player salaries lookup | 674 refs |
| `SystemValues` | Cap/Tax/Apron/Min levels | 60 refs |
| `'Tax Array'!` | Tax bracket calculations | 12 refs |
| `'Pick Database'!` | Draft pick ownership | 14 refs |

### References IN (other sheets → Finance)

None found — Finance is a terminal/presentation sheet.

---

## 6. Key Formulas / Logic Patterns

### A5: Sorted player list

```excel
=_xlfn.LET(
  _xlpm.team,      $D$2,
  _xlpm.yr,        E2,
  _xlpm.hdrs,      Y!$D$2:$P$2,
  _xlpm.tbl,       Y!$B$3:$P$1137,
  _xlpm.colIx,     MATCH(_xlpm.yr, _xlpm.hdrs, 0) + 2,
  _xlpm.teamRows,  FILTER(_xlpm.tbl, INDEX(_xlpm.tbl,,2)=_xlpm.team),
  _xlpm.names,     INDEX(_xlpm.teamRows,,1),
  _xlpm.rawSal,    INDEX(_xlpm.teamRows,,_xlpm.colIx),
  _xlpm.cleanSal,  NUMBERVALUE(SUBSTITUTE(...)),
  _xlpm.key,       IF(ISNUMBER(_xlpm.cleanSal), _xlpm.cleanSal, -10000000000),
  SORTBY(_xlpm.names, _xlpm.key, -1, _xlpm.yearsKey, -1, _xlpm.names, 1)
)
```
Filters Y warehouse for team, sorts by salary descending.

### E5 (and similar): Salary lookup

```excel
=IFERROR(
  _xlfn.LET(
    _xlpm.r, MATCH(D5, Y!$B:$B, 0),
    _xlpm.c, MATCH($E$4, Y!$D$2:$J$2, 0),
    _xlpm.v, INDEX(Y!$D:$J, _xlpm.r, _xlpm.c),
    IF(_xlpm.v="-", 0, _xlpm.v)
  ),
0)
```
Looks up player name in Y column B, returns salary for the year.

### E50: Cap Level

```excel
=_xlfn.XLOOKUP(E4,SystemValues[[#All],[Season]],SystemValues[[#All],[Salary Cap]])
```
Uses structured table reference to SystemValues.

### E54: Tax Payment (key formula)

```excel
=IF(
  $J$2="Yes",
  SUMPRODUCT(
    (E53>'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$K$4:$K$200=$E$4) *
    (E53 - 'Tax Array'!$M$4:$M$200) *
    ('Tax Array'!$O$4:$O$200)
  ),
  SUMPRODUCT(
    (E53>'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$E$4:$E$200=$E$4) *
    (E53 - 'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$I$4:$I$200)
  )
)
```
Calculates tax using repeater vs non-repeater brackets from Tax Array sheet.

### AC41: Trade Machine - Expanded incoming salary

```excel
=IF(
$AF$25=2024,
IF(AA42="","",
  IF($AD$25="Expanded",
    IF(AA42<7493424,AA42*2+250000,
      IF(AA42<=29973695,AA42+7752000,
        IF(AA42>29973695,AA42*1.25+250000,AA42))),
    AA42)),
IF(AA42="","",
  IF($AD$25="Expanded",
    IF(AA42<8277000,AA42*2+250000,
      IF(AA42<=29973695,AA42+8527000,
        IF(AA42>29973695,AA42*1.25+250000,AA42))),
    AA42))
)
```
Implements 2023 CBA trade matching rules for expanded/standard trades.

---

## 7. Mapping to Postgres Model

| Sean Concept | Our Table(s) |
|--------------|--------------|
| Player salary grid (E5:O35) | `pcms.salary_book_warehouse` |
| Cap/Tax/Apron levels | `pcms.league_system_values` |
| Dead Money (row 45) | `pcms.dead_money_warehouse` |
| Tax brackets (Tax Array) | `pcms.tax_brackets` (TODO?) |
| Draft picks (rows 65-71) | `pcms.draft_picks` |
| Trade Machine math | `pcms.fn_tpe_trade_math()` / trade primitives |
| Roster count / min fills | Could compute from salary_book_warehouse |
| Team totals (row 47-59) | `pcms.team_salary_warehouse` |

### Missing from our schema

- **Tax Array / tax brackets** — Sean has a Tax Array sheet with bracket thresholds + rates. We may need to add `pcms.tax_brackets` for accurate tax payment calculation.
- **Repeater flag** — Currently hard-coded in Sean's sheet. Should be derived or stored.
- **Renegotiation Calculator logic** — Extension raise coefficients.
- **Team-specific draft pick ownership** — We have `pcms.draft_picks` but need to verify filtering by team works.

---

## 8. Open Questions / TODO

- [ ] **Tax Array sheet**: Spec `tax_array.json` to understand bracket structure
- [ ] **Pick Database sheet**: Spec `pick_database.json` for ownership lookup format
- [ ] Verify `pcms.draft_picks` can replicate the XLOOKUP pattern
- [ ] Consider adding a "team finance snapshot" cache for common queries
- [ ] The "Repeater" logic is hard-coded — should derive from historical tax data
