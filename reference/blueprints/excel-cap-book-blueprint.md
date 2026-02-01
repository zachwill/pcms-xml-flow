# Excel Cap Book Blueprint

**Updated:** 2026-02-01

---

## Vision

We build Excel workbooks for NBA salary cap analysts using Python and XlsxWriter.

The workbook feels like a **dense, reactive TUI** — not a marketing spreadsheet. Every pixel earns its place.

---

## Three pillars

### 1. Correct data

We shove authoritative data from Postgres into Excel. The `DATA_*` sheets are solid, trustworthy, reconcilable.

See `data-contract.md` for specifications.

### 2. Modern Excel

We use XlsxWriter with modern Excel features:
- `FILTER`, `SORTBY`, `UNIQUE`, `TAKE` — dynamic arrays
- `XLOOKUP` — clean lookups
- `LET` — readable complex formulas
- `LAMBDA` — reusable calculations as defined names

No legacy hacks. No helper columns where spill formulas work.

See `excel/XLSXWRITER.md` for patterns.

### 3. Dense, beautiful, reactive UI

**Dense:** Information-rich. Walls of numbers. No wasted space.

**Beautiful:** Aptos Narrow. Right-aligned numbers. Subtle borders. Consistent formatting.

**Reactive:** Inputs drive the view. Change something → everything updates. No "submit" buttons.

---

## Design principles

### Dense ≠ ugly

- **Typography:** Aptos Narrow (compact, modern, legible)
- **Alignment:** Numbers right, text left, decimals aligned
- **Borders:** Subtle section dividers, not heavy gridlines
- **Color:** Meaningful (status, alerts, input zones), not decorative
- **Whitespace:** Minimal but intentional

Think Bloomberg terminal, not clip-art spreadsheet.

### Inputs are light yellow

Excel convention. Editable cells have yellow background. Everything else is computed or locked.

### Reactivity via formulas + conditional formatting

No VBA. No macros. Pure Excel formulas that react to input changes. Conditional formatting for visual feedback.

### Adjacent context

Rules shown next to where they're needed. Trade matching tiers next to trade inputs. Min scale next to roster.

### Trust via reconciliation

Every total reconciles to `tbl_team_salary_warehouse`. Mismatches are loud.

---

## Target: 4-7 dense sheets

Not 13+ tabs. A handful of dense, self-contained views:

1. **PLAYGROUND** — Team roster + scenario inputs + reactive totals (first target)
2. **TRADE** — Multi-team trade construction with matching rules
3. **LEAGUE** — All 30 teams at a glance
4. **PICKS** — Draft pick ownership grid
5. Maybe 2-3 others as patterns emerge

Plus `DATA_*` sheets (hidden) and `META` sheet.

---

## What we're NOT building

- A CBA reference manual
- A step-by-step wizard
- A pretty dashboard for executives
- A web app in Excel

We're building **working tools for practitioners**.

---

## Next steps

See `excel/UI.md` for the authoritative PLAYGROUND spec (source of truth).

`specs/playground.md` is legacy notes and should defer to `excel/UI.md`.
