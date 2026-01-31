# Cover Spec

**Source:** `reference/warehouse/cover.json`

---

## 1. Purpose

A minimal cover/title page for Sean's workbook. Displays the workbook title and a last-opened date.

No data modeling or tooling logic lives here.

---

## 2. Key Inputs / Controls

None.

---

## 3. Key Outputs

| Cell | Value/Formula | Meaning |
|------|---------------|---------|
| `G42` | `"Data Warehouse"` | Workbook title text |
| `G46` | `=TODAY()` | Last-opened date stamp |

---

## 4. Layout / Zones

Only two populated cells in the sheet:
- `G42`: centered title block
- `G46`: date stamp beneath the title

---

## 5. Cross-Sheet Dependencies

### Cover references (outbound)
- None.

### Sheets that reference Cover (inbound)
- None observed (no `'Cover'!` references across the workbook export).

---

## 6. Key Formulas / Logic Patterns

```excel
=TODAY()
```

---

## 7. Mapping to Our Postgres Model

Not applicable (purely presentational).

---

## 8. Open Questions / TODO

None.
