# "Can Bring Back" Inverse Trade Matching Primitive

**Status:** Spec complete  
**Created:** 2026-01-31  
**Related:** `machine.md`, `tpe-threshold-parameterization.md`, `027_tpe_trade_math.sql`

---

## 1. Summary

Sean's Trade Machine has a **reverse matching** formula (cols E5/J5) that inverts the forward salary-matching rules. Given an **incoming salary** (what you want to acquire), it calculates the **minimum outgoing salary** needed to match.

This is the inverse of `fn_tpe_trade_math()` which computes: *outgoing → max incoming*.

**Use case:** "Can Bring Back" tables that show, for each player on a roster, what salary range they can acquire in return.

---

## 2. Sean's E5/J5 Formula

From `machine.json` row 5, col E:

```excel
=IF(C3="","",
  IF($F$1="Expanded",
    IF($J$1=2024,
      IF(C3-7752000<=7493424, (C3-250000)/2,
        IF(C3-7752000>29973695, (C3-250000)/1.25,
          C3-7752000)),
      IF(C3-8527000<=8277000, (C3-250000)/2,
        IF(C3-8527000>33208000, (C3-250000)/1.25,
          C3-8527000))),
    IF($F$1="Standard",
      IF($J$1=2024, C3-7752000, C3-8527000),
      C3)))
```

