# Example: Set-Off (waiver + stretch)

This is a **worked example** of the CBA set-off rule on a stretched contract. Canonical waiver/buyout/stretches logic is documented in **[buyout-waiver-math.md](buyout-waiver-math.md)**.

**Source:** `reference/warehouse/set-off.json`  
**Related:** `buyout_calculator.json`, `kuzma_buyout.json` (other waiver/stretch tools)

---

## 1. Purpose

Calculator for **waiver set-off** scenarios when a player is waived and signs with a new team. Demonstrates the CBA rule where the waiving team's dead money obligation is reduced by half of the player's new salary (minus the minimum).

This specific sheet models a **Damian Lillard stretch scenario** where:
- Milwaukee waives Lillard and stretches his guaranteed salary over 5 years
- Lillard signs a new contract with Portland (MLE-level)
- Milwaukee receives "set-off" credit: half of `(new_salary − minimum)` reduces their dead money

---

## 2. Key Inputs / Controls

### Unearned Base Compensation (Row 4)
| Cell | Label | Value |
|------|-------|-------|
| B4 | 2025 remaining salary | `54,126,450` |
| C4 | 2026 remaining salary | `58,456,566` |
| D4 | Total | `=SUM(B4:C4)` |

### Contract Offer (New Team — Portland)
| Cell | Label | Value |
|------|-------|-------|
| B12 | Year 1 salary | `14,104,000` (MLE) |
| C13 | Year 2 multiplier | `0.95` (5% decline) |
| D13 | Year 3 multiplier | `1.00` (player option) |

### 1 YOS Minimum Reference
| Cell | Label | Value |
|------|-------|-------|
| B23 | 2025 1-YOS minimum | `2,048,494` |
| C23 | 2026 (same) | `=B23` |

---

## 3. Key Outputs

| Row | Section | Description |
|-----|---------|-------------|
| 8 | **Stretched Amounts (Pre Set-Off)** | Total ÷ 5 years = flat amount per year |
| 27 | **Set-Off Amounts (Totals)** | `(new_salary − minimum) / 2` per contract year |
| 31–32 | **Set-Off Amounts (Annual)** | Totals spread evenly over stretch years |
| 36 | **Milwaukee New Stretch Amounts** | Pre-set-off − annual set-off |
| 40 | **Milwaukee Savings** | Pre vs Post set-off totals |
| 44–45 | **Lillard Totals** | Summary: Milwaukee dead money + Portland contract |

---

## 4. Layout / Zones

```
ZONE 1: Unearned Base Compensation (Rows 1–4)
  Row 1   : Title "LILLARD STRETCH"
  Row 2-3 : Header ("Unearned Base Compensations", years)
  Row 4   : Raw remaining guaranteed amounts

ZONE 2: Stretched Amounts Pre Set-Off (Rows 6–8)
  Row 7   : Years 2025–2029 (5 stretch years)
  Row 8   : =Total/5 per year

ZONE 3: Contract Offer (Rows 10–19)
  Row 11-12 : New contract salary by year
  Row 13-14 : Multipliers + labels (MLE, decline, opt-P)
  Row 15-19 : Alternative "Comp" scenario (5% raise instead of decline)

ZONE 4: 1 YOS Minimum (Rows 21–23)
  Row 23  : Minimum salary baseline for set-off calc

ZONE 5: Set-Off Amounts (Rows 25–32)
  Row 27  : Set-off totals per contract year
  Row 31-32 : Annual set-off spread over stretch years

ZONE 6: Milwaukee New Stretch (Rows 34–36)
  Row 36  : Final dead money amounts per year

ZONE 7: Savings Summary (Rows 38–40)
  Row 40  : Pre/Post comparison + total savings

ZONE 8: Lillard Totals (Rows 42–45)
  Row 44  : Milwaukee's final cap hit by year
  Row 45  : Portland's contract payments
```

---

## 5. Cross-Sheet Dependencies

### References
None — this is a **standalone scenario calculator**. All inputs are hardcoded values (not looked up from Y or other warehouses).

