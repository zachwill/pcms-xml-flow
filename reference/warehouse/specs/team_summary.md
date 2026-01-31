# Team Summary Spec

**Source:** `reference/warehouse/team_summary.json`  
**Rows:** 36 (1 header row + 30 team rows + 4 footer rows)

---

## 1. Purpose

The **Team Summary** sheet is a league-wide salary dashboard. It shows:

- **All 30 teams** in a compact table (rows 3–32)
- **Cap/Tax/Apron totals** per team with dead money breakouts
- **Standings info** (wins, losses, win%, conference rank)
- **Cap space, tax overage, apron overage** with league-wide rankings
- **Luxury tax payment** estimates (repeater vs non-repeater)
- **Tax refund projections** at the bottom (total, 50/50 split, per-team share)

This is the "scoreboard" view for salary-cap analysts — at a glance you see which teams are over/under the key thresholds.

---

## 2. Key Inputs / Controls

| Cell | Label | Value/Formula | Purpose |
|------|-------|---------------|---------|
| `B1` | Date | `=TODAY()` | Current date |
| `D1` | Days Left | `=DATE(2026,4,12)-B1+1` | Days remaining in 2025-26 season |
| `E1` | Year | `2025` | Base salary year |
| `G1` | Cap | `='System Values'!G8` | Salary cap level |
| `J1` | Tax | `='System Values'!H8` | Tax level |
| `N1` | Apron 1 | `='System Values'!I8` | First apron level |
| `O1` | Apron 2 | `='System Values'!J8` | Second apron level |

No team selector — this sheet shows all 30 teams simultaneously.

---

## 3. Key Outputs

### Column Structure (Row 2 headers)

| Col | Header | Description |
|-----|--------|-------------|
| A | `Abv.` | Team code (e.g., ATL, BOS) |
| B | `Abv.` | Team code + " - DM" suffix (dead money lookup key) |
| C | `Roster` | Player count from Y warehouse |
| D | `Rk Min` | Rookie minimum charge (fill to 12 roster spots) |
| E | `Vet Min` | Vet minimum charge (fill to 14 roster spots) |
| F | `Tm Salary` | Team cap salary from Y (SUMIF on team code) |
| G | `Dead Money` | Team dead money from Y (SUMIF on "{team} - DM") |
| H | `Total` | F + G (cap salary + dead money) |
| I | `Tx Salary` | Team tax salary from Y column R |
| J | `Dead Money` | Tax dead money |
| K | `Repeater` | "Yes" if repeater tax team, blank otherwise |
| L | `Total` | I + J (tax salary + dead money) |
| M | `Ap Salary` | Team apron salary from Y column Y |
| N | `Dead Money` | Apron dead money |
| O | `Total` | M + N (apron salary + dead money) |
| P | `Conf` | Conference (East/West) |

### Standings Block (columns R–W)

| Col | Header | Description |
|-----|--------|-------------|
| R | `#` | Row number (1–30) |
| S | `Team` | Full team name |
| T | `Wins` | Win count (hardcoded snapshot) |
| U | `Losses` | Loss count (hardcoded snapshot) |
| V | `%` | Win percentage: `=T/(T+U)` |
| W | `Conf` | Conference rank formula |

### Financial Summary Block (columns X–AG)

| Col | Header | Description |
|-----|--------|-------------|
| X | `Cap Space` | `=H - Cap` (negative = over cap) |
| Y | `Roster` | Roster count (duplicate of C) |
| Z | `Rk` | Cap space rank (1 = most space) |
| AA | `+ / - Tax` | `=L - Tax` (negative = under tax) |
| AB | `Tax Payment` | Computed via Tax Array (repeater vs standard) |
| AC | `Rk` | Tax overage rank |
| AD | `+ / - Apron 1` | `=O - Apron1` |
| AE | `Rk` | Apron 1 overage rank |
| AF | `+/- Apron 2` | `=O - Apron2` |
| AG | `Rk` | Apron 2 overage rank |

### Footer Rows (33–36)

| Row | Content |
|-----|---------|
| 33 | `*Repeater` label |
| 34 | `Total:` = sum of all positive tax payments |
| 35 | `Tax Refund Projection:` / `50/50:` = half of total tax |
| 36 | `Share:` = 50/50 amount / count of teams below tax |

