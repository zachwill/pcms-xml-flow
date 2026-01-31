# minimum_salary_scale.json

**Status:** Spec complete  
**Source:** `reference/warehouse/minimum_salary_scale.json`

---

## 1. Purpose

Provides the **NBA minimum salary scale** by **years of service (YOS)** and **season**, plus derived amounts for Second Round Pick (SRP) contracts and veteran minimums. Used as a lookup table for contract calculators and team salary modeling.

---

## 2. Key Inputs / Controls

No user-editable cells. All values are either:
- Hardcoded CBA constants (rows 16–37 for 2025–2026 seasons)
- Formula-derived for future years (rows 38+ projecting from salary cap)

Key input factors:
- **Season** (col A): 2025–2031
- **YOS** (col B): 0–10 years of service
- **Year 1 % Cap** (col H): Fixed % of salary cap per YOS tier (e.g., 0.823% for YOS=0)

---

## 3. Key Outputs

### Zone A: Main Minimum Scale Table (A:H, rows 15–92)

| Column | Header | Purpose |
|--------|--------|---------|
| A | Season | Salary year (2025–2031) |
| B | YOS | Years of service (0–10) |
| C | Year 1 | Minimum salary for contract year 1 |
| D | Year 2 | Minimum salary for contract year 2 |
| E | Year 3 | Minimum salary for contract year 3 |
| F | Year 4 | Minimum salary for contract year 4 |
| G | Year 5 | Minimum salary for contract year 5 |
| H | Year 1 % Cap | Fixed % of cap for this YOS tier |

**Structure:** 11 rows per season (YOS 0–10) × 7 seasons = 77 data rows (rows 16–92).

### Zone B: Salary Cap Reference (A:B, rows 5–12)

Small lookup table pulling salary cap from `SystemValues` by season.

```
Row 6:  A=2025  B=INDEX(SystemValues[[#Data],[Salary Cap]], MATCH(...))
...
Row 12: A=2031  B=...
```

### Zone C: SRP & Vet Min Quick Reference (L:Q, rows 12–36)

Summarized minimums for common contract types:
- **SRP 2025–2030** (rows 16–21): Second round pick scale (YOS=0) years 1–4
- **Vet Min 2025–2031** (rows 23–29): Veteran minimum (YOS=2) year 1
- **Rookie Min 2025–2031** (rows 30–36): Rookie minimum (YOS=0) year 1

---

## 4. Layout / Zones

| Zone | Rows | Cols | Content |
|------|------|------|---------|
| Title | 1 | A | "Minimum Salary Scale" |
| Cap reference header | 3,5 | A:B | Salary Cap Amounts lookup |
| Cap reference data | 6–12 | A:B | Season → Salary Cap (from SystemValues) |
| Main scale header | 15 | A:H | Column headers for Minimum table |
| Main scale data | 16–92 | A:H | Season × YOS → Year 1–5 minimums |
| SRP/VetMin header | 12 | L | "Vet Mins & SRP Amounts" |
| SRP/VetMin data | 15–36 | L:Q | Quick reference lookups |

---

## 5. Cross-Sheet Dependencies

### References FROM this sheet (outbound):
- **`SystemValues` table** (from `system_values.json`):
  - `CapAmounts` zone (rows 6–12) pulls `Salary Cap` via `INDEX(...MATCH...)` 

### References TO this sheet (inbound):
- **`team_summary.json`** — roster minimum salary charges:
  ```excel
  =IF(C3<12,12-C3,0)*('Minimum Salary Scale'!$C$16*($D$1/174))
  =IF(C3<14,14-C3,0)*'Minimum Salary Scale'!$C$18*($D$1/174)
  ```
  Uses YOS=0 and YOS=2 minimums for incomplete roster charges.

---

## 6. Key Formulas / Logic Patterns

### Year 1 minimum (projected seasons 2027+):
```excel
C38: =ROUND((_xlfn.XLOOKUP(Minimum[[#This Row],[Season]], 
             CapAmounts[Season], CapAmounts[Salary Cap])
             *Minimum[[#This Row],[Year 1 % Cap]]),0)
```
→ Year 1 = Salary Cap × fixed % for YOS tier

### Year 2–5 raises (standard CBA escalators):
```excel
D39: =ROUND(Minimum[[#This Row],[Year 1]]*1.05,0)   -- Year 2: +5% over Y1
E40: =ROUND(Minimum[[#This Row],[Year 2]]*1.047,0)  -- Year 3: +4.7% over Y2
F41: =ROUND(Minimum[[#This Row],[Year 3]]*1.045,0)  -- Year 4: +4.5% over Y3 (YOS=3)
     -- or 1.047 for higher YOS
G42: =ROUND(Minimum[[#This Row],[Year 4]]*1.043,0)  -- Year 5: +4.3% over Y4
```

### Year 1 % of Cap by YOS tier (col H, constant across years):
| YOS | % of Cap |
|-----|----------|
| 0 | 0.823% |
| 1 | 1.325% |
| 2 | 1.485% |
| 3 | 1.538% |
| 4 | 1.592% |
| 5 | 1.725% |
| 6 | 1.859% |
| 7 | 1.992% |
| 8 | 2.126% |
| 9 | 2.136% |
| 10+ | 2.350% |

---

## 7. Sample Data (2025 season)

| YOS | Year 1 | Year 2 | Year 3 | Year 4 | Year 5 |
|-----|--------|--------|--------|--------|--------|
| 0 | 1,272,870 | — | — | — | — |
| 1 | 2,048,494 | 2,150,917 | — | — | — |
| 2 | 2,296,274 | 2,411,090 | 2,525,901 | — | — |
| 3 | 2,378,870 | 2,497,812 | 2,616,754 | 2,735,698 | — |
| 4 | 2,461,463 | 2,584,539 | 2,707,612 | 2,830,685 | 2,953,760 |
| 10 | 3,634,153 | 3,815,861 | 3,997,570 | 4,179,277 | 4,360,985 |

---

## 8. Mapping to Our Postgres Model

| Sean Concept | Our Table/Column | Notes |
|--------------|------------------|-------|
| Minimum salary (Year 1) by YOS/season | `pcms.league_salary_scales.minimum_salary_amount` | Keyed by `(salary_year, league_lk, years_of_service)`; this matches the sheet’s Year 1 values. |
| Multi-year minimum scale (Years 2–5) | (derived) | We do **not** currently store Years 2–5 in a table; Sean derives them via fixed escalators (5%, 4.7%, etc.). We can compute these on demand from Year 1. |
| Salary cap for % calculations | `pcms.league_system_values.salary_cap_amount` (naming varies) | The workbook uses cap to project/validate % of cap. |
| Future cap projections (if needed) | `pcms.league_salary_cap_projections` | PCMS provides projections; Sean also projects forward via GrowthRate. |

---

## 9. Open Questions / TODO

- [ ] Confirm `pcms.league_salary_scales` is always populated for all seasons we need (2025–2031).
- [ ] Decide whether we need a helper function/view, e.g. `pcms.fn_minimum_scale_amount(salary_year, years_of_service, contract_year)` to reproduce Sean’s Years 2–5 logic.
- [ ] Validate Sean’s escalator constants vs PCMS / CBA (5%, 4.7%, 4.5%, 4.3% vary by YOS/year).
- [ ] For “projected” future seasons: decide whether tooling should use PCMS projections (`league_salary_cap_projections`) or a fixed GrowthRate model.