### Referenced by
No other sheets reference this calculator.

---

## 6. Key Formulas / Logic

### Stretched amount (pre set-off)
```excel
B8: =$D$4/COUNTIF($B$7:$F$7,">1")
```
Divides total unearned compensation evenly across 5 stretch years.  
Result: `112,583,016 / 5 = 22,516,603.2` per year.

### Set-off total per contract year
```excel
B27: =(B12-B23)/2       -- (new_salary − minimum) / 2
C27: =(C12-C23)/2       -- same for year 2
D27: "-"                -- no contract year 3 (player option)
```
This is the CBA set-off rule: waiving team gets credit for half of (new salary − minimum).

### Set-off annual allocation
Year 1 set-off is spread over 5 stretch years:
```excel
B31: =B27/5             -- Year 1 set-off ÷ 5 years
C31: =B31               -- same amount each year
D31: =B31
E31: =B31
F31: =B31
```

Year 2 set-off is spread over 4 remaining years:
```excel
B32: "-"                -- N/A for year 1 (contract starts in 2025)
C32: =C27/4             -- Year 2 set-off ÷ 4 years
D32: =C32
E32: =C32
F32: =C32
```

### Final stretch amounts (post set-off)
```excel
B36: =B8-B31                    -- 2025: pre-set-off − year1 allocation
C36: =C8-C31-C32                -- 2026+: minus both allocations
D36: =D8-D31-D32
E36: =E8-E31-E32
F36: =F8-F31-F32
```

### Savings calculation
```excel
B40: =SUM(D4)                   -- Total pre set-off
C40: =SUM(B36:F36)              -- Total post set-off
D40: =C40-B40                   -- Savings (negative = money saved)
```

### Lillard totals summary
```excel
C44: =B36                       -- Milwaukee 2025 = final stretch amount
H44: =SUM(C44:G44)              -- Milwaukee total
C45: =B12                       -- Portland 2025 = new contract Y1
H45: =SUM(C45:G45)              -- Portland total
I44: =H44                       -- Net (Milwaukee)
I45: =H45                       -- Net (Portland)
J44: =I44+I45                   -- Combined net
```

---

## 7. CBA Set-Off Rule Summary

The **set-off provision** (CBA Article VII.4.b) reduces a team's dead money when a waived player signs elsewhere:

1. **Set-off amount** = `(new_salary − applicable_minimum) / 2`
2. Applied only for years where the **new contract overlaps** the waived contract
3. The **set-off is spread** over the remaining stretch years

In this example:
- Lillard's new contract (Portland): $14.1M in 2025, declining to ~$13.4M in 2026
- 1-YOS minimum used as baseline: $2.05M
- Year 1 set-off: `(14,104,000 − 2,048,494) / 2 = 6,027,753`
- Spread over 5 stretch years: `~1,205,551/year`

---

## 8. Mapping to Postgres

| Sean Concept | Our Table / Function |
|--------------|----------------------|
| Player guaranteed salary | `pcms.salary_book_warehouse` (`cap_20xx`) |
| Minimum salary by YOS | `pcms.league_salary_scales` (`minimum_salary_amount`) |
| Stretch provision | Not currently modeled |
| Set-off calculation | Not currently modeled |

### Missing for tooling parity

- **No set-off scenario calculator** — this is analyst scratchpad math
- **No stretch provision function** — would need `fn_stretch_waiver(remaining_salary, years_remaining)`
- **Set-off logic** is complex: depends on new contract terms + overlap with waived years

---

## 9. Open Questions / TODO

- [ ] Confirm the "1 YOS minimum" is always used for set-off calculations (or does player's actual YOS matter?)
- [ ] The sheet shows two contract scenarios (5% decline vs 5% raise) — which is authoritative?
- [ ] Stretch years = 5 (for 2 remaining years: `2 × 2 + 1 = 5`) — confirm CBA formula
- [ ] Should we build `fn_setoff_scenario()` for trade/waiver planning tools?