---

## 4. Layout / Zones

```
Row 1:     Date | Days Left | Year | Cap | Tax | Apron levels (from System Values)
Row 2:     Column headers
Rows 3-32: One row per team (ATL, BOS, BRK, ... WAS) — 30 teams
Row 33:    "*Repeater" annotation
Row 34:    Tax total
Row 35:    50/50 split
Row 36:    Per-team share for non-tax teams
```

---

## 5. Cross-Sheet Dependencies

### Team Summary reads from:

| Sheet | Reference | Purpose |
|-------|-----------|---------|
| **System Values** | `'System Values'!G8:J8` | Cap, Tax, Apron 1, Apron 2 levels for 2025 |
| **Y** | `Y!C:C` (team column), `Y!D:D` (cap 2025), `Y!R:R` (tax 2025), `Y!Y:Y` (apron 2025) | Salary totals via SUMIF |
| **Y** | `Y!A:C` | Player count via COUNTIF |
| **Minimum Salary Scale** | `'Minimum Salary Scale'!$C$16`, `$C$18` | Rookie min and vet min amounts |
| **Tax Array** | `'Tax Array'!$E$4:$O$200` | Luxury tax bracket calculations |

### What references Team Summary:

- Only **Team Summary itself** (self-references for ranking formulas)
- No external sheets reference Team Summary directly

---

## 6. Key Formulas

### Roster count (C3)
```excel
=COUNTIF(Y!A:C,'Team Summary'!A3)
```
Counts players in Y warehouse matching team code.

### Rookie minimum fill (D3)
```excel
=IF(C3<12,12-C3,0)*('Minimum Salary Scale'!$C$16*($D$1/174))
```
If roster < 12, charge rookie min per empty slot, prorated by days remaining.

### Vet minimum fill (E3)
```excel
=IF(C3<14,14-C3,0)*'Minimum Salary Scale'!$C$18*($D$1/174)
```
Same logic for slots 12–14, vet minimum salary.

### Team cap salary (F3)
```excel
=SUMIF(Y!C:C,A3,Y!D:D)
```
Sum of Y column D (2025 cap salary) where team = A3.

### Dead money (G3)
```excel
=SUMIF(Y!C:C,B3,Y!D:D)
```
Sum of Y column D where team = "{team} - DM" (dead money rows in Y use this suffix).

### Total cap (H3)
```excel
=F3+G3
```

### Tax salary + dead money (I3, J3, L3)
```excel
I3: =SUMIF(Y!C:C,A3,Y!R:R)
J3: =SUMIF(Y!C:C,B3,Y!R:R)
L3: =I3+J3
```

### Apron salary + dead money (M3, N3, O3)
```excel
M3: =SUMIF(Y!C:C,A3,Y!Y:Y)
N3: =SUMIF(Y!C:C,B3,Y!Y:Y)
O3: =N3+M3
```

### Cap space (X3)
```excel
=H3-$G$1
```
Negative means over cap.

### Tax overage (AA3)
```excel
=L3-$J$1
```
Positive means over tax threshold.

### Tax payment (AB3)
```excel
=IF(
  K3="Yes",
  SUMPRODUCT(
    (AA3>'Tax Array'!$M$4:$M$200)*
    ('Tax Array'!$K$4:$K$200=$E$1)*
    (AA3-'Tax Array'!$M$4:$M$200)*
    ('Tax Array'!$O$4:$O$200)
  ),
  SUMPRODUCT(
    (AA3>'Tax Array'!$G$4:$G$200)*
    ('Tax Array'!$E$4:$E$200=$E$1)*
    (AA3-'Tax Array'!$G$4:$G$200)*
    ('Tax Array'!$I$4:$I$200)
  )
)
```
Uses repeater brackets (M/O columns) if K3="Yes", otherwise standard brackets (G/I columns).

### Rank formulas (Z3, AC3, AE3, AG3)
```excel
=COUNT($X$3:$X$32) + 1 - _xlfn.RANK.EQ(X3, $X$3:$X$32)
```
Rank among all 30 teams (1 = highest value).

