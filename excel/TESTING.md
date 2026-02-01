# Excel Workbook Testing & Debugging

## Quick Validation Loop

```bash
# 1. Rebuild the workbook
cd /Users/zachwill/code/pcms-xml-flow/excel
uv run python export_capbook.py --out ../shared/capbook.xlsx --base-year 2025 --as-of 2025-01-31

# 2. Open in Excel 365 (Mac)
open ../shared/capbook.xlsx
```

If Excel shows a repair dialog, click "Yes" to repair, then check the repair log at:
`~/Library/Containers/com.microsoft.Excel/Data/Library/Application Support/Microsoft/`

Or Excel will show you the XML repair log directly - copy/paste it to share what failed.

---

## Known XlsxWriter Limitations

### 1. Excel 365 Function Prefixes (FIXED)

**Problem**: XlsxWriter doesn't add `_xlfn.` prefix to LET, FILTER, XLOOKUP, etc. by default.

**Solution**: Added `use_future_functions: True` to workbook options in `excel/capbook/build.py`:
```python
workbook = xlsxwriter.Workbook(str(out_path), {
    "remove_timezone": True,
    "use_future_functions": True,
})
```

### 2. Spill Operator (`#`) in Named Ranges

**Problem**: XlsxWriter generates invalid XML for named ranges with spill references like `='Sheet'!$A$1#`

**Affected code**:
- `ExceptionUsedList` in `excel/capbook/sheets/subsystems.py` (~line 1349)
- `TradeTeamList` in `excel/capbook/sheets/subsystems.py` (~line 402)

**Workaround**: Use static range references instead of spill operator, or remove named ranges and use direct formulas.

### 3. Structured Table References in Data Validation

**Problem**: `=tbl_plan_manager[plan_name]` in data validation causes Excel repair.

**Affected code**: `excel/capbook/sheets/command_bar.py` lines ~390-415 (ActivePlan, ComparePlanA/B/C/D dropdowns)

**Workarounds that work**:
- `=INDIRECT("tbl_test[Name]")` ✓
- Direct range `=$A$2:$A$10` ✓

---

## Isolate Specific Issues

Create minimal test files to verify fixes:

```bash
cd /Users/zachwill/code/pcms-xml-flow
uv run python << 'EOF'
import xlsxwriter

# Test your specific fix here
wb = xlsxwriter.Workbook("shared/test_fix.xlsx", {"use_future_functions": True})
ws = wb.add_worksheet("Test")

# Example: test INDIRECT workaround for table reference
ws.add_table("A1:A4", {"name": "tbl_test", "columns": [{"header": "Name"}], "data": [["X"], ["Y"], ["Z"]]})
ws.data_validation("C1", {"validate": "list", "source": '=INDIRECT("tbl_test[Name]")'})

wb.close()
print("Created shared/test_fix.xlsx")
EOF

# Open and verify no repair dialog
open shared/test_fix.xlsx
```

---

## Inspect Generated XML

```bash
# Inspect named ranges
unzip -p shared/capbook.xlsx xl/workbook.xml | xmllint --format - | grep -A2 "definedName"

# Inspect data validation on a specific sheet (sheet3 = TEAM_COCKPIT)
unzip -p shared/capbook.xlsx xl/worksheets/sheet3.xml | xmllint --format - | grep -A5 "dataValidation"

# Check table formulas
unzip -p shared/capbook.xlsx xl/tables/table4.xml | xmllint --format -

# Check if LET/FILTER have proper _xlfn prefixes
unzip -p shared/capbook.xlsx xl/worksheets/sheet3.xml | xmllint --format - | grep -E "<f [^>]*>.*LET" | head -3
```

---

## Sheet Number Reference

| Sheet # | Name                    | Notes                                      |
|---------|-------------------------|--------------------------------------------|
| 1       | HOME                    |                                            |
| 2       | META                    |                                            |
| 3       | TEAM_COCKPIT            | Data validation + conditional formatting   |
| 4       | ROSTER_GRID             |                                            |
| 5       | BUDGET_LEDGER           |                                            |
| 6       | PLAN_MANAGER            | Contains tbl_plan_manager                  |
| 7       | PLAN_JOURNAL            |                                            |
| 8       | TRADE_MACHINE           | TradeTeamList named range                  |
| 9       | SIGNINGS_AND_EXCEPTIONS | table4 = tbl_signings_input                |
| 10      | WAIVE_BUYOUT_STRETCH    | table5 = tbl_waive_input                   |
| 11      | ASSETS                  |                                            |
| 12      | AUDIT_AND_RECONCILE     |                                            |

---

## What Works vs What Fails

### Works ✓
- `=INDIRECT("tbl_test[Name]")` in data validation
- `=$A$2:$A$4` direct range in data validation
- Named range without spill operator (`=Sheet!$A$1:$A$3`)
- `use_future_functions: True` for `_xlfn.` prefixes

### Fails ✗
- `=tbl_plan_manager[plan_name]` in data validation (structured table ref)
- `='Sheet'!$A$1#` (spill operator) in named range

---

## Files to Fix

1. **`excel/capbook/sheets/command_bar.py`**
   - Change `"source": "=tbl_plan_manager[plan_name]"` to use INDIRECT or direct range
   - Affects ActivePlan and ComparePlan A/B/C/D data validations

2. **`excel/capbook/sheets/subsystems.py`**
   - Remove spill operator from `TradeTeamList` named range (~line 402)
   - Remove spill operator from `ExceptionUsedList` named range (~line 1349)
   - Either use fixed ranges or remove named ranges and use direct formula in data validation
