# Minimum Salary Parity Analysis

**Status:** Complete  
**Date:** 2026-01-31

---

## 1. Summary

Sean's workbook derives **multi-year minimum salaries (Years 2-5)** using fixed CBA escalator percentages. PCMS only provides **Year 1 minimums** via `yearly_salary_scales.json`. We currently store only Year 1 in `pcms.league_salary_scales.minimum_salary_amount`.

**Gap identified:** We need a helper function to derive Years 2-5 on demand using the same escalators Sean uses.

---

## 2. Sean's Escalator Constants (from `minimum_salary_scale.json`)

### Year 2: +5% over Year 1 (all YOS)
```excel
D39: =ROUND(Minimum[[#This Row],[Year 1]]*1.05,0)
```

### Year 3: +4.7% over Year 2 (all YOS ≥ 2)
```excel
E40: =ROUND(Minimum[[#This Row],[Year 2]]*1.047,0)
```

### Year 4: Varies by YOS

| YOS | Year 4 Multiplier | Evidence |
|-----|-------------------|----------|
| 3   | `Year 3 * 1.045`  | Row 41: `=ROUND(Minimum[[#This Row],[Year 3]]*1.045,0)` |
| 4+  | `Year 3 * 1.047`  | Row 42+: `=ROUND(Minimum[[#This Row],[Year 3]]*1.047,0)` |

### Year 5: +4.3% over Year 4 (all YOS ≥ 4)
```excel
G42: =ROUND(Minimum[[#This Row],[Year 4]]*1.043,0)
```

---

## 3. Contract Year Eligibility by YOS

Not all YOS tiers can sign multi-year minimum deals. The table structure implies:

| YOS | Max Contract Years |
|-----|-------------------|
| 0   | 1 year only       |
| 1   | 2 years           |
| 2   | 3 years           |
| 3   | 4 years           |
| 4+  | 5 years (full)    |

---

## 4. Proration Assumption (`/174`)

Sean uses `/174` for **prorated roster charges** when calculating incomplete roster penalties.

**Formula from `team_summary.json` (row 3):**
```excel
D3: =IF(C3<12,12-C3,0)*('Minimum Salary Scale'!$C$16*($D$1/174))
E3: =IF(C3<14,14-C3,0)*'Minimum Salary Scale'!$C$18*($D$1/174)
```

Where:
- `$D$1 = DATE(2026,4,12) - TODAY() + 1` → days remaining in season
- `174` = total days in NBA regular season (Oct 22 → Apr 13 ≈ 174 days)
- `$C$16` = YOS=0 Year 1 minimum (1,272,870 for 2025)
- `$C$18` = YOS=2 Year 1 minimum (2,296,274 for 2025)

**Logic:**
- If roster < 12 players → charge (12 - roster) × rookie_minimum × days_left/174
- If roster < 14 players → charge (14 - roster) × vet_minimum × days_left/174

---

## 5. PCMS Data vs Sean's Data

### PCMS provides (via `yearly_salary_scales.json`)
- `salary_year` (season)
- `league_lk` (NBA/DLG)
- `years_of_service` (0-10)
- `minimum_salary_year1` ← **Year 1 only**

### Sean hardcodes (rows 16-37 for 2025/2026)
- Year 1, 2, 3, 4, 5 amounts for all YOS tiers
- These are CBA-published values, slightly differ from pure escalator math due to rounding at CBA level

### Sean derives (rows 38+ for 2027+)
- Year 1: `ROUND(salary_cap × YOS_pct_of_cap, 0)`
- Years 2-5: Escalator formulas

---

## 6. YOS % of Cap Constants

Sean uses fixed percentages for Year 1 minimum as % of salary cap:

| YOS | % of Cap (col H) |
|-----|------------------|
| 0   | 0.823081%        |
| 1   | 1.324626%        |
| 2   | 1.484849%        |
| 3   | 1.538258%        |
| 4   | 1.591666%        |
| 5   | 1.725185%        |
| 6   | 1.858708%        |
| 7   | 1.992228%        |
| 8   | 2.125751%        |
| 9   | 2.136333%        |
| 10+ | 2.349966%        |

