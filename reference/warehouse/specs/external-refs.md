# External Workbook References — Resolution Guide

**Generated:** 2026-01-31  
**Source:** `reference/warehouse/*.json`

---

## Overview

Some formulas in Sean's exported workbook reference **external workbooks** using Excel's `[n]` syntax (e.g., `[2]Sheet!Cell`). These are links to other Excel files that were open or linked when the workbook was saved.

This document maps each external reference to its **in-repo equivalent** (another sheet in `reference/warehouse/`) and/or the corresponding **`pcms.*` table**.

---

## External Reference Inventory

| Pattern | Count | Files Using It |
|---------|-------|----------------|
| `[2]Exceptions Warehouse - 2024` | 26 | `machine.json` |
| `[2]Y!` | 82 | `2025.json`, `finance.json`, `ga.json`, `playground.json`, `por.json`, `team.json` |
| `[2]X!` | 2 | `machine.json` |
| `[2]Contract Protections` | 1 | `dynamic_contracts.json` |

---

## Resolution Details

### 1. `[2]Exceptions Warehouse - 2024`

**What it is:** An older (2024-25 season) version of the Exceptions list. Referenced by the Trade Machine to look up team TPEs.

**Example formula** (from `machine.json` row 2):
```excel
=IFERROR(_xlfn._xlws.FILTER('[2]Exceptions Warehouse - 2024'!$C$4:$C$70, 
         '[2]Exceptions Warehouse - 2024'!$B$4:$B$70=B1),"None")
```

This filters exception names (column C) by team code (column B).

**In-repo equivalent:**
- `reference/warehouse/exceptions.json` — current (2025-26) exceptions sheet

**Column mapping (from exceptions.json headers, row 3):**
| Column | Header |
|--------|--------|
| B | Team |
| C | Exception |
| D | Date |
| E | Type |
| F | Amount |

**Postgres equivalent:**
- `pcms.exceptions_warehouse` — denormalized cache of active exceptions

```sql
-- Equivalent query: filter exceptions by team
SELECT exception_type_name, trade_exception_player_name, remaining_amount
  FROM pcms.exceptions_warehouse
 WHERE team_code = 'POR'
   AND record_status_lk = 'Active'
 ORDER BY remaining_amount DESC;
```

**Status:** ✅ Resolvable — use `exceptions.json` (current) or `pcms.exceptions_warehouse` (DB).

---

### 2. `[2]Y!`

**What it is:** The Y Warehouse (multi-year salary matrix) in an external workbook. Some sheets reference it via `[2]Y!` instead of the local `Y!`.

**Example formula** (from `2025.json` row 24):
```excel
=IFERROR(
  IF(INDEX([2]Y!$P:$P, MATCH(D24, [2]Y!$A:$A, 0)) = "-", "", 
     INDEX([2]Y!$P:$P, MATCH(D24, [2]Y!$A:$A, 0))),
"")
```

This looks up column P (2030 salary) by player ID (column A).

**In-repo equivalent:**
- `reference/warehouse/y.json` — the local Y sheet

**Column P meaning (from y.json headers):**
- Row 2 shows `P` = `=I2` which equals **2030** (one of the "Options" year columns for cap)

**Postgres equivalent:**
- `pcms.salary_book_warehouse` — pivoted player salary view

```sql
SELECT player_name, y2030_cap_amount
  FROM pcms.salary_book_warehouse
 WHERE player_id = 1630700;
```

**Status:** ✅ Resolvable — use `y.json` (local) or `pcms.salary_book_warehouse` (DB).

---

### 3. `[2]X!`

**What it is:** The **X Warehouse** (2024-25 season salary matrix) — the prior-year version of Y.

**Example formula** (from `machine.json` row 9):
```excel
=[2]X!AN9
```

This pulls a specific cell (AN9) from the prior-year warehouse.

**Files referencing it:**
- `machine.json` rows 9, 10 reference `[2]X!AN9` and `[2]X!AN10`

**Context from machine.json:**
- Row 9: `S: "2024"`, `T: "Cap:"`, `U: "=[2]X!AN9"` — looks like it's pulling the 2024 salary cap value
- Row 10: context shows this is the row header area for the trade machine

**In-repo equivalent:**
- **None directly** — there is no `x.json` exported. X was the 2024-25 equivalent of Y.

**Postgres equivalent:**
- `pcms.league_system_values` — CBA constants by year

```sql
-- Get 2024 cap
SELECT salary_cap_amount FROM pcms.league_system_values WHERE salary_year = 2025;
-- (Note: PCMS uses salary_year = start year + 1, so 2024-25 season = salary_year 2025)
```

Alternatively, if the reference is to player salaries:
- `pcms.salary_book_warehouse` with `salary_year = 2025`

**Status:** ⚠️ Partially resolvable — need to determine what AN9 represents:
- If it's a cap constant → use `pcms.league_system_values`
- If it's a player salary → use `pcms.salary_book_warehouse` with prior year filter

---

### 4. `[2]Contract Protections`

**What it is:** Contract protection/guarantee lookup table.

**Example formula** (from `dynamic_contracts.json` row 1):
```excel
='[2]Contract Protections'!F1
```

This pulls cell F1 (header row) from the protections sheet.

**In-repo equivalent:**
- `reference/warehouse/contract_protections.json`

**Column F meaning (from contract_protections.json row 1):**
- `F: "Protection Coverage"`

**Postgres equivalent:**
- `pcms.contract_amounts` — contains guarantee/protection fields

```sql
SELECT guarantee_type_lk, protection_amount
  FROM pcms.contract_amounts
 WHERE contract_id = ?
   AND salary_year = ?;
```

**Status:** ✅ Resolvable — use `contract_protections.json` (local) or `pcms.contract_amounts` (DB).

---

## Summary: What External Workbook `[2]` Represents

Based on the naming pattern (`Exceptions Warehouse - 2024`), `[2]` appears to be a **prior-season workbook** (2024-25). It contains:

- **X** — the 2024-25 Y Warehouse (player salary matrix for prior year)
- **Exceptions Warehouse - 2024** — prior-year exceptions list
- **Contract Protections** — protection lookup (likely identical structure)

For tool implementation, use the **current** in-repo sheets or Postgres tables. The `[2]` references are legacy links that should be updated to:
- Local sheet references (`Y!` instead of `[2]Y!`)
- Or Postgres queries against `pcms.*` tables

---

## Migration Notes for Trade Machine (`machine.json`)

The Trade Machine has the most external refs. Here's how to handle them:

| Current Reference | Replace With |
|-------------------|--------------|
| `'[2]Exceptions Warehouse - 2024'!...` | `Exceptions!...` (local) or `pcms.exceptions_warehouse` |
| `[2]X!AN9` | `pcms.league_system_values.salary_cap_amount WHERE salary_year = 2025` |
| `[2]Y!...` | `Y!...` (local) or `pcms.salary_book_warehouse` |

---

## Open Questions

1. **What is cell AN9 in the X sheet?** Context suggests it's a cap value for 2024, but we'd need the original X sheet to confirm. The surrounding cells in `machine.json` row 9 show: `S: "2024", T: "Cap:", U: "=[2]X!AN9"`, which strongly suggests it's the 2024-25 salary cap ($136,021,000).

2. **Should we create an X equivalent?** For historical trade analysis, we may need to support prior-year salary data. `pcms.salary_book_warehouse` could be parameterized by year, or we could maintain a separate X view.

3. **Are there other `[n]` references?** Only `[2]` appears in the current export. No `[1]`, `[3]`, etc. were found.
