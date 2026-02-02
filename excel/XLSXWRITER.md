# XlsxWriter docs for coding agents

---

## Tier 0 - Non-negotiables (must know)

### 0.1 Formula text rules (most common `#NAME?` causes)
- **Function names must be English** in the file: `SUM`, not `SOMME`.
- **Argument separators must be commas `,`**, not semicolons `;` (even if user's Excel UI uses `;`).
- **Use valid Excel syntax**; if Excel wouldn't accept it, XlsxWriter can't "fix" it.

### 0.2 XlsxWriter does **not** calculate formulas
- XlsxWriter stores formulas but generally stores a **result of `0`** and sets "recalc on open".
- Many non-Excel viewers (some mobile apps, Excel Viewer, PDF converters, etc.) **won't recalc** → they show `0`.
- Workaround: pass the optional **`value`** parameter to `write_formula()` / `write_array_formula()` when you need precomputed results.

### 0.3 Choose the correct formula-writing API
- **Single-value formulas**: `worksheet.write_formula(cell, "=A1+B1", fmt=None, value=None)`
- **Legacy array/CSE formulas** (with braces): `worksheet.write_array_formula(range, "{=...}", ...)`
- **Dynamic array formulas (Excel 365 spill)**: `worksheet.write_dynamic_array_formula(range_or_single_cell, "=...")`
  - **Do NOT** add `{}` braces here.

### 0.4 "Future functions" and prefixes (`_xlfn.`)
Excel stores many newer functions with prefixes in the file format.

**Recommended for simplicity**: enable auto-prefixing for Excel 2010+ future functions
   ```python
   workbook = xlsxwriter.Workbook("out.xlsx", {"use_future_functions": True})
   ```

---

## Tier 1 - Recommended patterns for modern Excel (safe defaults)

### 1.1 Default setup recommendation
Use this unless you have a strong reason not to:
```python
workbook = xlsxwriter.Workbook("out.xlsx", {"use_future_functions": True})
worksheet = workbook.add_worksheet()
```

### 1.2 Dynamic arrays: always use `write_dynamic_array_formula()` for spill behavior
Use it for functions like `FILTER`, `UNIQUE`, `SORT`, `SEQUENCE`, `XLOOKUP` (when returning arrays), `DROP`, `TAKE`, `HSTACK`, `VSTACK`, etc.

```python
worksheet.write_dynamic_array_formula("F2", "=FILTER(A2:D100, C2:C100=K2)")
```

Why this matters:
- Prevents Excel from treating it as a "legacy single-value" formula that later displays an `@` (implicit intersection).

### 1.3 Referring to spilled ranges: you can't reliably write `F2#`
Excel's spill operator `#` is **a UI/runtime operator**; it isn't stored the same way.

**Use `ANCHORARRAY()`** in stored formulas as the equivalent of `F2#`:
```python
# Equivalent to Excel: =COUNTA(F2#)
worksheet.write_formula("J2", "=COUNTA(ANCHORARRAY(F2))")
```

### 1.4 LAMBDA: parameter names must use `_xlpm.` internally
When writing a `LAMBDA()` formula text into a file, Excel requires parameter references to be stored with an `_xlpm.` prefix (Excel won't show it in the UI, but it must be in the file).

Inline call pattern:
```python
worksheet.write_formula("A1", "=LAMBDA(_xlpm.temp, (5/9)*(_xlpm.temp-32))(212)")
```

**Preferred pattern:** define it once as a workbook name and call it like a function:
```python
workbook.define_name("ToCelsius", "=LAMBDA(_xlpm.temp, (5/9)*(_xlpm.temp-32))")
worksheet.write_formula("A1", "=ToCelsius(212)")
```

### 1.5 XLOOKUP: make failures explicit
A robust, production-friendly pattern:
```python
worksheet.write_formula(
    "D2",
    '=IFNA(XLOOKUP("k3", A2:A100, B2:B100), "Not found")'
)
```

(Use `IFERROR` if you also want to catch non-`#N/A` errors.)

---

## Tier 2 - Gotchas & debugging bumpers (what usually goes wrong)

### 2.1 `#NAME?` (or formulas "work only after editing")
Common causes:
- Non-English function name (Excel stores formulas in US English internally).
- Using `;` instead of `,`.
- Using Excel 2010+ functions without `_xlfn.` prefix **and** not enabling `use_future_functions`.
- Writing a dynamic-array-intended formula with `write_formula()` instead of `write_dynamic_array_formula()` (Excel may reinterpret it).

Debug loop:
1) Paste the formula into Excel (desktop) and confirm it evaluates.
2) Ensure commas `,` and English function names.
3) Enable `{"use_future_functions": True}` if using newer functions.
4) If it should spill, rewrite using `write_dynamic_array_formula()`.

### 2.1.1 Manual `_xlfn.` disables auto-prefixing for the ENTIRE formula

**Critical gotcha:** If you manually add `_xlfn.` to ANY function in a formula, xlsxwriter's
`use_future_functions` auto-prefixing is **disabled for that entire formula**.