### Conference rank (W3)
```excel
=1+COUNTIFS($P:$P,$P3,$V:$V,">"&$V3) + (COUNTIFS($P:$P,$P3,$V:$V,$V3)-1)/2
```
Rank by win% within conference, with tie-breaking.

### Tax refund projections (rows 34–36)
```excel
AB34: =SUMIF(AB3:AB32,">0")      -- Total tax payments
AB35: =AB34/2                    -- 50/50 split
AB36: =AB35/COUNTIF(AB3:AB32,"<1")  -- Per-team share (teams under tax)
```

---

## 7. Data Values

### Repeater teams (K column, "Yes" values in sample data)
- BOS, DEN, GSW, LAC, LAL, MIL, PHO, SAS

### Conference assignments (P column)
- **East**: ATL, BOS, BRK, CHA, CHI, CLE, DET, IND, MIA, MIL, NYK, ORL, PHI, TOR, WAS
- **West**: DAL, DEN, GSW, HOU, LAC, LAL, MEM, MIN, NOR, OKC, PHO, POR, SAC, SAS, UTA

---

## 8. Mapping to Postgres

| Team Summary Concept | Our Table(s) | Notes |
|----------------------|--------------|-------|
| Team cap/tax/apron totals | `pcms.team_salary_warehouse` | Columns: `cap_2025`, `tax_2025`, `apron_2025` |
| Dead money by team | `pcms.dead_money_warehouse` | Aggregate by team_code |
| Cap/Tax/Apron levels | `pcms.league_system_values` | Columns: `salary_cap`, `tax_level`, `apron_1`, `apron_2` |
| Roster count | `pcms.salary_book_warehouse` | `COUNT(*) WHERE team_code = ?` |
| Minimum salary fill | TODO | Requires a minimum-salary scale by YOS (Sean references `minimum_salary_scale.json`) |
| Repeater status | `pcms.teams` or computed | Need 3-year tax history |
| Tax bracket calc | `pcms.league_tax_rates` + `pcms.tax_team_status` | Compute from over-tax amount + repeater flag |
| Standings (wins/losses) | **Not in PCMS** | Would come from NBA Stats API |
| Conference | `pcms.teams.conference` | |

### Coverage assessment

- ✅ Team salary totals (cap/tax/apron) — `team_salary_warehouse`
- ✅ Dead money breakout — `dead_money_warehouse`
- ✅ CBA constants — `league_system_values`
- ⚠️ Repeater flag — need to derive from tax payment history
- ⚠️ Tax payment calculation — need tax bracket table or function
- ❌ Standings data — not in PCMS (NBA Stats API)

---

## 9. Open Questions / TODO

1. **Roster count logic**: The formula `COUNTIF(Y!A:C,team)` searches columns A:C for the team code. Column C is the team column in Y. Verify our roster count matches.

2. **Days remaining proration**: The `$D$1/174` factor prorates minimum fills by days left in season. The 174 constant is presumably the total season days. Verify this is correct for 2025-26.

3. **Repeater status source**: Currently hardcoded ("Yes" in column K). Need to compute from 3-year tax payment history or add to `pcms.teams`.

4. **Tax bracket parity**: The SUMPRODUCT pattern uses Tax Array columns E–I (standard) and K–O (repeater). Need to verify our tax calculation matches.

5. **Dead money suffix convention**: Y warehouse uses "{team} - DM" rows for dead money. Our `dead_money_warehouse` uses separate rows — aggregation should match.

6. **Standings integration**: This sheet includes wins/losses/rank which don't exist in PCMS. If we replicate this dashboard, we'd need to join standings from another source.

---

## 10. Summary

Team Summary is a **league-wide salary scoreboard** — one row per team with:

- Cap/Tax/Apron salary totals (from Y)
- Dead money breakouts
- Room/overage vs each threshold
- Tax payment estimates
- Rankings across the league

Our `pcms.team_salary_warehouse` is the direct analog for the salary totals. The main gaps are:

- **Tax payment calculation** (need bracket logic)
- **Repeater status** (need historical derivation)
- **Standings** (not in PCMS)

For salary-cap tooling, this sheet answers "who's over the tax?" and "what's the league-wide tax bill?" — useful for trade deadline context.
