# Trade Bonus Amounts Spec

**Source:** `reference/warehouse/trade_bonus_amounts.json`  
**Rows:** 56 (header/constants + ~40 player rows with trade kickers)

---

## 1. Purpose

The **Trade Bonus Amounts** sheet calculates the **actual trade kicker amounts** that would be added to a player's salary if traded. This is critical for trade math because:

- Trade kickers are **capped by CBA rules** — the kicker cannot push salary above the max for the player's years of service
- The sheet computes the **effective kicker** (after applying the max cap), then produces the **post-trade salary** for each year
- The Y Warehouse pulls these computed amounts (columns U–Z) for players with trade kickers

---

## 2. Key Inputs / Controls

| Cell | Description | Example |
|------|-------------|---------|
| `G4` | **Player selector** — dropdown to pick a player for the comparison calculator | `"Portis TK"` |
| `R15` | **Current date** — used to compute "day in season" for pro-rating | `2026-01-20` |
| `P15` | **Days remaining in season** — formula: `=174-(R15-DATE(2025,10,21))` | ~90+ days |

### Constants zone (rows 3–12)

Rows 6–12 (column B) list seasons 2025–2031. Columns C–E pull **max salary thresholds** from the `Maximums` table in `system_values.json`:

| Col | Header | Source |
|-----|--------|--------|
| C | `25%` | Max salary for 0–6 YOS |
| D | `30%` | Max salary for 7–9 YOS |
| E | `35%` | Max salary for 10+ YOS |

Formula example (row 6, 2025):
```excel
C6: =INDEX(Maximums[[#Data],[25%]], MATCH(Max[[#This Row],[Season]], Maximums[[#Data],[Season]], 0))
```

---

## 3. Key Outputs

### Player comparison dashboard (rows 4–7, columns G–N)

| Row | Description |
|-----|-------------|
| 5 | **New (post-trade) salaries** for selected player (2025–2030) |
| 6 | **Old (pre-trade) salaries** for selected player |
| 7 | **Difference** = kicker amount added per year; **N7** = total kicker amount |

### Player data table (rows 17–59)

One row per player with a trade kicker. Columns:

| Col | Header | Description |
|-----|--------|-------------|
| B | `Name` | Player identifier (e.g., `"NAW TK"`, `"Anunoby TK"`) |
| C | `2025` | Current year base salary |
| D | `Owed in '25` | Pro-rated salary for current year: `=C17*($P$15/174)` |
| E–I | `2026`–`2030` | Base salaries by year (0 = no contract) |
| J | `TK%` | Trade kicker percentage (e.g., `0.15`, `0.075`) |
| K | `TK Amount` | Total kicker value (before max constraint) |
| L | `Years` | Number of contract years remaining |
| M | `Option` | "Yes" if final year is an option (excluded from kicker base) |
| N | `Average` | Average kicker per year: `=K/L` |
| O | `YOS` | Years of service (determines which max column applies) |
| P | `Maximum` | Applicable max salary (25%/30%/35% based on YOS) |
| Q | `TK +/- Max` | Headroom: `=P-C` (max minus current salary) |
| R | `Actual Avg` | Effective kicker (capped by headroom): `=IF(N>Q,Q,N)` |
| S | `Net Avg` | Floor at zero: `=IF(R<=0,0,R)` |
| T | `Net Total` | Total effective kicker: `=S*L` |
| U–Z | `2025`–`2030` | **Post-trade salary** per year (base + net avg kicker) |

---

## 4. Layout / Zones

| Rows | Zone | Description |
|------|------|-------------|
| 1 | Title | `"Trade Bonus Amounts"` |
| 3 | Section header | `"Salary Cap Amounts"` |
| 4 | Comparison header | Player selector (G4) + year headers |
| 5–7 | Comparison output | New/Old/Difference for selected player |
| 6–12 | Max lookup (cols B–E) | Season → max salary by YOS tier |
| 15–16 | Data table header | Column labels + date metadata |
| 17–59 | Player data | One row per player with trade kicker |

---

## 5. Cross-Sheet Dependencies

### Trade Bonus Amounts references:

| Sheet/Table | Usage | Example |
|-------------|-------|---------|
| `Maximums` (in `system_values.json`) | Max salary lookup by YOS tier | `=INDEX(Maximums[[#Data],[25%]], MATCH(...))` |
| `Max` (named table, rows 6–12 in this sheet) | Self-reference for season matching | `Max[[#This Row],[Season]]` |

### Sheets that reference Trade Bonus Amounts:

| Sheet | Usage |
|-------|-------|
| `y.json` | Rows 615+ pull post-trade salaries via XLOOKUP into columns U–Z |

Y formula pattern:
```excel
B615: ='Trade Bonus Amounts'!B17
D615: =_xlfn.XLOOKUP(B615, 'Trade Bonus Amounts'!$B:$B, 'Trade Bonus Amounts'!U:U, "-")
```

---

## 6. Key Formulas / Logic

### Pro-rated current year salary (column D)

```excel
D17: =C17*($P$15/174)
```
- 174 = approximate regular season days
- Multiplies base salary by fraction of season remaining

### Total kicker amount (column K)

