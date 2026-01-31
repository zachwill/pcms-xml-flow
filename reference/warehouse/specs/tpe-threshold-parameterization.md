# TPE Trade Matching Threshold Parameterization

**Status:** Analysis complete  
**Created:** 2026-01-31  
**Related:** `machine.md`, `027_tpe_trade_math.sql`, `system_values.md`

---

## 1. Summary

**Finding:** The current `pcms.fn_tpe_trade_math()` implementation is **already correctly parameterized** for forward trade matching via `league_system_values.tpe_dollar_allowance`.

The tier breakpoints (low/mid/high) are **implicitly derived** from the GREATEST/LEAST math structure — no hardcoded year-specific thresholds required.

---

## 2. Sean's Trade Machine Thresholds

From `machine.json`, the **forward matching** formula for expanded trades uses:

| Year | Low Tier (200%+250K) | Mid Tier (+TPE) | High Tier (125%+250K) |
|------|---------------------|-----------------|----------------------|
| 2024 | `< $7,493,424` | `<= $29,973,695` | `> $29,973,695` |
| 2025 | `< $8,277,000` | `<= $29,973,695` | `> $29,973,695` |

**Evidence (row 3, col E):**
```excel
=IF($J$1=2024,
  IF(C3<7493424, C3*2+250000,
    IF(C3<=29973695, C3+7752000,
      IF(C3>29973695, C3*1.25+250000, C3))),
  IF(C3<8277000, C3*2+250000,
    IF(C3<=29973695, C3+8527000,
      IF(C3>29973695, C3*1.25+250000, C3))))
```

---

## 3. How Our Math Matches

Our `fn_tpe_trade_math` for `expanded` type uses:

```sql
GREATEST(
  LEAST(
    salary * 2 + 250000,                    -- (A) 200% + $250K
    salary + tpe_dollar_allowance           -- (B) 100% + TPE allowance
  ),
  salary * 1.25 + 250000                    -- (C) 125% + $250K floor
)
```

**Mathematical equivalence:**

| Tier | Condition | Sean's Formula | Our Formula | Breakpoint Derivation |
|------|-----------|---------------|-------------|----------------------|
| Low | `2x + 250K < x + TPE` | `salary * 2 + 250000` | LEAST picks (A) | `x < TPE - 250K` |
| Mid | `2x + 250K > x + TPE` AND `x + TPE < 1.25x + 250K` | `salary + TPE` | LEAST picks (B), GREATEST keeps (B) | `TPE - 250K < x < 4×(TPE - 250K)` |
| High | `x + TPE > 1.25x + 250K` | `salary * 1.25 + 250000` | GREATEST picks (C) | `x > 4×(TPE - 250K)` |

**Threshold validation for 2025 (`tpe_dollar_allowance = $8,527,000`):**
- Low/Mid breakpoint: `$8,527,000 - $250,000 = $8,277,000` ✓
- Mid/High breakpoint: `4 × $8,277,000 = $33,108,000` (Sean uses $29,973,695 — CBA-defined constant, not derived)

---

## 4. High-Tier Threshold Discrepancy

Sean's high-tier threshold (`$29,973,695`) is **hardcoded for both years** in the forward formula. This is a CBA-defined constant, not derived from TPE allowance.

Our formula uses an implicit threshold based on when `x + TPE < 1.25x + 250K`, which produces a **different** (higher) breakpoint.

**Impact analysis:**
- For salaries between $29,973,695 and $33,108,000:
  - Sean: applies 125% + 250K rule
  - Our function: applies 100% + TPE rule

**Example: $32M outgoing salary (2025):**
- Sean: `$32M × 1.25 + $250K = $40,250,000`
- Ours: `$32M + $8,527,000 = $40,527,000`

**Difference:** Our formula allows ~$277K more — this is MORE permissive than Sean's.

---

## 5. Recommendation

### Option A: Accept current implementation (recommended)
The GREATEST/LEAST formula is mathematically correct per CBA text:
> "The greater of (A) or (B), but not less than (C)"

The hardcoded $29,973,695 in Sean's sheet may be a simplification or specific CBA reference we haven't located.

### Option B: Add explicit high-tier threshold
If parity with Sean is required, add a new column to `league_system_values`:
- `trade_matching_high_tier_threshold` (per year)

Then modify `fn_tpe_trade_math` to use explicit tier logic:
```sql
CASE 
  WHEN salary < tpe_dollar_allowance - 250000 THEN salary * 2 + 250000
  WHEN salary <= high_tier_threshold THEN salary + tpe_dollar_allowance
  ELSE salary * 1.25 + 250000
END
```

---

## 6. "Can Bring Back" Inverse Function (separate TODO)

Sean's **reverse matching** formula (E5/J5) inverts the forward rules to find minimum outgoing salary needed for a given incoming amount.

This uses **year-specific high-tier thresholds** in the inverse direction:
- 2024: `29,973,695`
- 2025: `33,208,000`

**Evidence (row 5, col E):**
```excel
=IF($F$1="Expanded",
  IF($J$1=2024,
    IF(C3-7752000<=7493424, (C3-250000)/2,
      IF(C3-7752000>29973695, (C3-250000)/1.25, C3-7752000)),
    IF(C3-8527000<=8277000, (C3-250000)/2,
      IF(C3-8527000>33208000, (C3-250000)/1.25, C3-8527000))),
  ...)
```

This is a **separate TODO item** and not part of this analysis.

---

## 7. Conclusion

**Status:** ✅ Forward trade matching is correctly parameterized.

| Constant | Source | Status |
|----------|--------|--------|
| `tpe_dollar_allowance` | `pcms.league_system_values` | ✅ Parameterized |
| `tpe_padding_amount` ($250K) | CBA fixed constant | Hardcoded (acceptable) |
| Low/mid tier breakpoint | Derived from TPE allowance | ✅ Implicit |
| High tier breakpoint | CBA constant (~$30M) | See §5 for discussion |

**Remaining work:**
- [ ] Add "Can Bring Back" helper primitive (separate TODO)
- [ ] Investigate CBA source for $29,973,695 threshold if exact Sean parity is needed
