# Kuzma Buyout Spec

**Source:** `reference/warehouse/kuzma_buyout.json`  
**Related:** `buyout_calculator.json` (simpler base template)

---

## 1. Purpose

Extended buyout scenario calculator with **trade kicker handling** and **multi-player trade comparison**. This is a clone of `buyout_calculator.json` customized for Kyle Kuzma's specific buyout scenario when traded to Portland.

Key additions over base template:
- Trade kicker (+$333,333) added to cap salary adjustments
- Side-by-side trade comparison (Jerami Grant vs Kuzma + Portis)
- Stretch provision calculation (dead money ÷ 3 years)
- Minimum salary reference for 8 vs 9 YOS

---

## 2. Key Inputs / Controls

### Main buyout section (columns B–F)

| Cell | Label | Example Value |
|------|-------|---------------|
| B1 | **Player name** (lookup key into Y) | `"Kuzma, Kyle"` |
| D1 | Scenario note | `"(if traded to Portland)"` |
| C2 | **Season Start** date | `2025-10-20` |
| C3 | **Date Waived** | `2026-01-15` |
| C21 | **Give Back** (linked to C34 = 9 YOS min) | `=C34` (3,546,312) |

### Trade comparison section (columns H–P)

| Cell | Label | Value |
|------|-------|-------|
| J4 | Season Start | `2025-10-20` |
| J5 | Date of Trade | `2026-01-20` |
| H11/I11 | Grant, Jerami cap salary | `32,000,001` |
| M11/N11 | Kuzma, Kyle cap salary (base + TK) | `=B11+333333` |
| M12/N12 | Portis, Bobby cap salary | `13,445,754` |

---

## 3. Key Outputs

| Row | Columns | Description |
|-----|---------|-------------|
| 6 | C | **Days Remaining** (174 - day of season) |
| 11 | B–F | **Current Salary** by year (2025–2028 + Total) |
| 11–13 | H–K | **Grant trade scenario**: cap salary, true earned, true left |
| 11–13 | M–P | **Kuzma+Portis trade scenario**: same breakdown |
| 14 | K | **Cash Saved** = Kuzma+Portis left − Grant left |
| 17 | B–F | **Guaranteed Amount Remaining** (pro-rata for current year) |
| 29 | B–F | **Buyout Amounts** (cap salary − give-back + trade kicker) |
| 32 | C | **Stretch Amount** = C29/3 |
| 33–34 | C | Minimum salary: 8 YOS / 9 YOS reference values |

---

## 4. Layout / Zones

```
ZONE 1: Main Buyout Calculator (B–F)
  Row 1     : Player name + scenario note
  Row 2-6   : Date inputs + day calculations
  Row 8-11  : Current Salary (pulls from Y for 2027-2028)
  Row 14-18 : Guaranteed Amount Remaining + pro-rata %
  Row 21    : Give Back input
  Row 23-29 : Buyout math
  Row 30    : Final dead money label
  Row 32-35 : Stretch provision + min salary references

ZONE 2: Trade Comparison (H–K) — Jerami Grant
  Row 4-7   : Trade date inputs + days calc
  Row 10-13 : Grant salary breakdown (earned/left)

ZONE 3: Trade Comparison (M–P) — Kuzma + Portis
  Row 9-13  : Kuzma + Portis salaries (Base + TK column vs Base column)
  Row 13-14 : Totals + Cash Saved comparison
```

---

## 5. Cross-Sheet Dependencies

### References Y (Y Warehouse)

Future-year salaries (D11, E11) are looked up from Y:

```excel
=IFERROR(
  _xlfn.LET(
    _xlpm.r, MATCH(B1, Y!$B:$B, 0),           -- find player row by name
    _xlpm.c, MATCH($D$10, Y!$D$2:$J$2, 0),    -- find year column (2027)
    _xlpm.v, INDEX(Y!$D:$J, _xlpm.r, _xlpm.c),
    IF(_xlpm.v="-", 0, _xlpm.v)
  ),
0)
```

### Referenced by

No other sheets reference this (standalone scenario worksheet).

---

## 6. Key Formulas / Logic

### Day calculations
```excel
C4: =C3+2                 -- clears waivers (48-hour rule)
C5: =C4-C2                -- day of season
C6: =174-C5               -- days remaining
```

### Trade scenario: days left for each side
```excel
J6: =J5-J4                -- days responsible (Date of Trade - Season Start)
J7: =174-J6               -- days left for acquiring team
```

### Pro-rata current-year guaranteed amount (with $600K adjustment)
```excel
B17: =((C6/174)*B11)-600000   -- Note: $600K subtracted (possibly guarantee threshold)
```

### Pro-rata percentage
```excel
B18: =B17/(B17+C17)       -- current year share
C18: =1-B18               -- future year share
```

### Give-back allocation
```excel
B26: =B27*C21             -- give-back × pro-rata % (B27 = B18)
C26: =C27*C21
```

### Buyout amount with trade kicker
```excel
B29: =B11-B26+333333      -- cap salary − buyout + TK
C29: =C17-C26+333333      -- guaranteed remaining − give-back + TK
```

The `+333333` is the trade kicker that must be added to the cap salary calculation.

### Trade comparison: true earned vs true left
```excel
K11: =(J7/174)*I11        -- Grant: true left (days left fraction × salary)
J11: =I11-K11             -- Grant: true earned

P11: =(J7/174)*(N11-333333)   -- Kuzma: true left (excluding trade kicker from base)
O11: =(N11-333333)-P11        -- Kuzma: true earned
```

### Cash saved (trade comparison result)
```excel
K14: =P13-K13             -- total true left (Kuzma+Portis) − total true left (Grant)
```

### Stretch provision
```excel
C32: =C29/3               -- dead money stretched over 3 years
C35: =C29/3               -- same formula (duplicate display)
```

---

## 7. Mapping to Postgres

| Sean Concept | Our Table / Function |
|--------------|----------------------|
| Player cap salary by year | `pcms.salary_book_warehouse` (`cap_20xx`) |
| Trade kicker | `pcms.salary_book_warehouse.trade_kicker_pct`, `pcms.contract_versions.trade_bonus_percent` |
| Minimum salary by YOS | `pcms.league_salary_scales` (minimum_salary_amount) |
| Waiver/dead money | `pcms.dead_money_warehouse` (historical only) |

### Gaps for tooling parity

- **No buyout scenario API** — this is analyst scratchpad
- **Trade comparison** logic (days responsible / cash saved) is not modeled
- **Stretch provision** calculation (÷ years) not in our functions
- **$600K adjustment** in B17 — unclear CBA rule (possibly guarantee protection threshold)

---

## 8. Open Questions / TODO

- [ ] What is the $600,000 subtracted in B17? Likely a protection/guarantee rule.
- [ ] The `+333333` trade kicker amount appears hardcoded — is this Kuzma-specific or a general formula?
- [ ] Stretch provision years (3) — CBA rule: `2 × remaining years + 1`
- [ ] Trade comparison section is scenario-specific (Grant vs Kuzma+Portis trade) — useful as template for `fn_trade_cash_comparison()`?