Example problem:
```python
# GREATEST/LEAST are very new (2022+) and not in xlsxwriter's auto-prefix list.
# You might try adding _xlfn. manually:
"=LET(x,1,_xlfn.GREATEST(x,0))"  # ❌ BROKEN

# But now LET() won't get auto-prefixed! Result: #NAME? error.
```

**Fix:** If you manually prefix ANY function, you must manually prefix ALL future functions:
```python
"=_xlfn.LET(x,1,_xlfn.GREATEST(x,0))"  # ✅ Works
```

Functions that commonly need manual `_xlfn.` (not in xlsxwriter's list):
- `GREATEST`, `LEAST` (Excel 2022+)
- `VSTACK`, `HSTACK`, `TOCOL`, `TOROW`, `WRAPCOLS`, `WRAPROWS` (may vary by xlsxwriter version)

**Debug tip:** Unzip the `.xlsx` and inspect the formula in `xl/worksheets/sheet1.xml`:
```bash
unzip -o file.xlsx -d /tmp/inspect && grep 'GREATEST\|LET' /tmp/inspect/xl/worksheets/sheet1.xml
```
If you see `LET(` without `_xlfn.LET(`, that's the problem.

### 2.2 Excel shows `@` inserted into your formula
- `@` is the **Implicit Intersection Operator** Excel 365 displays for "legacy" formulas that reduce a range to one value.
- This is usually a sign you intended a spill but wrote a legacy/single-cell formula.
- Fix: use `write_dynamic_array_formula()` (or rewrite formula to be explicitly dynamic-array compatible).

### 2.3 Don't add `{}` braces to dynamic arrays
- `{=...}` is for legacy CSE arrays (`write_array_formula`).
- Dynamic arrays should be written without braces (`write_dynamic_array_formula`).

### 2.4 Literal strings that start with `=`
By default, `worksheet.write()` treats strings starting with `=` as formulas.
- If you need the literal text `=XLOOKUP(...)` displayed as text, use `write_string()` or disable `strings_to_formulas`.

### 2.5 A1 ranges must be uppercase
XlsxWriter expects A1 ranges like `A1:D10` (uppercase), not `a1:d10`.

### 2.6 `0` results in non-Excel apps (PDF renderers, etc.)
If consumers won't recalc formulas:
- Pass `value=` (precomputed result) when writing formulas:
```python
worksheet.write_formula("A1", "=2+2", None, 4)
```

---

## Tier 3 - Copy/paste recipes (minimal, working snippets)

### 3.1 FILTER spill + spill reference via ANCHORARRAY
```python
import xlsxwriter

wb = xlsxwriter.Workbook("spill.xlsx", {"use_future_functions": True})
ws = wb.add_worksheet()

ws.write_row("A1", ["Item", "Qty"])
ws.write_row("A2", ["apple", 10])
ws.write_row("A3", ["banana", 5])
ws.write_row("A4", ["cherry", 12])

# Spill result starting at F2.
ws.write_dynamic_array_formula("F2", "=FILTER(A2:A100, B2:B100>6)")

# Equivalent to Excel: =COUNTA(F2#)
ws.write_formula("H2", "=COUNTA(ANCHORARRAY(F2))")

wb.close()
```

### 3.2 XLOOKUP with fallback
```python
import xlsxwriter

wb = xlsxwriter.Workbook("xlookup.xlsx", {"use_future_functions": True})
ws = wb.add_worksheet()

ws.write_row("A1", ["Key", "Value"])
ws.write_row("A2", ["k1", 10])
ws.write_row("A3", ["k2", 20])

ws.write_formula("D1", '=IFNA(XLOOKUP("k3", A2:A3, B2:B3), "Not found")')

wb.close()
```

### 3.3 Define + call a LAMBDA (strongly preferred)
```python
import xlsxwriter

wb = xlsxwriter.Workbook("lambda.xlsx", {"use_future_functions": True})
ws = wb.add_worksheet()

wb.define_name("ToCelsius", "=LAMBDA(_xlpm.temp, (5/9)*(_xlpm.temp-32))")
ws.write_formula("A1", "=ToCelsius(212)")

wb.close()
```

### 3.4 Force stored results for a formula (non-Excel viewers)
```python
ws.write_formula("A1", "=2+2", None, 4)
```

---

## Quick "agent checklist" (paste into PR comments)
- [ ] All formulas use **English** function names.
- [ ] All formulas use **commas**, not semicolons.
- [ ] Use `write_dynamic_array_formula()` for anything that should **spill**.
- [ ] Don't use `F2#`; use `ANCHORARRAY(F2)` to reference spilled output.
- [ ] LAMBDA parameter references use `_xlpm.` inside the formula text.
- [ ] Enable `Workbook(..., {"use_future_functions": True})` unless manually prefixing.
- [ ] **If manually adding `_xlfn.` to ANY function, add it to ALL future functions in that formula.**
- [ ] If output is consumed by non‑Excel tools, pass `value=` for important formulas.
