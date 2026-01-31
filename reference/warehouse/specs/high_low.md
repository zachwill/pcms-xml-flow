# High / Low Spec

**Source:** `reference/warehouse/high_low.json`  
**Rows:** 451

---

## 1. Purpose

`High Low` is a **salary ranking & comparison tool**.

It displays NBA players sorted by salary (high → low) with:

- Multi-year salary columns
- % of cap columns (per year)
- A small “salary search” widget to filter players within a salary band

Use case: quickly identify players at similar salary levels for trade matching or market comparisons.

---

## 2. Key Inputs / Controls

The salary-search control block:

| Cell | Meaning |
|---|---|
| `V3` | Salary target (user input) |
| `V2` | Upper bound (“Up to”) = `V3 + 1,000,000` |
| `V4` | Lower bound (“Down to”) = `V3 - 1,000,000` |

---

## 3. Key Outputs

### A) Main ranking table (cols A–S)

Row 1 headers:
- `#`, `Tier`, `Player`, `Age`, `Team`, `2025`, `2026`, …, `Total`

Row 2 and down: one player per row.

Key columns:

| Col | Header | Notes |
|---|---|---|
| A | (sorted names) | generated list sorted by 2025 salary |
| B | `#` | rank (1,2,3…) |
| C | `Tier` | `=XLOOKUP(player, Y!B:B, Y!AM:AM)` (Salary Book tier string) |
| D | `Player` | mirrors column A |
| E | `Age` | pulled from Y via `INDEX(Y!$C:$AJ, ...)` |
| F | `Team` | pulled from Y |
| G, I, K, M, O, Q | 2025–2030 salary | pulled from Y |
| H, J, L, N, P, R | % of cap | salary / `SystemValues[Salary Cap]` |
| S | `Total` | `=SUMIF(G2:R2,">1")` |

### B) Salary search results (cols X–AK)

Filter output begins near `X2` and returns players whose **2025 salary** is within ±$1M of `V3`.

Filter formula pattern (from the sheet body):
```excel
=FILTER(D:Q, (G:G<>"") * (G:G >= $V$3 - 1000000) * (G:G <= $V$3 + 1000000), "")
```

---

## 4. Layout / Zones

- Row 1: headers
- Rows 2–451: ranking table
- Salary search:
  - inputs around `U2:V4`
  - results in `X:AK`

---

## 5. Cross-Sheet Dependencies

### High Low references (outbound)

| Sheet | How |
|---|---|
| `Y` | primary source for player list and salaries |
| `SystemValues` | cap amounts for % of cap columns |

Evidence:
- Player list generator in `A2` references `Y!$B$3:$B$530` and `Y!$D$3:$D$530`.
- % of cap columns use `XLOOKUP(<year>, SystemValues[[Season]], SystemValues[[Salary Cap]])`.

### Sheets that reference High Low (inbound)

None found (this appears to be a standalone tool sheet).

---

## 6. Key Formulas / Logic Patterns

### Sorted player list (cell `A2`)

```excel
=_xlfn.LET(
  _xlpm.names,    Y!$B$3:$B$530,
  _xlpm.salaries, Y!$D$3:$D$530,
  _xlpm.keep,     (_xlpm.salaries<>"")*(_xlpm.salaries<>"-")*ISNUMBER(_xlpm.salaries),
  _xlfn.SORTBY( _xlfn._xlws.FILTER(_xlpm.names, _xlpm.keep), _xlfn._xlws.FILTER(_xlpm.salaries, _xlpm.keep), -1 )
)
```

### Tier lookup (cell `C2`)

```excel
=_xlfn.XLOOKUP(D2,Y!B:B,Y!AM:AM)
```

### Dynamic lookup for attributes / salaries (pattern used in `E2`, `F2`, `G2`, etc.)

```excel
=IFERROR(
  _xlfn.LET(
    _xlpm.r, MATCH($D2, Y!$B:$B, 0),
    _xlpm.c, MATCH($G$1, Y!$C$2:$AJ$2, 0),
    _xlpm.v, INDEX(Y!$C:$AJ, _xlpm.r, _xlpm.c),
    IF(_xlpm.v=0, "-", _xlpm.v)
  ),
  "-"
)
```

### % of cap (example `H2`)

```excel
=IFERROR(G2/_xlfn.XLOOKUP(G$1,SystemValues[[#All],[Season]],SystemValues[[#All],[Salary Cap]],),"-")
```

---

## 7. Mapping to Postgres

| High Low concept | Our table/view |
|---|---|
| Player list + multi-year salaries | `pcms.salary_book_warehouse` |
| Cap per year | `pcms.league_system_values` |
| % of cap | computed at query time |

Notes:
- The workbook’s “Tier / SB” comes from Y column `AM`. We don’t currently store an equivalent in `salary_book_warehouse`.

---

## 8. Open Questions / TODO

- [ ] Document what the “SB” / tier classification means (Y column `AM`).
- [ ] The sheet only filters/sorts by **2025** salary. Confirm whether other years are ever used for sorting.
