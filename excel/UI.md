# PLAYGROUND (Excel) — Dense Reactive UI Spec (SOURCE OF TRUTH)

**Status:** Active / authoritative.

This file describes what we are actually building: a **dense, reactive, “terminal-like”** Excel working surface for NBA cap scenario modeling.

## Read this first (anti-shortcut warning)

- This spec is intentionally **not** an “MVP roster + totals”. Sean’s workbook works because it keeps *everything visible* and *everything reacts*.
- **Do not simplify away** multi-year, roster fills, thresholds, exceptions, draft assets, depth, trade math, or calculators just because they’re “extra”. They are the product.
- This doc **supersedes** `reference/blueprints/specs/playground.md` (which is now “principles + older notes”). If there’s disagreement: **follow `excel/UI.md`.**

---

## North star

Build an Excel sheet that feels like a **Bloomberg terminal / reactive dashboard**:

- **Dense:** minimal whitespace, high information per screen.
- **Reactive:** every keystroke in an input cell recomputes roster + totals + KPIs.
- **Multi-year:** you can see 4–6 years across without leaving the sheet.
- **Trustworthy:** totals reconcile to our authoritative warehouse tables.

The sheet is not a wizard and not a form. It’s one live surface.

---

## Non‑negotiables (what agents keep “shortcutting”)

1. **Multi-year grid is central** (base year + 5 years). Not optional.
2. **Inputs do not live in the middle.** Inputs are in a fixed left rail (frozen columns).
3. **KPI bar exists and stays visible** (frozen rows). It answers “what’s our situation *right now*?”
4. **Roster fills and thresholds are first-class.** Cap/tax/apron room is meaningless without fills.
5. **Color has semantics:**
   - Green = room / under threshold
   - Red = over / negative room
   - Purple = traded in / added
   - Gray + strikethrough = traded out / waived
6. **Everything updates from the same state** (SelectedTeam + scenario inputs). No hidden “submit”.
7. **Offline workbook.** No live DB connections. All data comes from embedded `DATA_*` sheets.

---

## Two canonical references (the “why”)

### 1) Sean’s workbook (functionality completeness)

Sean’s Playground includes (at minimum):
- Team context header (team / base year / as-of / repeater)
- Multi-year roster grid with option coloring (PO/TO/ETO), traded-out strike, traded-in highlight
- Trade inputs (out/in) that immediately affect totals and trade math
- Waive/stretch and dead money
- Signings and pick signings
- Roster fills (rookie/vet mins) and dead money line
- **Comprehensive totals** per year: min/cap/tax/aprons, room/over, tax payment, net cost
- Depth chart (by year)
- Draft picks ownership grid
- Trade machine / matching zone
- Contract calculators (forward/backward) + renegotiation calculator

### 2) The React app screenshot (information design)

The React app nails:
- A top KPI bar that summarizes the team’s posture instantly
- A dense roster grid with secondary details under each player
- Sidebar-like breakdowns (cap outlook, charts)
- Explicit “badges” (Under Tax, etc.)

In Excel, we borrow the **clarity and hierarchy**, but we keep the **Sean-level completeness and density**.

---

## Interaction model (what reacts to what)

### Inputs (left rail) drive everything
When the user changes any of these:
- **Selected team**
- **Trade Out** names
- **Trade In** names
- **Waive** names
- **Stretch** names
- **Sign** names + salaries (v1: base-year only)
- (Later) contract calculator / term inputs

Then all of these must update automatically:
- Roster grid (including status + formatting)
- Trade math (out/in totals, match %)
- KPI bar numbers + status badge
- Totals vs thresholds (cap/tax/aprons, min)
- Roster fill counts and fill dollars
- Downstream sections (exceptions, picks, depth) for that team

### “Reactive surface” rules
- No buttons required for core reactivity (typing is enough).
- Clearing an input cell is the “reset”.
- Unknown names should not break the sheet: lookups should resolve to 0 / blank and surface an error indicator (see “Error handling”).

---

## Scenario semantics (what each input *means*)

This is the critical modeling contract. If these rules drift, the UI will feel "wrong" even if the formulas calculate.

### TRADE OUT
- Removes the player’s salary from team totals for the affected years.
- Player stays visible in the roster view but is marked **OUT** (gray + strikethrough).

