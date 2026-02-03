# Example: Buyout Calculator

This is a **template-style scenario worksheet** (an analyst scratchpad). Canonical waiver/buyout/stretches logic is documented in **[buyout-waiver-math.md](buyout-waiver-math.md)**.

**Source:** `reference/warehouse/buyout_calculator.json`  
**Related:** `kuzma_buyout.json` (extended example with trade kicker + stretch)

---

## 1. Purpose

Interactive scenario calculator for **player buyouts**. Given a player, waiver date, and "give back" amount, computes:
- Pro-rata remaining salary obligations
- Buyout amounts per year
- Final cap salary post-waivers (dead money)

Used for quick "what if we waived X on date Y" analysis.

---

## 2. Key Inputs / Controls

| Cell | Label | Example Value |
|------|-------|---------------|
| B1 | **Player name** (lookup key into Y) | `"Young, Trae"` |
| C2 | **Season Start** date | `2025-10-20` |
| C3 | **Date Waived** | `2026-01-15` |
| C21 | **Give Back** (player concession) | `9000000` |

---

## 3. Key Outputs

| Row | Description |
|-----|-------------|
| 11 | **Current Cap Salary** — multi-year (2025–2028 + Total) |
| 17 | **Guaranteed Amount Remaining** per year (pro-rata for current season) |
| 24–26 | **Remaining Salary** breakdown after buyout |
| 29 | **Buyout Amounts** — cap salary reduction per year |
| 30 | **Cap Salary Post Waivers** — dead money that remains on books |
| 32–33 | Hard-coded minimum salary values (context for signing post-buyout) |

---

## 4. Layout / Zones

```
Row 1     : Player name (input)
Row 2-6   : Date inputs + computed day-of-season / days-remaining
Row 8-11  : Current Cap Salary section (pulls from Y warehouse)
Row 14-18 : Guaranteed Amount Remaining + pro-rata %
Row 21    : Give Back input
Row 23-29 : Buyout math (remaining salary vs buyout amounts)
Row 30    : Final dead money label
Row 32-33 : Reference min salaries
```

Only columns B–F are used (compact single-player calculator).

---

## 5. Cross-Sheet Dependencies

### References Y (Y Warehouse)
Row 11 uses `LET/MATCH/INDEX` to pull cap salaries from the Y warehouse:

```excel
=IFERROR(
  _xlfn.LET(
    _xlpm.r, MATCH(B1, Y!$B:$B, 0),           -- find player row
    _xlpm.c, MATCH($B$10, Y!$D$2:$J$2, 0),    -- find year column
    _xlpm.v, INDEX(Y!$D:$J, _xlpm.r, _xlpm.c),
    IF(_xlpm.v="-", 0, _xlpm.v)
  ),
0)
```

### Referenced by
No other sheets reference this calculator (standalone scenario tool).

---

## 6. Key Formulas / Logic

### Days remaining in season
```excel
C4: =C3+2                 -- clears waivers (48-hour rule)
C5: =C4-C2                -- day of season (from start)
C6: =174-C5               -- days remaining (174-day regular season)
```

### Pro-rata current-year guaranteed amount
```excel
B17: =(C6/174)*B11        -- remaining days fraction × salary
```

### Pro-rata percentage split
```excel
B18: =B17/F17             -- current year's share of total remaining
C18: =C17/F17             -- future year's share
```

### Give-back allocation across years
```excel
B26: =B18*F26             -- give-back × pro-rata %
C26: =C18*F26             -- (F26 = C21 = total give-back)
```

### Buyout amount (dead money savings)
```excel
B29: =B11-B26             -- original cap salary − buyout portion
C29: =C17-C26             -- guaranteed remaining − give-back
```

The remaining cap hit (dead money) is computed row 29.

---

## 7. Mapping to Postgres

| Sean Concept | Our Table / Function |
|--------------|----------------------|
| Player cap salary by year | `pcms.salary_book_warehouse` (`cap_20xx`) or `pcms.salary_book_yearly` |
| Season calendar (174 days) | Hardcoded constant (could be in `pcms.league_system_values`) |
| Waiver/dead money | `pcms.dead_money_warehouse` (for historical; not scenario) |

### Missing for tooling parity
- **No buyout scenario calculator** in our Postgres model—this is purely an analyst worksheet.
- If we build a buyout API, we'd need:
  - `fn_buyout_scenario(player_id, waive_date, give_back)` returning pro-rata dead money

---

## 8. Extended Example: Kuzma Buyout

`kuzma_buyout.json` extends the base calculator with:
- **Trade kicker handling**: adds $333,333 to cap salary adjustments (row 29)
- **Trade comparison**: columns H–P compare two trades (Jerami Grant vs Kyle Kuzma + Bobby Portis)
- **Stretch provision**: row 32 computes `=C29/3` (stretch dead money over 3 years)
- Minimum salary lookup for 8 YOS vs 9 YOS (rows 33–34)

This shows the calculator is a template that analysts clone/customize for specific scenarios.

---

## 9. Open Questions / TODO

- [ ] Should we provide a `fn_buyout_scenario()` function for API use?
- [ ] Hardcoded `174` (regular season days) — confirm CBA source for this constant
- [ ] Stretch provision logic (divide by N years) could be a separate `fn_stretch_waiver()`
