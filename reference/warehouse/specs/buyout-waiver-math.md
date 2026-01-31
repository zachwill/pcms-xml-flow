# Buyout & Waiver Scenario Math

**Consolidated from:** `buyout_calculator.json`, `kuzma_buyout.json`, `set-off.json`  
**Purpose:** Document the core CBA rules and formulas for buyout/waiver/stretch scenarios.

---

## 1. Core Constants

| Constant | Value | Source | Notes |
|----------|-------|--------|-------|
| **Regular season days** | `174` | CBA (not in system_values) | Used for pro-rata salary calculations |
| **Waiver clearance period** | `+2 days` | CBA | 48-hour waiver clearance rule |

**Evidence:**
```excel
-- buyout_calculator row 4
C4: =C3+2                 -- clears waivers = waive_date + 2

-- buyout_calculator row 6  
C6: =174-C5               -- days_remaining = 174 - day_of_season
```

---

## 2. Day-of-Season Calculation

```
season_start   = 2025-10-20  (CBA season opener)
waive_date     = user input
clears_waivers = waive_date + 2
day_of_season  = clears_waivers - season_start
days_remaining = 174 - day_of_season
```

**Evidence (buyout_calculator rows 2–6):**
```excel
C2: 2025-10-20 00:00:00   -- season start
C3: 2026-01-15 00:00:00   -- date waived (input)
C4: =C3+2                 -- clears waivers
C5: =C4-C2                -- day of season
C6: =174-C5               -- days remaining
```

---

## 3. Pro-Rata Salary (Current Season)

When a player is waived mid-season, their remaining guaranteed salary for the current season is prorated:

```
guaranteed_remaining_current_year = (days_remaining / 174) × cap_salary_current_year
```

**Evidence (buyout_calculator row 17):**
```excel
B17: =(C6/174)*B11        -- pro-rata current year
C17: =C11                 -- future years are fully guaranteed
D17: =D11                 -- (no proration)
```

---

## 4. The $600,000 Adjustment (kuzma_buyout)

**Formula (kuzma_buyout row 17):**
```excel
B17: =((C6/174)*B11)-600000
```

This subtracts $600,000 from the prorated guaranteed amount. The likely explanation:

1. **Guarantee protection threshold**: Some contracts have partial guarantees where a specific dollar amount becomes non-guaranteed if waived before a certain date.

2. **Kuzma's contract specifics**: Looking at his contract data:
   - Y warehouse cap_2025: `22,410,605`
   - kuzma_buyout B11: `21,477,272`
   - Difference: `933,333` (≈ $600K + $333K trade kicker)