### TRADE IN
- Adds the player’s salary to team totals for the affected years.
- Player appears in the roster view marked **IN** (purple).

### SIGN (v1)
- Adds a manual salary **only in the base year**.
- Future years default to 0/blank until we add multi-year signing terms.

### WAIVE
- **Immediately adds dead money**.
- Practical effect (v1 modeling):
  - Player is removed from active roster count (so fills may increase).
  - The player’s cap hit is reclassified into a **Dead Money** line item (so cap/tax/apron posture does not magically improve).

### STRETCH
- Does **WAIVE** + stretches the resulting dead money.
- Practical effect: remaining guaranteed amounts are converted into a multi-year dead money stream (spread across stretch years), and active roster count decreases (so fills may increase).

(Exact stretch rules can be implemented incrementally; the key is: stretch changes *timing* of dead money, not whether it exists.)

---

## Layout contract (what goes where)

This layout is designed around Excel’s freeze panes.

### Freeze panes (required)
- **Frozen rows:** 1–3
  - Row 1: Team context (team selector + team name + base year + as-of)
  - Row 2: KPI bar (cap/tax/apron posture + roster counts)
  - Row 3: Column headers for the roster grid
- **Frozen columns:** A–C
  - Column A: section labels
  - Column B: input cells (yellow)
  - Column C: secondary inputs (e.g., signing salary)

### Spatial hierarchy
- **Top**: team context + KPI bar
- **Left rail** (always visible): scenario inputs + trade math
- **Right/main grid**: roster multi-year + totals multi-year
- **Below**: exceptions, draft assets, depth chart, calculators (still same sheet; scroll down)

---

## Concrete grid contract (target coordinates)

This is the *intended* geometry so the sheet stays code-generatable and predictable.

### Freeze boundary
- Freeze at **row 3** and **column C**.
  - Rows 1–3 stay visible while scrolling down.
  - Columns A–C stay visible while scrolling right.

### Left rail inputs (columns A–C)
- `SelectedTeam`: **B1** (data validation list of team codes)
- **Trade Out** (6 slots): **B5:B10** → named range `TradeOutNames`
- **Trade In** (6 slots): **B13:B18** → named range `TradeInNames`
- **Waive** (3 slots): **B21:B23** → named range `WaivedNames`
- **Stretch** (3 slots): **B24:B26** → named range `StretchNames`
- **Sign** (2 slots):
  - Names: **B29:B30** → named range `SignNames`
  - Salaries: **C29:C30** → named range `SignSalaries`

(Exact row numbers can move during iteration, but the *concept* is fixed: inputs live in the frozen left rail and are exposed via stable named ranges.)

### Roster grid header (row 3, starts at column D)
The roster grid starts immediately right of the left rail.

Recommended columns:
- **D:** `#`
- **E:** `Player`
- Then repeating pairs for each year in horizon (base year … base+5):
  - **F/G:** `25-26 Salary`, `25-26 %`
  - **H/I:** `26-27 Salary`, `26-27 %`
  - **J/K:** `27-28 Salary`, `27-28 %`
  - **L/M:** `28-29 Salary`, `28-29 %`
  - **N/O:** `29-30 Salary`, `29-30 %`
  - **P/Q:** `30-31 Salary`, `30-31 %`
- **R:** `Status`
- (Optional) **S:** `Agent`

### ASCII sketch (density / intent)

```
FROZEN ROWS 1–3
┌─────────────────┬──────────────────────────────────────────────────────────────────────────┐
│ A–C (FROZEN)    │ D… (SCROLL)                                                               │
├─────────────────┼──────────────────────────────────────────────────────────────────────────┤
│ Team: [POR ▼]   │ Portland Trail Blazers     (base year from META)     (as-of from META)    │
│ KPI BAR         │ ROSTER  TWO-WAY  TOTAL   CAP ROOM   TAX ROOM   APR1   APR2   [STATUS]     │
│ (inputs rail)   │ #  Player   25-26  %  26-27  %  27-28  %  28-29  % ... Status  Agent      │
├─────────────────┼──────────────────────────────────────────────────────────────────────────┤
│ TRADE OUT       │ 1  Grant   32.4M 21% 34.8M 21% ...                                         │
│ [____]          │ 2  Simons  27.7M 18% 29.1M 18% ...   OUT (struck/gray)                     │
│ ...             │ 3  Butler  29.5M 19% 31.0M 19% ...   IN (purple)                           │
│                 │ …                                                                          │
│ TOTALS ↓        │ Min/Cap/Tax/Aprons stack by year                                           │
│ EXCEPTIONS ↓    │ Draft assets ↓  Depth chart ↓  Calculators ↓                               │
└─────────────────┴──────────────────────────────────────────────────────────────────────────┘
```

