# Excel Workbook Progress

**Last updated:** 2026-02-03

---

## Current State: PLAYGROUND Sheet

### ✅ Done

**Layout & Structure**
- Freeze panes (rows 1-3, cols A-C)
- Left rail inputs (Trade Out/In, Waive, Stretch, Sign)
- Team selector with dropdown validation
- Hidden CALC sheet for scenario formulas

**KPI Bar (Row 1)**
- ROSTER count, TWO-WAY count, TOTAL salary (filled to 14)
- CAP/TAX/APR1/APR2 room with conditional formatting (green/red)

**Roster Grid**
- 6-year salary columns with % of cap
- Trade In + Sign additions appear; Trade Out/Waive show strikethrough
- Sorted by base-year salary descending

**Trade Math**
- Outgoing/incoming salary with trade bonus handling
- Apron post-trade, 250K padding, max incoming, remaining, legal status

**Scenario Logic**
- All inputs reactive: Trade Out/In, Waive, Stretch, Sign
- Roster fills to 12 at rookie minimum; slots 12–14 filled at vet minimum (Sean convention)

### 🚧 Remaining

**Multi-Year**
- [x] 6-year view (base year + 5)
- [x] Option year coloring (PO/TO)
- [ ] Early termination option (ETO) coloring

**Totals Completeness**
- [ ] Minimum Level and +/- Minimum
- [ ] Tax Payment / Tax Refund
- [ ] Apron 2 Level and +/- Apron 2
- [ ] Net Cost, Cost Savings

**Roster Fill Controls (Sean parity)**
- [x] Inputs for a *fill pricing date* (event date + delay days; e.g. trade date + 14)
- [x] Allow fill-to-12 basis selection (rookie min vs vet min) for realistic midseason modeling
- [x] Default fill-to-14 basis = vet min

**Additional Sections**
- [ ] Exceptions inventory
- [ ] Draft picks grid
- [ ] Depth chart
- [ ] Contract calculators

---

## Scenario Semantics (Modeling Contract)

These are the rules for what each input *means*. If these drift, the UI feels wrong.

### TRADE OUT
- Removes player's salary from team totals (affected years)
- Player stays visible, marked gray + strikethrough
- Uses `outgoing_apron_amount` for apron calculations

### TRADE IN
- Adds player's salary to team totals (affected years)
- Player appears in roster, marked purple
- Uses `incoming_cap_amount` / `incoming_apron_amount` (includes trade bonus)

### WAIVE
- Removes player from active roster count
- Player's cap hit becomes **Dead Money** (posture doesn't magically improve)
- Player marked gray + strikethrough

### STRETCH
- Does WAIVE + stretches remaining guaranteed across stretch years
- Changes *timing* of dead money, not whether it exists
- Formula: `2 * years_remaining + 1` stretch years

### SIGN (v1)
- Adds manual salary in **base year only**
- Future years default to 0 until multi-year signing terms added

---

## Non-Negotiables

1. **Multi-year is central.** 6-year view, not optional.
2. **Inputs stay in frozen left rail.** Columns A-C, always visible.
3. **KPI bar stays visible.** Frozen rows 1-3.
4. **Roster fills are first-class.** Cap room is meaningless without fills.
5. **Totals reconcile to warehouse.** Don't invent numbers.
6. **Color has semantics:**
   - Green = room / under threshold
   - Red = over / negative room
   - Purple = traded in
   - Gray + strikethrough = traded out / waived

---

## Named Ranges (API Contract)

These names are stable and used by formulas:

| Name | Location | Purpose |
|------|----------|---------|
| `SelectedTeam` | B1 | Team selector |
| `TradeOutNames` | B range | Trade out player names |
| `TradeInNames` | B range | Trade in player names |
| `WaivedNames` | B range | Waived player names |
| `StretchNames` | B range | Stretched player names |
| `SignNames` | B range | Signed player names |
| `SignSalaries` | C range | Signed player salaries |
| `MetaBaseYear` | META sheet | Base year for calculations |
| `MetaAsOfDate` | META sheet | As-of date |

---

## Key References

| Doc | Purpose |
|-----|---------|
| `excel/AGENTS.md` | Technical guide + architecture |
| `excel/XLSXWRITER.md` | XlsxWriter patterns and gotchas |
| `reference/blueprints/` | Design principles |

---

## CLI

```bash
uv run excel/export_capbook.py --out shared/capbook.xlsx --base-year 2025 --as-of today
```
