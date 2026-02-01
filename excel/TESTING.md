# Excel Workbook Testing & Debugging

This workbook is **code-generated** (XlsxWriter) and is expected to open cleanly in Excel 365/2021 **without** a repair dialog.

## Build a workbook (local)

From the repo root:

```bash
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today

# Mac
open shared/capbook.xlsx
```

Required env:
- `POSTGRES_URL`

## If Excel shows a repair dialog

1. Click “Yes” to repair.
2. Copy the repair log.
   - Mac path:
     `~/Library/Containers/com.microsoft.Excel/Data/Library/Application Support/Microsoft/`
3. Run the XML sanity checks below to pinpoint what broke.

## XML sanity checks (common Mac Excel repair triggers)

### Recommended: Use the automated validator

The `validate_xlsx_formulas.py` script performs comprehensive validation of ALL LET/LAMBDA variables (not just the first one) and checks for spill refs in defined names:

```bash
uv run excel/validate_xlsx_formulas.py shared/capbook.xlsx

# Expected output on success:
# ✅ All formula validation checks passed!
```

If issues are found, the script reports each bare variable with its location and suggested fix.

### Manual checks (for debugging)

#### 1) No bare LET/LAMBDA variables (must be `_xlpm.`)

The manual grep only catches the **first** variable after `LET(`; use the validator above for comprehensive checks.

```bash
unzip -p shared/capbook.xlsx xl/worksheets/*.xml \
  | grep -oE "LET\([a-z_]+," \
  | grep -v "_xlpm" \
  | head -20

# Expect: no output
```

#### 2) No spill operator (`#`) in defined names

XlsxWriter + Excel can generate invalid XML if a defined name contains a spill ref like `Sheet!$A$1#`.

We avoid this by defining validation-list named ranges as **fixed-size ranges** (e.g. first 32 rows), not spill refs.

```bash
unzip -p shared/capbook.xlsx xl/workbook.xml | grep -n "#" | head -20

# Expect: no output
```

#### 3) Data validation sources: avoid structured table refs (use INDIRECT)

Some Excel versions repair when data validation sources use structured refs directly (e.g. `=tbl_plan_manager[plan_name]`).

Current convention:
- Use `=INDIRECT("tbl_plan_manager[plan_name]")` for plan dropdowns.

To inspect data validation XML (example: TEAM_COCKPIT is usually sheet3):

```bash
unzip -p shared/capbook.xlsx xl/worksheets/sheet3.xml | grep -n "dataValidation" -n | head -40
```

## Inspect generated XML (misc)

```bash
# Inspect named ranges
unzip -p shared/capbook.xlsx xl/workbook.xml | grep -n "definedName" | head -40

# Check for LET formulas (TEAM_COCKPIT)
unzip -p shared/capbook.xlsx xl/worksheets/sheet3.xml | grep -n "LET" | head -20
```

## Sheet order reference (UI sheets)

| # | Sheet |
|---:|------|
| 1 | HOME |
| 2 | META |
| 3 | TEAM_COCKPIT |
| 4 | ROSTER_GRID |
| 5 | BUDGET_LEDGER |
| 6 | PLAN_MANAGER |
| 7 | PLAN_JOURNAL |
| 8 | TRADE_MACHINE |
| 9 | SIGNINGS_AND_EXCEPTIONS |
| 10 | WAIVE_BUYOUT_STRETCH |
| 11 | ASSETS |
| 12 | AUDIT_AND_RECONCILE |
| 13 | RULES_REFERENCE |