---

## Worksheet regions (minimum set)

### A) Team context (frozen)
- **Team selector** (yellow input) → defines `SelectedTeam`
- Base year and as-of date displayed from META (`MetaBaseYear`, `MetaAsOfDate`)
- Optional: repeater flag (from warehouse)

### B) KPI bar (frozen)
For **base year** (the “current posture”), show:
- Roster count (standard) + two-way count
- Total salary (filled-to-14 view)
- Cap room (CapLevel − FilledSalary)
- Tax room (TaxLevel − FilledSalary)
- Apron 1 room (Apron1Level − FilledSalary)
- Apron 2 room (Apron2Level − FilledSalary)
- Status badge (Under Tax / Tax Team / Over Apron 1 / etc.)

### C) Inputs (left rail, frozen)
Minimum input slots (tunable, but do not remove the concept):
- Trade Out ×6 (names)
- Trade In ×6 (names)
- Waive ×3 (names)
- Stretch ×3 (names)
- Sign ×2 (name + salary; **v1 applies to base year only**)

Later expansions (still same left rail concept):
- Signing type dropdown (min/room/MLE/etc.)
- Multi-year signing terms

### D) Trade math (left rail)
For base year:
- Outgoing salary (from team roster lookups)
- Incoming salary (league-wide lookup)
- Match % and/or rule indicator (125% + $250K, etc.)

### E) Roster grid (main)
The roster grid is the visual center.

