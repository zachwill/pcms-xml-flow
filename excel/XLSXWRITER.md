# XlsxWriter Reference for Coding Agents

## Pre-flight Checklist

Before writing any formula, verify:

- [ ] `Workbook(..., {"use_future_functions": True})` is set
- [ ] Function names are English (`SUM` not `SOMME`)
- [ ] Argument separators are commas (`,` not `;`)
- [ ] A1 refs are uppercase (`A1:D10` not `a1:d10`)
- [ ] Spill formulas use `write_dynamic_array_formula()` (no `{}` braces)
- [ ] Spill columns have `set_column(..., format)` applied (anchor format doesn't propagate)
- [ ] LAMBDA params use `_xlpm.` prefix (`_xlpm.x` not `x`)
- [ ] Spill refs use `ANCHORARRAY(F2)` not `F2#`
- [ ] Complex formulas: closing parens are commented and/or balance is asserted
- [ ] Defined names with dynamic/future functions use cell indirection

---

## 1. Workbook Setup

Always use:
```python
workbook = xlsxwriter.Workbook("out.xlsx", {"use_future_functions": True})
```

---

## 2. Formula API Selection

| Intent | Method | Notes |
|--------|--------|-------|
| Single value | `write_formula(cell, "=A1+B1")` | Default |
| Legacy CSE array | `write_array_formula(range, "{=...}")` | Braces required |
| Dynamic array (spill) | `write_dynamic_array_formula(cell, "=...")` | No braces |

**Decision rule:** If the formula returns multiple values, use `write_dynamic_array_formula()`.

**Spill functions** (always use `write_dynamic_array_formula`):
- `FILTER`, `UNIQUE`, `SORT`, `SORTBY`
- `SEQUENCE`, `RANDARRAY`
- `XLOOKUP` (when returning array/column)
- `DROP`, `TAKE`, `CHOOSECOLS`, `CHOOSEROWS`
- `HSTACK`, `VSTACK`, `TOCOL`, `TOROW`, `WRAPCOLS`, `WRAPROWS`, `EXPAND`
- `TEXTSPLIT`
- Any formula applied to a range that returns multiple values (e.g., `=LEN(A1:A100)`)

---

## 3. Critical Patterns

### 3.1 Spill Formatting

`write_dynamic_array_formula()` only formats the anchor cell. Spilled cells inherit **column format**.

```python
# ❌ BAD: format only applies to anchor
ws.write_dynamic_array_formula("D4", "=UNIQUE(A1:A100)", fmt)

# ✅ GOOD: set column format first
ws.set_column("D:D", 20, fmt)
ws.write_dynamic_array_formula("D4", "=UNIQUE(A1:A100)")
```

For multi-column spill grids:
```python
ws.set_column(COL_RANK, COL_RANK, 8, fmts["rank"])
ws.set_column(COL_NAME, COL_NAME, 20, fmts["name"])
ws.set_column(COL_SAL, COL_SAL, 12, fmts["money"])
ws.write_dynamic_array_formula(...)
```

### 3.2 LAMBDA Parameters

LAMBDA params require `_xlpm.` prefix in stored formulas (Excel hides this in UI):

```python
# ❌ BAD
"=LAMBDA(x, x*2)(5)"

# ✅ GOOD
"=LAMBDA(_xlpm.x, _xlpm.x*2)(5)"
```

Prefer defining as workbook name:
```python
wb.define_name("Double", "=LAMBDA(_xlpm.x, _xlpm.x*2)")
ws.write_formula("A1", "=Double(5)")
```

### 3.3 Spill References

`F2#` syntax doesn't work in stored formulas. Use `ANCHORARRAY()`:

```python
# ❌ BAD
"=COUNTA(F2#)"

# ✅ GOOD
"=COUNTA(ANCHORARRAY(F2))"
```

### 3.4 Defined Names + Dynamic Functions

Avoid future/dynamic functions directly in `define_name()`. Use cell indirection:

```python
# ❌ RISKY: may cause Excel warnings
wb.define_name("UniqueNames", "=UNIQUE(A1:A100)")

# ✅ SAFE: formula in cell, name points to cell
calc_ws.write_dynamic_array_formula("A1", "=UNIQUE(DATA!A1:A100)")
wb.define_name("UniqueNames", "=CALC!$A$1")
```

### 3.5 Parenthesis Balance in Nested Formulas

Complex LET/LAMBDA/MAP/FILTER formulas break silently on paren mismatch.

**Pattern 1:** Comment every closing paren:
```python
formula = (
    "=LET("
    "_xlpm.y,2025,"
    "_xlpm.names,FILTER(tbl[name],tbl[year]=_xlpm.y),"
    "_xlpm.sals,FILTER(tbl[sal],tbl[year]=_xlpm.y),"
    "MAP(InputNames,LAMBDA(_xlpm.p,"
    "IFERROR(XLOOKUP(_xlpm.p,_xlpm.names,_xlpm.sals,0),0)"
    "))"  # close LAMBDA, MAP
    ")"   # close LET
)
```

**Pattern 2:** Assert balance before writing:
```python
assert formula.count("(") == formula.count(")"), "Unbalanced parens"
ws.write_formula("A1", formula)
```

### 3.6 Manual `_xlfn.` Prefix Gotcha

If you manually add `_xlfn.` to ANY function, auto-prefixing is disabled for the ENTIRE formula.

```python
# ❌ BROKEN: LET won't get prefixed
"=LET(x,1,_xlfn.GREATEST(x,0))"

# ✅ WORKS: prefix everything manually
"=_xlfn.LET(_xlpm.x,1,_xlfn.GREATEST(_xlpm.x,0))"
```

Functions commonly needing manual prefix (not in xlsxwriter's list):
- `GREATEST`, `LEAST`
- `VSTACK`, `HSTACK`, `TOCOL`, `TOROW`, `WRAPCOLS`, `WRAPROWS`

---

## 4. Error Diagnosis

| Symptom | Cause | Fix |
|---------|-------|-----|
| `#NAME?` | Non-English function name | Use English: `SUM` not `SOMME` |
| `#NAME?` | Semicolon separators | Use commas: `SUM(1,2)` not `SUM(1;2)` |
| `#NAME?` | Missing `_xlfn.` prefix | Enable `use_future_functions` or prefix manually |
| `#NAME?` | Unbalanced parens | Count `(` vs `)`, add comments |
| `#NAME?` | Mixed manual/auto prefixing | If any `_xlfn.`, prefix ALL future functions |
| `@` in formula | Legacy formula, should be dynamic | Use `write_dynamic_array_formula()` |
| Spill cells unformatted | Anchor format doesn't propagate | Use `set_column(..., format)` |
| `0` in non-Excel viewers | No recalc capability | Pass `value=` param with precomputed result |
| Excel warnings on open | Future function in defined name | Use cell indirection pattern |

**Debug command** (inspect stored formula):
```bash
unzip -o file.xlsx -d /tmp/x && grep -o '<f>[^<]*</f>' /tmp/x/xl/worksheets/sheet1.xml
```

---

## 5. Quick Recipes

### Basic setup
```python
import xlsxwriter
wb = xlsxwriter.Workbook("out.xlsx", {"use_future_functions": True})
ws = wb.add_worksheet()
```

### Dynamic array with ANCHORARRAY reference
```python
ws.write_dynamic_array_formula("F2", "=FILTER(A:A, B:B>0)")
ws.write_formula("H2", "=COUNTA(ANCHORARRAY(F2))")
```

### XLOOKUP with fallback
```python
ws.write_formula("D1", '=IFNA(XLOOKUP(key, A:A, B:B), "Not found")')
```

### Named LAMBDA
```python
wb.define_name("ToCelsius", "=LAMBDA(_xlpm.f,(5/9)*(_xlpm.f-32))")
ws.write_formula("A1", "=ToCelsius(212)")
```

### Force cached result (for PDF/non-Excel consumers)
```python
ws.write_formula("A1", "=2+2", None, 4)  # 4 is the cached value
```

### Cell indirection for complex defined name
```python
calc = wb.add_worksheet("CALC")
calc.hide()
calc.write_dynamic_array_formula("A1", "=UNIQUE(DATA!A:A)")
wb.define_name("UniqueItems", "=CALC!$A$1")
```

### Formatted spill grid
```python
fmt_name = wb.add_format({"bold": True})
fmt_sal = wb.add_format({"num_format": "#,##0"})

ws.set_column("C:C", 20, fmt_name)
ws.set_column("D:D", 12, fmt_sal)

ws.write_dynamic_array_formula("C3", "=PlayerNames")
ws.write_dynamic_array_formula("D3", "=PlayerSalaries")
```

---

## 6. Formula Building Helper

For complex formulas, use a builder pattern:

```python
def build_formula(*parts: str) -> str:
    """Concatenate formula parts and validate paren balance."""
    formula = "".join(parts)
    opens = formula.count("(")
    closes = formula.count(")")
    if opens != closes:
        raise ValueError(f"Unbalanced: {opens} open, {closes} close\n{formula}")
    return formula

formula = build_formula(
    "=LET(",
    "_xlpm.x,1,",
    "_xlpm.y,2,",
    "_xlpm.x+_xlpm.y",
    ")",  # close LET
)
```