**Key insight:** This formula takes `C3` (which is the player's **outgoing salary** used as input to the "can bring back" calculation) and computes the **minimum** incoming salary that player could match. But the formula logic inverts the tier rules.

Wait — re-reading the formula:
- `C3` is the **cap salary** from row 3 (forward matching input)
- E5 appears to compute **minimum outgoing** needed given that `C3` value interpreted as an incoming target

Actually, looking at the machine spec (§7), E5/J5 are in the *same* columns as E3/J3 but on alternating rows:
- Row 3: forward (outgoing → max incoming)
- Row 5: reverse (for "Can Bring Back" — appears below the player salary)

Let me re-parse: E5 uses `C3` which is the player's **actual cap salary**. The formula computes the **minimum salary** someone else would need to send to acquire that player.

**Interpretation:** Given a player with salary `S`, what's the **minimum** salary the other team needs to send back to match?

---

## 3. Inverse Formula Logic

### Forward matching (E3)
Given outgoing salary `out`:
```
if out < low_tier_threshold:       return out * 2 + 250000    # 200% + 250K
elif out <= high_tier_threshold:   return out + tpe_allowance # 100% + TPE
else:                              return out * 1.25 + 250000 # 125% + 250K
```

### Reverse matching (E5) — "can bring back"
Given target incoming salary `incoming` (the player you want to trade AWAY):
```
if incoming - tpe_allowance <= low_tier_threshold:
    return (incoming - 250000) / 2                # invert 200% + 250K
elif incoming - tpe_allowance > inverse_high_tier:
    return (incoming - 250000) / 1.25             # invert 125% + 250K
else:
    return incoming - tpe_allowance               # invert 100% + TPE
```

### Year-specific thresholds

| Year | TPE Allowance | Low Tier | Inverse High Tier |
|------|---------------|----------|-------------------|
| 2024 | $7,752,000 | $7,493,424 | $29,973,695 |
| 2025 | $8,527,000 | $8,277,000 | $33,208,000 |

**Note:** The "inverse high tier" for 2025 is $33,208,000 (≈ 4 × $8,277,000), different from the forward formula's $29,973,695.

---

## 4. Standard Mode

When `$F$1 = "Standard"`:
```
return incoming - tpe_allowance
```
This is dollar-for-dollar matching with the TPE allowance margin.

---

## 5. Use Case in Trade Machine

In Sean's workbook, the "Can Bring Back" zone (rows 32+) shows:
- **Col L/O**: Player name
- **Col M**: Max incoming (forward formula result)
- **Col below**: Min incoming (reverse formula result)

This lets analysts quickly see: "If I trade Player X ($35M), I can bring back someone between $26.5M and $44M".

---

## 6. Proposed SQL Function

```sql
CREATE OR REPLACE FUNCTION pcms.fn_min_outgoing_for_incoming(
  p_incoming_salary bigint,
  p_salary_year int,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
SELECT
  CASE LOWER(p_mode)
    WHEN 'standard' THEN
      p_incoming_salary - lsv.tpe_dollar_allowance
    WHEN 'expanded' THEN
      CASE
        -- Low tier: invert 200% + 250K
        WHEN p_incoming_salary - lsv.tpe_dollar_allowance <= (lsv.tpe_dollar_allowance - 250000) THEN
          CEIL((p_incoming_salary - 250000)::numeric / 2)::bigint
        -- High tier: invert 125% + 250K
        WHEN p_incoming_salary - lsv.tpe_dollar_allowance > (4 * (lsv.tpe_dollar_allowance - 250000)) THEN
          CEIL((p_incoming_salary - 250000)::numeric / 1.25)::bigint
        -- Mid tier: invert 100% + TPE
        ELSE
          p_incoming_salary - lsv.tpe_dollar_allowance
      END
    ELSE
      p_incoming_salary  -- Apron teams: 1:1
  END
FROM pcms.league_system_values lsv
WHERE lsv.league_lk = p_league_lk
  AND lsv.salary_year = p_salary_year;
$$;
```

**Notes:**
- Uses `tpe_dollar_allowance` from `league_system_values` (already parameterized)
- Tier breakpoints derived from TPE allowance (matching forward function approach)
- The "inverse high tier" is approximately `4 × (TPE - 250K)`

---

## 7. Sean's Threshold vs Derived

| Year | TPE | Derived Low | Sean Low | Derived High | Sean High |
|------|-----|-------------|----------|--------------|-----------|
| 2024 | 7,752,000 | 7,502,000 | 7,493,424 | 30,008,000 | 29,973,695 |
| 2025 | 8,527,000 | 8,277,000 | 8,277,000 | 33,108,000 | 33,208,000 |

Small discrepancies exist. For **exact Sean parity**, we'd need to store the thresholds explicitly in `league_system_values`.

For **practical correctness**, the derived values are close enough (differences < $100K on threshold edges).

---

## 8. Alternative: Return Both Min and Max

For UI tools, it may be more useful to return a range:

```sql
CREATE OR REPLACE FUNCTION pcms.fn_trade_salary_range(
  p_outgoing_salary bigint,
  p_salary_year int,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS TABLE (
  min_incoming bigint,
  max_incoming bigint
)
LANGUAGE sql
STABLE
AS $$
-- Returns both ends of the salary matching window
SELECT
  pcms.fn_min_outgoing_for_incoming(p_outgoing_salary, p_salary_year, p_mode, p_league_lk) AS min_incoming,
  -- max_incoming uses forward formula (already in fn_tpe_trade_math but extractable)
  CASE LOWER(p_mode)
    WHEN 'expanded' THEN
      GREATEST(
        LEAST(
          p_outgoing_salary * 2 + 250000,
          p_outgoing_salary + lsv.tpe_dollar_allowance
        ),
        CEIL(p_outgoing_salary::numeric * 1.25)::bigint + 250000
      )
    WHEN 'standard' THEN
      p_outgoing_salary + lsv.tpe_dollar_allowance
    ELSE
      p_outgoing_salary
  END AS max_incoming
FROM pcms.league_system_values lsv
WHERE lsv.league_lk = p_league_lk
  AND lsv.salary_year = p_salary_year;
$$;
```

---

## 9. Implementation Plan

1. **Add function** `pcms.fn_min_outgoing_for_incoming()` — inverse of forward matching
2. **Optionally add** `pcms.fn_trade_salary_range()` — convenience wrapper returning `(min, max)`
3. **Verify** against Sean's sample calculations from `machine.json`
4. **Test edge cases:**
   - Low-tier boundary ($8.3M incoming for 2025)
   - High-tier boundary ($40M+ incoming)
   - Standard mode
   - Apron-team mode (1:1)

---

## 10. Mapping to Postgres

| Sean Concept | Formula Location | Our Function |
|--------------|------------------|--------------|
| Forward matching (E3) | Row 3, alternating | `pcms.fn_tpe_trade_math()` → `max_replacement_salary` |
| Reverse matching (E5) | Row 5, alternating | `pcms.fn_min_outgoing_for_incoming()` (new) |
| Salary range | Can Bring Back zone | `pcms.fn_trade_salary_range()` (optional wrapper) |

---

## 11. Open Questions

1. **Exact threshold parity**: Accept derived thresholds or add explicit columns to `league_system_values`?
   - Recommendation: Accept derived (< $100K difference at edge cases)

2. **Apron team handling**: Should inverse function accept an `is_apron_team` flag?
   - Current: Use `mode = 'apron'` to get 1:1 matching

3. **Naming**: `fn_min_outgoing_for_incoming` vs `fn_can_bring_back_min`?
   - Either works; former is more explicit about what it calculates