---

## 7. Sample Data Verification (2025 YOS=4)

| Field | Sean (row 20) | Escalator Calc | Delta |
|-------|---------------|----------------|-------|
| Year 1 | 2,461,463 | — (hardcoded) | — |
| Year 2 | 2,584,539 | 2,584,536 | +3 |
| Year 3 | 2,707,612 | 2,706,009 | +1,603 |
| Year 4 | 2,830,685 | 2,833,200 | -2,515 |
| Year 5 | 2,953,760 | 2,954,819 | -1,059 |

**Note:** Sean's 2025/2026 values are hardcoded from CBA publications, not derived via escalators. Small differences are due to CBA-level rounding.

---

## 8. Recommendations for Tooling Parity

### Option A: Helper Function (Recommended)
Create `pcms.fn_minimum_salary(salary_year, years_of_service, contract_year)`:
- For `contract_year = 1`: return `minimum_salary_amount` from `pcms.league_salary_scales`
- For `contract_year > 1`: derive using escalators

```sql
CREATE OR REPLACE FUNCTION pcms.fn_minimum_salary(
    p_salary_year INT,
    p_years_of_service INT,
    p_contract_year INT  -- 1, 2, 3, 4, or 5
) RETURNS BIGINT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base BIGINT;
    v_result BIGINT;
BEGIN
    -- Get Year 1 from table
    SELECT minimum_salary_amount INTO v_base
    FROM pcms.league_salary_scales
    WHERE salary_year = p_salary_year
      AND league_lk = 'NBA'
      AND years_of_service = p_years_of_service;
    
    IF v_base IS NULL OR p_contract_year = 1 THEN
        RETURN v_base;
    END IF;
    
    -- Year 2: +5%
    v_result := ROUND(v_base * 1.05);
    IF p_contract_year = 2 THEN RETURN v_result; END IF;
    
    -- Year 3: +4.7%
    v_result := ROUND(v_result * 1.047);
    IF p_contract_year = 3 THEN RETURN v_result; END IF;
    
    -- Year 4: +4.5% for YOS=3, +4.7% for YOS>=4
    IF p_years_of_service = 3 THEN
        v_result := ROUND(v_result * 1.045);
    ELSE
        v_result := ROUND(v_result * 1.047);
    END IF;
    IF p_contract_year = 4 THEN RETURN v_result; END IF;
    
    -- Year 5: +4.3%
    v_result := ROUND(v_result * 1.043);
    RETURN v_result;
END;
$$;
```

### Option B: Expand Table Schema
Add `minimum_salary_year2..year5` columns to `pcms.league_salary_scales`. This requires:
- Schema migration
- Updating import script to compute escalators
- More storage, but simpler queries

### Recommendation
**Option A** is preferred because:
1. PCMS only provides Year 1 data
2. Escalators are CBA constants (unlikely to change mid-CBA)
3. Smaller table footprint
4. Easy to validate/audit escalator logic

---

## 9. Proration Constant (`174`)

For incomplete roster charge calculations, use:
- **174 days** = NBA regular season length
- Season dates typically Oct 22 → Apr 13

This could be a constant or derived from `pcms.league_system_values` if we add season date fields.

---

## 10. Open Questions

- [ ] Confirm PCMS does NOT provide Year 2-5 minimums (it appears not to)
- [ ] Decide: helper function vs expanded table schema
- [ ] Add season start/end dates to `pcms.league_system_values`? (for proration calcs)
- [ ] Validate YOS=3 special case (1.045 vs 1.047) against CBA Article VII

---

## 11. Files Referenced

| File | Rows | Evidence Used |
|------|------|---------------|
| `minimum_salary_scale.json` | 16-92 | Escalator formulas, hardcoded values, YOS % of cap |
| `team_summary.json` | 1, 3 | `/174` proration, roster charge formulas |
| `import_pcms_data.flow/league_config.inline_script.py` | 311-327 | Confirms we only import `minimum_salary_year1` |