```excel
K17: =IF(M17="Yes", SUM(D17:I17) - IFERROR(LOOKUP(2, 1/(D17:I17>1), D17:I17), 0), SUM(D17:I17))*J17
```
- If option year exists (M="Yes"), exclude the last non-zero year from the base
- Multiply total remaining salary by kicker percentage

### Years remaining (column L)

```excel
L17: =IF(M17="Yes",COUNTIF(D17:I17,">0")-1,COUNTIF(D17:I17,">0"))
```
- Count non-zero salary years
- Subtract 1 if there's an option year

### Max salary lookup (column P)

```excel
P17: =IF(O17<=6, $C$6, IF(AND(O17>=7, O17<=9), $D$6, IF(O17>=10, $E$6, "")))
```
- 0–6 YOS → 25% max (column C)
- 7–9 YOS → 30% max (column D)
- 10+ YOS → 35% max (column E)

### Effective kicker (columns R–S)

```excel
R17: =IF(N17>Q17,Q17,N17)
S17: =IF(R17<=0,0,R17)
```
- Cap kicker at headroom (max - current salary)
- Floor at zero (can't be negative)

### Post-trade salary (columns U–Z)

```excel
U17: =IF(C17=0,"-",C17+$S17)
V17: =IF(E17=0,"-",E17+$S17)
...
```
- Add net average kicker to each year's base salary
- Return "-" if no contract in that year

### Option year handling

When a player has an option (M="Yes"), some cells show the base salary without kicker addition:
```excel
X18: =G18    (Anunoby's 2028 shows base, not base+kicker)
```
This reflects that kicker typically doesn't apply to option years.

---

## 7. Data Examples

### Row 18 (OG Anunoby)

| Col | Value | Description |
|-----|-------|-------------|
| B | `Anunoby TK` | |
| C | `39568966` | 2025 base salary |
| J | `0.15` | 15% trade kicker |
| O | `8` | 8 years of service |
| P | `$D$6` | → 30% max tier |
| M | `Yes` | Has player option |

### Row 24 (Jaylen Brown)

| Col | Value | Description |
|-----|-------|-------------|
| B | `Brown TK` | |
| C | `53142264` | 2025 base salary |
| J | `0.07` | 7% trade kicker |
| O | `9` | 9 years of service |
| M | (empty) | No option |

---

## 8. Mapping to Postgres

| Trade Bonus Column | PCMS Source |
|--------------------|-------------|
| B (Name) | Player identifier — would need display name lookup |
| C–I (Base salaries) | `pcms.salaries.contract_cap_salary` by year |
| J (TK%) | `pcms.contract_versions.trade_bonus_percent` |
| O (YOS) | `pcms.people.years_exp` or computed from draft year |
| Max lookup | `pcms.league_system_values` (we have 25%/30%/35% columns) |

### Warehouse coverage

Our `pcms.salary_book_warehouse` includes:
- `trade_kicker_display` — shows kicker % or "Used"
- `trade_bonus_percent` — raw percentage from contract_versions

**Gap:** We don't currently compute/store:
- Effective kicker amount (after max constraint)
- Post-trade salary columns
- YOS tier logic for max determination

### Trade machine usage

The trade machine needs post-trade salaries for kicker players. Two approaches:

1. **Compute at query time**: Use `trade_bonus_percent`, `years_exp`, and `league_system_values` to calculate effective kicker
2. **Pre-compute in warehouse**: Add `trade_kicker_effective_amount` and `post_trade_cap_YYYY` columns

---

## 9. CBA Rules (embedded in formulas)

1. **Trade kicker base**: Total remaining guaranteed salary × kicker %
2. **Option year exclusion**: Option years are excluded from kicker base calculation
3. **Max salary cap**: Kicker cannot push salary above the max for player's YOS:
   - 0–6 YOS → 25% of cap
   - 7–9 YOS → 30% of cap
   - 10+ YOS → 35% of cap
4. **Pro-rating**: Current year salary is pro-rated by days remaining in season

---

## 10. Open Questions

1. **Player selection**: How are the ~40 players in this sheet selected? Likely manually curated list of notable kicker contracts.

2. **"Used" kickers**: Players whose kickers were already triggered aren't in this sheet — handled separately in Y (AI column shows "Used").

3. **Partial kickers**: Some players have non-standard percentages (3.23%, 5%, 7.5%). Source is `trade_bonus_percent` from contract.

4. **Option logic**: The formula excludes option years using a LOOKUP trick. Need to verify this matches CBA interpretation.

---

## 11. Summary

Trade Bonus Amounts is a **specialized calculator** for trade kicker impact:

- Takes base salaries + kicker % + YOS
- Applies CBA max constraint (kicker can't push above max)
- Outputs post-trade salaries by year (columns U–Z)
- Y Warehouse consumes these outputs for players with kickers

For our trade machine, we need to replicate this logic:
1. Look up player's YOS tier → applicable max
2. Compute headroom: max - current salary
3. Compute raw kicker: remaining salary × kicker %
4. Effective kicker = MIN(raw kicker per year, headroom)
5. Post-trade salary = base + effective kicker

This could be a SQL function (`pcms.fn_trade_kicker_amount`) or embedded in the trade planner.