Required columns:
- Rank (#)
- Player name
- For each year in horizon: Salary + % of cap
- Status (OUT / IN / WAIVED / STRETCH / SIGN / blank)
- (Later) Agent, contract tags (TO/PO/ETO), two-way badge

Required behaviors:
- Sorted (usually by base-year salary descending)
- Traded-out / waived players remain visible but visually marked
- Trade-ins and signings appear and are highlighted

### F) Roster fills (main)
Per year:
- Roster count
- Rookie min fills
- Vet min fills (if you model it)
- Dead money line

### G) Totals vs thresholds (main)
Per year, include (Sean-complete):
- Team Salary
- Team Salary (fill to 14) / Team + Fills
- Minimum Level and +/- Minimum
- Cap Level and Cap Space
- Tax Level and +/- Tax
- Tax Payment (if applicable)
- Tax Refund (when applicable)
- Apron 1 Level and +/- Apron 1
- Apron 2 Level and +/- Apron 2
- Net Cost (salary + tax)
- Cost Savings (vs baseline)
- Baseline Cost (reference)

### H) Exceptions (below)
Show exception inventory for the selected team (from `tbl_exceptions_warehouse`).

### I) Draft assets (below)
Draft pick ownership grid (from `tbl_draft_picks_warehouse`).

### J) Depth chart (below)
A compact by-position view, reactive to roster changes.

### K) Contract calculators (below)
Forward max contract calculator, backward “start from total”, and renegotiation calculator.

---

## Visual language (formatting rules)

- **Inputs:** light yellow fill, unlocked.
- **Numbers:** right-aligned, comma-separated, no decimals for large money.
- **Millions shorthand:** KPI bar can use custom number formats like `23M`, `-8M`.
- **Conditional formatting semantics:**
  - Room >= 0 → green
  - Room < 0 → red
  - Trade out / waived → gray + strikethrough
  - Trade in → purple (bold)
  - Sign → distinct highlight (green or yellow, but consistent)

---

## Data & calculation contract (don’t invent numbers)

### Authoritative sources (DATA sheets)
- `tbl_salary_book_yearly` — player salaries by year
- `tbl_team_salary_warehouse` — authoritative team totals and counts
- `tbl_system_values` — cap/tax/apron/min levels
- `tbl_minimum_scale` — minimum salary amounts for fills
- `tbl_tax_rates` — tax brackets
- `tbl_dead_money_warehouse` — baseline dead money by team/year (scenario adds layer on top)
- `tbl_exceptions_warehouse` — exceptions inventory
- `tbl_draft_picks_warehouse` — draft assets

### Trust / reconciliation rule
- The sheet must always be able to show a “base” view that matches `tbl_team_salary_warehouse`.
- Scenario modifications must be explicit additions/removals layered on top.

### Named ranges (expected)
These names are part of the UI API:
- `SelectedTeam`
- `TradeOutNames`
- `TradeInNames`
- `WaivedNames`
- `StretchNames`
- `SignNames`
- `SignSalaries`

(Additional names are fine; these should remain stable.)

---

## Error handling (must not feel brittle)

- If a typed player name cannot be found:
  - Salary lookup should return **0** (not `#N/A`) in computed totals.
  - The roster/status area should show a clear indicator (e.g., status = `UNKNOWN` or a red cell note).
- Duplicate names in inputs should not double-count silently; either de-dupe or visibly flag.

---

## Acceptance criteria (how we know it’s “real”, not a shortcut)

The sheet meets the bar when:

1. **Changing `SelectedTeam` repopulates the entire surface** (roster, totals, picks, exceptions).
2. **Trade Out**:
   - The player row is struck/gray.
   - Outgoing salary increases.
   - Cap/tax/apron rooms update.
3. **Trade In**:
   - The player appears (purple).
   - Incoming salary increases.
   - Cap/tax/apron rooms update.
4. **Waive**:
   - The player is struck/gray.
   - The waived player’s cap hit shows up immediately in **Dead Money** (so posture doesn’t falsely improve).
   - Totals/rooms update (including any added roster fills due to the roster spot opening).
5. **Stretch**:
   - The player is struck/gray.
   - Dead money is **re-timed** across stretch years (visible in the multi-year dead money line).
   - Totals/rooms update (including roster fills).
6. **Sign** (v1):
   - New row appears with entered salary.
   - Salary affects **base year only**.
   - Totals and rooms update.
7. **Multi-year is visible**: at least 4 years shown by default with the ability to scroll to 6.
8. **Totals are Sean-complete**: the threshold stack exists (min/cap/tax/aprons), not just “cap space”.

---

## Delivery guidance (no “phases”, just working slices)

When implementing, work in **vertical slices** that keep the sheet coherent:

- Slice A: Layout + freeze panes + stable named ranges (inputs exist and are clearly marked)
- Slice B: Base roster multi-year grid + base totals that reconcile to warehouse
- Slice C: Trade out/in reactivity across roster + KPIs + totals
- Slice D: Waive/sign reactivity + roster fills + minimum/cap/tax/apron stack
- Slice E: Exceptions + draft assets + depth chart blocks (still same sheet)
- Slice F: Trade machine rules + contract calculators

Each slice should leave the workbook in a usable, dense state—no “toy” intermediate UI.

---

## Appendix A — React app reference (keep this feel)

### KPI bar (posture at a glance)

What the KPI bar communicates instantly:
- roster and two-way counts
- total salary
- cap room (negative = over)
- room under tax and aprons
- a badge that summarizes posture (e.g., Under Tax)

Example (illustrative):

```
Atlanta Hawks    ROSTER  TWO-WAY   TOTAL      CAP SPACE   TAX ROOM   APRON 1   APRON 2
                 15        3     $187.5M     -$32.9M     $6.8M     $14.8M    $26.7M
```

### Roster rows (dense + secondary detail)

The roster grid should support a “two-line row” feel (even if implemented as adjacent rows):

- Line 1: player name + multi-year salaries + total + agent
- Line 2: position / age / YOS + % of cap by year + contract tags (TO/PO/etc.)

---

## Appendix B — Sean’s completeness checklist (don’t drop these)

If a feature exists in Sean’s Playground, it should have an intentional home here:

- Roster fills and dead money are visible (not hidden)
- Full threshold stack (min/cap/tax/aprons) per year
- Draft pick ownership grid
- Depth chart mini-view
- Trade matching zone
- Contract calculators (forward/backward) + renegotiation

When in doubt: err toward **showing more**, not less.
