# Spec: `rookie_scale_amounts.json`

## 1. Purpose

Lookup table providing **NBA rookie scale salary amounts** by pick number (1–30) and draft year (2025–2031). Used to determine guaranteed contract values for first-round draft picks, plus derived values like Qualifying Offers (QO), FA amounts, and cap holds.

The CBA mandates specific salaries for first-round picks based on draft slot; this sheet is the authoritative reference for those amounts and related CBA calculations.

---

## 2. Key Inputs / Controls

**No user inputs.** This is a reference table. All data is derived from:

- **SystemValues table** (rows 5–12 reference `CapAmounts` which pulls salary cap from `SystemValues`)
- **Hardcoded CBA percentages** (Year 1 % Cap, escalator rates, QO increases by pick)

---

## 3. Key Outputs

### CapAmounts Table (rows 5–12)
Lookup table for salary cap by season:

| Column | Name | Example (row 6) |
|--------|------|-----------------|
| A | Season | `2025` |
| B | Salary Cap | `=INDEX(SystemValues[[#Data],[Salary Cap]], ...)` |
| C | Est. Avg. Salary | `=INDEX(SystemValues[[#Data],[Est. Avg. Salary]], ...)` |
| D | 25% | `=CapAmounts[[#Headers],[25%]]*...` |

### RSC Table (rows 15–225+)
Main rookie scale data. 30 picks × 7 seasons = 210 data rows.

| Column | Name | Description |
|--------|------|-------------|
| A | Pick | e.g. `#1 2025`, `#30 2026` |
| B | Season | Draft year (2025–2031) |
| C | Year 1 | Year 1 salary (literal or formula) |
| D | Year 2 | Year 2 salary (Year 1 × 1.05) |
| E | Year 3 | Year 3 salary (Year 2 × 1.05) |
| F | Year 4 | Year 4 salary (team option, Year 3 × escalator) |
| G | 80–120% | Scale factor (1.2 = 120% of scale) |
| H | Year 1 % Cap | Base percentage of salary cap |
| I | Year 2 ↑ | Year-over-year increase (0.05 = 5%) |
| J | Year 3 ↑ | Year-over-year increase (0.05 = 5%) |
| K | Year 4 ↑ | Team option escalator (varies by pick, 1.261–1.805) |
| L | QO Increase | Qualifying Offer increase percentage (0.40–0.60) |
| M | FA Amount | Estimated FA value (Year 4 × 3, with cap) |
| N | Starter Criteria | `"Yes"` or `"No"` (picks 1–9 = Yes) |
| O | QO | Qualifying Offer amount |
| P | Cap Hold | `MAX(FA Amount, QO)` |

---

## 4. Layout / Zones

```
Row 1:       Title "Rookie Scale Amounts"
Row 3:       Section "Salary Cap Amounts"
Rows 5-12:   CapAmounts table (Season → Cap/Avg Salary/25%)
Row 15:      RSC table headers
Rows 16-45:  Pick #1-#30 for 2025
Rows 46:     (transition row with sparse formulas)
Rows 47-76:  Pick #1-#30 for 2026
...          (continues for 2027-2031)
~Row 225:    End of main RSC data
Rows 226+:   Additional formula rows (sparse)
```

---

## 5. Cross-Sheet Dependencies

### Inbound (this sheet reads from)
- **SystemValues** — salary cap and estimated average salary by season
  - Formula: `=INDEX(SystemValues[[#Data],[Salary Cap]], MATCH(...))`

### Outbound (other sheets read from this)
- **y.json** — references `"Rookie Scale Amounts | Qualifying Offers"` (row 741 header)
  - Used for QO calculations in the Y Warehouse

---

## 6. Key Formulas / Logic

### Year 1 Salary (column C, e.g. row 78 for pick #1 2027)
```excel
=ROUND((_xlfn.XLOOKUP(RSC[[#This Row],[Season]], CapAmounts[Season], CapAmounts[Salary Cap])
        * RSC[[#This Row],[Year 1 % Cap]])
       * RSC[[#This Row],[80 - 120%]], 0)
```
Year 1 = `SalaryCap × Year1%Cap × ScaleFactor`

### Year 2–3 Escalation (columns D, E)
```excel
D: =ROUND(RSC[[#This Row],[Year 1]]*(1+RSC[[#This Row],[Year 2 ↑]]),0)
E: =ROUND(RSC[[#This Row],[Year 2]]*(1+RSC[[#This Row],[Year3 ↑]]),0)
```
Standard 5% annual increase.

### Year 4 Team Option (column F)
```excel
=ROUND(RSC[[#This Row],[Year 3]]*(RSC[[#This Row],[Year 4 ↑]]),0)
```
Year 4 option escalator varies by pick (26.1% for #1 up to 80.5% for #30).

### FA Amount (column M)
```excel
=IF(AND(F16>$C$10, F16*2.5>$D$10), $C$10, F16*3)
```
FA amount = Year 4 × 3, unless capped by average salary thresholds.

For top picks (rows 16–17):
```excel
=RSC[[#This Row],[Year 4]]*3
```
(No cap logic for picks 1–2.)

### Qualifying Offer (column O)
```excel
=ROUND(IF(N16="No", F30*(L30+1), (F16*(1+L16))), 0)
```
- If Starter Criteria = "No": use standard QO formula
- If "Yes" (picks 1–9): Year 4 × (1 + QO Increase)

### Cap Hold (column P)
```excel
=IF(RSC[[#This Row],[FA Amount]]>RSC[[#This Row],[QO]], 
    RSC[[#This Row],[FA Amount]], 
    RSC[[#This Row],[QO]])
```
Cap hold = `MAX(FA Amount, QO)`.

---

## 7. Mapping to Postgres Model

| Sean Concept | Our Table | Notes |
|--------------|-----------|-------|
| Pick + Season → Year 1–4 salaries | `pcms.rookie_scale_amounts` | ✅ Exists; imported from PCMS (`salary_year_1..4`, plus option amounts/percentages). |
| Salary Cap / avg salary by season | `pcms.league_system_values` | Used for max / projection context (Sean derives many values from cap + avg salary). |
| “120% of scale” amounts | (derived) | Sean’s sheet explicitly multiplies by a **scale factor** (`80–120%`, currently 1.2). PCMS tables may represent the baseline scale; tooling may need to apply the chosen factor. |
| QO / cap hold / FA amount | `pcms.non_contract_amounts` (sometimes) | PCMS has QO/FA fields on non-contract amounts, but Sean’s sheet computes pick-based QO/cap-hold logic directly. We may need explicit derived calcs for pick planning tools. |

---

## 8. Open Questions / TODO

1. **PCMS vs Sean scale factor**: confirm whether `pcms.rookie_scale_amounts.salary_year_1..4` are baseline (100%) or already “maxed” (120%).

2. **Future years**: Sean projects 2027–2031 from projected caps. Decide whether tooling should:
   - store projected rookie scales in DB, or
   - compute on-demand from `league_salary_cap_projections`.

3. **QO / cap hold parity**: if we need pick-based cap holds for a “draft pick planner”, define whether to source from PCMS (if available) vs replicate Sean’s computed logic.

4. **Scale factor flexibility**: The column name suggests 80–120% flexibility, but current data uses 120%. Decide if tools need the ability to choose a different factor.