3. **Possible interpretation**: The $600K represents a protection threshold where that portion of his guarantee was waivable (i.e., team doesn't owe it if waived before a specific date).

**Status:** ⚠️ Not fully confirmed — this appears to be contract-specific and may relate to partial guarantee terms in `pcms.contract_protections`.

---

## 5. Trade Kicker in Buyouts

When a player with a trade kicker is traded and then waived by the acquiring team, the trade kicker affects the dead money:

**Evidence (kuzma_buyout):**
```excel
-- Row 11: Kuzma's cap salary (base + trade kicker for trade comparison)
N11: =B11+333333                    -- cap salary + TK

-- Row 29: Buyout amounts (dead money) include trade kicker
B29: =B11-B26+333333                -- current year buyout + TK
C29: =C17-C26+333333                -- future year buyout + TK
```

The `+333333` is hardcoded in this example. For general calculation:
- Trade kicker % comes from `contract_versions.trade_bonus_percent`
- Amount = `cap_salary × trade_bonus_percent / 100`

---

## 6. Buyout Amount (Give-Back) Allocation

The "give back" is the amount the player concedes (waives) to facilitate the buyout.

**Allocation formula:**
1. Compute pro-rata percentages for each year
2. Apply give-back proportionally

```excel
-- Row 18: Pro-rata percentages
B18: =B17/(B17+C17)               -- current year's share
C18: =1-B18                       -- remaining year's share

-- Row 26: Give-back allocation
B26: =B18*F26                     -- give-back × current year %
C26: =C18*F26                     -- give-back × future year %
     -- where F26 = total give-back amount

-- Row 29: Final buyout (dead money = salary − give-back)
B29: =B11-B26                     -- current year dead money
C29: =C17-C26                     -- future year dead money
```

---

## 7. Stretch Provision

The CBA allows teams to "stretch" dead money over a longer period:

**Formula:**
```
stretch_years = (2 × remaining_contract_years) + 1
annual_stretch = total_dead_money / stretch_years
```

**Examples:**
| Remaining Years | Stretch Years | Formula |
|-----------------|---------------|---------|
| 1 | 3 | 2×1+1=3 |
| 2 | 5 | 2×2+1=5 |
| 3 | 7 | 2×3+1=7 |

**Evidence:**

*kuzma_buyout (1 remaining year after current):*
```excel
C32: =C29/3                       -- stretch over 3 years
```
Kuzma has 2026 remaining → 2×1+1=3

*set-off (2 remaining years):*
```excel
-- Row 8: Lillard stretch (2 years remaining: 2025 + 2026)
B8: =$D$4/COUNTIF($B$7:$F$7,">1")  -- total ÷ 5 years
```
Lillard has 2025+2026 remaining → 2×2+1=5

---

## 8. Set-Off (When Waived Player Signs Elsewhere)

The CBA reduces dead money when a waived player signs a new contract:

**Set-off formula:**
```
setoff_per_year = (new_salary − minimum_salary) / 2
```

**Evidence (set-off.json row 27):**
```excel
B27: =(B12-B23)/2                 -- (new_salary − 1_YOS_min) / 2
```

**Set-off allocation over stretch years:**
- Year 1 set-off is spread over all remaining stretch years
- Year 2 set-off is spread over remaining stretch years after year 1

```excel
-- Row 31: Year 1 set-off spread over 5 years
B31: =B27/5
C31: =B31
D31: =B31
E31: =B31
F31: =B31

-- Row 32: Year 2 set-off spread over 4 years
B32: "-"                          -- N/A for year 1
C32: =C27/4
D32: =C32
E32: =C32
F32: =C32
```

**Final dead money = pre-set-off amount − set-off allocations:**
```excel
B36: =B8-B31
C36: =C8-C31-C32
D36: =D8-D31-D32
...
```

---

## 9. Trade Comparison (Cash Responsibility)

For mid-season trades, each team is responsible for salary based on days:

```
days_responsible = trade_date - season_start
days_left = 174 - days_responsible

true_earned = cap_salary - true_left
true_left = (days_left / 174) × cap_salary
```

**Evidence (kuzma_buyout columns H–K):**
```excel
J6: =J5-J4                        -- days responsible
J7: =174-J6                       -- days left

K11: =(J7/174)*I11                -- Grant: true left
J11: =I11-K11                     -- Grant: true earned
```

---

## 10. Mapping to Postgres

| Sean Concept | Our Table/Function | Status |
|--------------|-------------------|--------|
| Player cap salary by year | `pcms.salary_book_yearly.cap_amount` | ✅ |
| Minimum salary by YOS | `pcms.league_salary_scales.minimum_salary_amount` | ✅ |
| Contract protections | `pcms.contract_protections` or `pcms.contract_amounts` | ✅ (partial) |
| Trade kicker % | `pcms.contract_versions.trade_bonus_percent` | ✅ |
| 174-day season constant | — | ❌ Not stored (hardcode) |
| Dead money (historical) | `pcms.dead_money_warehouse` | ✅ |
| Buyout scenario calculator | — | ❌ Not implemented |
| Stretch provision function | — | ❌ Not implemented |
| Set-off calculation | — | ❌ Not implemented |

---

## 11. Proposed Functions

### `fn_buyout_scenario(player_id, waive_date, give_back)`

Returns:
- `days_remaining`
- `guaranteed_remaining` (per year)
- `buyout_amount` (per year)
- `dead_money` (per year)

### `fn_stretch_waiver(total_dead_money, remaining_years)`

Returns:
- `stretch_years` = 2 × remaining_years + 1
- `annual_amount` = total_dead_money / stretch_years

### `fn_setoff_scenario(new_salary, minimum_salary, stretch_years)`

Returns:
- `setoff_per_year` = (new_salary − minimum_salary) / 2
- `annual_setoff` per stretch year

---

## 12. Open Questions

- [ ] **$600K adjustment**: Need to confirm if this is a protection threshold specific to Kuzma's contract, or a general CBA rule.
- [ ] **YOS for minimum**: Set-off uses 1-YOS minimum as baseline — confirm this is always the case regardless of player's actual YOS.
- [ ] **Trade kicker timing**: Does the trade kicker apply if player is waived same day as trade, or only after clearance?
- [ ] **Season start date**: Should we store this in `pcms.league_system_values` for flexibility?
