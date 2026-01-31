# Repeater Flag Parameterization Spec

**Status:** Proposed  
**Source:** `reference/warehouse/playground.json`, `reference/warehouse/team.json`

---

## 1. Problem

Sean's workbook contains **hardcoded repeater taxpayer flags** in `playground.json` and `team.json` (cells `J1` and `N1`).

These formulas use IF-chains to determine repeater status based on team code:

```excel
// J1 (Repeater in '25)
=IF($D$1="POR","No",
IF($D$1="BOS","Yes",
IF($D$1="PHX","Yes",
IF($D$1="DEN","Yes",
IF($D$1="GSW","Yes",
IF($D$1="LAL","Yes",
IF($D$1="MIL","Yes",
IF($D$1="LAC","Yes","No"))))))))

// N1 (Repeater in '26)
=IF($D$1="POR","No",
IF($D$1="BOS","Yes",
IF($D$1="PHX","Yes",
IF($D$1="DEN","Yes",
IF($D$1="GSW","Yes",
IF($D$1="LAL","Yes",
IF($D$1="MIL","Yes",
IF($D$1="LAC","Yes","No"))))))))
```

**Issues:**

1. **Hardcoded teams** — Only 8 teams are listed (BOS, PHX, DEN, GSW, LAL, MIL, LAC as repeaters; POR explicitly non-repeater).
2. **Static snapshot** — Status is frozen as of workbook creation; doesn't update with new tax years.
3. **Year-agnostic (partial)** — `J1` is labeled "Repeater in '25" and `N1` is "Repeater in '26", but both formulas are **identical** (no year-specific logic).
4. **Downstream impact** — The repeater flag directly affects tax payment calculations via `Tax Array` SUMPRODUCT formulas.

---

## 2. Solution

Replace hardcoded IF-chains with lookups from:

| Table | Column | Description |
|-------|--------|-------------|
| `pcms.tax_team_status` | `is_repeater_taxpayer` | Raw PCMS data per `(team_id, salary_year)` |
| `pcms.team_salary_warehouse` | `is_repeater_taxpayer` | Tool-facing cache per `(team_code, salary_year)` |

The **preferred source** for tooling is `pcms.team_salary_warehouse.is_repeater_taxpayer`, which:
- Is already team_code-keyed (no need to join `pcms.teams`)
- Is refreshed alongside other warehouse tables
- Falls back to `false` if no data exists (tool-friendly)

---

## 3. Data Flow

```
PCMS XML (tax_teams.json)
    ↓
    taxpayer_repeater_rate_flg
    ↓
pcms.tax_team_status.is_repeater_taxpayer
    ↓ (via refresh_team_salary_warehouse)
pcms.team_salary_warehouse.is_repeater_taxpayer
    ↓
Tool UI (parameterized by team_code + salary_year)
```

**Import source:** `import_pcms_data.flow/team_financials.inline_script.py` line 352:

```python
"is_repeater_taxpayer": to_bool(tt.get("taxpayer_repeater_rate_flg")) or False,
```

**Warehouse refresh:** `migrations/051_team_salary_warehouse_exclude_two_way_from_roster_count.sql` line 193:

```sql
COALESCE(tts.is_repeater_taxpayer, ttsn.is_repeater_taxpayer, false) AS is_repeater_taxpayer,
```

---

## 4. Usage Pattern

### For tax payment calculations

Current Sean formula (`E55` in `playground.json`):

```excel
=IF(
  $J$1="Yes",
  SUMPRODUCT(... repeater bracket ...),
  SUMPRODUCT(... non-repeater bracket ...)
)
```

Replacement in Postgres:

```sql
SELECT pcms.fn_luxury_tax_amount(
    2025,                    -- salary_year
    tsw.tax_total - lsv.tax_level_amount,  -- over_tax_amount
    tsw.is_repeater_taxpayer -- from warehouse
)
FROM pcms.team_salary_warehouse tsw
JOIN pcms.league_system_values lsv ON lsv.salary_year = 2025
WHERE tsw.team_code = 'BOS' AND tsw.salary_year = 2025;
```

### For team-year lookup

```sql
SELECT team_code, salary_year, is_repeater_taxpayer
FROM pcms.team_salary_warehouse
WHERE salary_year IN (2025, 2026);
```

---

## 5. Validation: Sean's Hardcoded Teams vs PCMS

Sean's 2025 repeaters (per `J1`):
- BOS, PHX, DEN, GSW, LAL, MIL, LAC

**TODO:** Validate against `pcms.tax_team_status`:

```sql
SELECT team_code, salary_year, is_repeater_taxpayer
FROM pcms.team_salary_warehouse
WHERE salary_year = 2025
  AND is_repeater_taxpayer = true
ORDER BY team_code;
```

If there are discrepancies:
1. Check if PCMS source (`taxpayer_repeater_rate_flg`) is authoritative
2. If PCMS is incomplete, flag for Sean to verify

---

## 6. Implementation Tasks

### Already done

- [x] `pcms.tax_team_status` table exists (created in `001_schema_dump.sql`, enriched with `team_code` in `003_team_code_and_draft_picks.sql`)
- [x] `is_repeater_taxpayer` imported from PCMS (`team_financials.inline_script.py`)
- [x] `pcms.team_salary_warehouse.is_repeater_taxpayer` column exposed (migration 019 → 051)
- [x] `pcms.fn_luxury_tax_amount(salary_year, over_tax_amount, is_repeater)` function (migration 057)

### TODO

- [ ] UI/API: Replace hardcoded repeater logic in Salary Book / Playground UI with warehouse lookup
- [ ] Verify PCMS data coverage for `is_repeater_taxpayer` across 2025–2030
- [ ] Consider adding `is_repeater_taxpayer` to `pcms.salary_book_warehouse` if needed for player-context displays

---

## 7. Cross-References

- `reference/warehouse/specs/playground.md` §2 (Key Inputs: J1/N1 repeater flags)
- `reference/warehouse/specs/team.md` §2 (Key Inputs: J1/N1 repeater flags)
- `reference/warehouse/specs/tax_array.md` §8-10 (tax bracket calculation with repeater)
- `reference/warehouse/specs/fn_luxury_tax_amount.md` (SQL function using `is_repeater`)
- `migrations/051_team_salary_warehouse_exclude_two_way_from_roster_count.sql` (warehouse refresh)
- `migrations/057_fn_luxury_tax_amount.sql` (tax calculation function)
