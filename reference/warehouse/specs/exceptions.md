# exceptions.json — Trade Exceptions Spec

**File:** `reference/warehouse/exceptions.json`  
**Size:** ~18KB  
**Rows:** 163 (rows 4–97 contain data; rest are blank)

---

## 1. Purpose

Lists **active trade exceptions** available to NBA teams for the current season. Covers:

- **TPE** (Traded Player Exceptions) — named after the player whose trade generated the exception
- **MLE** (Mid-Level Exceptions) — Non-Taxpayer, Taxpayer, Room, Convertible
- **BAE** (Bi-Annual Exception)

This is a simple inventory: team, exception name/player, expiration date, type, amount.

---

## 2. Key Inputs / Controls

| Cell | Purpose |
|------|---------|
| `I4` | **Team selector** — e.g. `HOU`. Drives the filtered lookup in cols J–M. |

User enters a team code in `I4`; the adjacent zone shows that team's exceptions.

---

## 3. Key Outputs

### Main list (cols B–F)

All exceptions sorted by amount descending.

| Column | Header (row 3) | Content |
|--------|----------------|---------|
| B | Team | 3-letter team code (e.g. `BOS`) |
| C | Exception | Player name for TPE (e.g. `Porziņģis, Kristaps`) or MLE/BAE label |
| D | Date | Expiration date (`2026-07-07 00:00:00`) |
| E | Type | `TPE`, `MLE`, or `BAE` |
| F | Amount | Dollar amount (integer string, e.g. `22531707`) |

### Team lookup zone (cols I–M, starting row 3)

Filtered view for a single team.

| Column | Header (row 3) | Content |
|--------|----------------|---------|
| I | Team | Team selector (input cell I4) |
| J | (Exception) | Formula-driven filtered list of exception names |
| K | (Date) | Expiration dates |
| L | Type | Exception types |
| M | Amount | Amounts |

---

## 4. Layout / Zones

```
Row 1    : Title "Trade Exceptions"
Row 3    : Headers (B–F main; I–M team lookup)
Rows 4-97: Data rows (sorted by amount DESC)
Rows 98+ : Empty/placeholder
```

**Exception type breakdown (rows 4–97):**

| Type | Count | Example name |
|------|-------|--------------|
| TPE  | 50    | `Collins, John`, `Robinson, Duncan`, `Schröder, Dennis` |
| MLE  | 23    | `Non-Taxpayer MLE`, `Convertible Non-Taxpayer MLE`, `Taxpayer MLE`, `Room MLE` |
| BAE  | 21    | `Bi-annual` |

---

## 5. Cross-Sheet Dependencies

### Outbound (this sheet references)

None (no external sheets). The only formulas are **self-references** back into `Exceptions!$B:$F` for the team-filter panel.

### Inbound (other sheets reference this)

| File | How |
|------|-----|
| `the_matrix.json` | Displays each selected team’s top exceptions using `FILTER(Exceptions!$B:$F, Exceptions!$B:$B=<team>)` + `SORTBY` + `TAKE` |
| `exceptions.json` (self) | Row 4 col J uses `FILTER(Exceptions!$B:$F, Exceptions!$B:$B=$I$4)` for team lookup |

Related but **not this sheet**:
- `machine.json` references an external workbook range `'[2]Exceptions Warehouse - 2024'!…`.

---

## 6. Key Formulas / Logic

### Team lookup filter (cell J4)

```excel
=IFERROR(_xlfn.LET(
  _xlpm.f, _xlfn._xlws.FILTER(Exceptions!$B:$F, Exceptions!$B:$B=$I$4),
  _xlpm.sorted, _xlfn.SORTBY(_xlpm.f, --INDEX(_xlpm.f,,5), -1),
  _xlfn.TAKE(_xlfn.DROP(_xlpm.sorted,,1), MIN(5, ROWS(_xlpm.sorted)))
),"-")
```

**Logic:**
1. Filter main exception list (B:F) where team = cell I4
2. Sort by amount (col 5) descending
3. Take up to 5 rows, drop header
4. Display filtered subset for that team

---

## 7. Mapping to Postgres Model

| Sean Concept | Sean Column | Our Table | Our Column |
|--------------|-------------|-----------|------------|
| Team code | B | `pcms.exceptions_warehouse` | `team_code` |
| Exception name / player | C | `pcms.exceptions_warehouse` | `trade_exception_player_name` (for TPE) or exception_type_name (MLE/BAE) |
| Expiration date | D | `pcms.exceptions_warehouse` | `expiration_date` |
| Type | E | `pcms.exceptions_warehouse` | `exception_type_lk` |
| Amount | F | `pcms.exceptions_warehouse` | `remaining_amount` |

### Exception type mapping

| Sean Type | Our `exception_type_lk` values |
|-----------|--------------------------------|
| `TPE` | `TPE` (Trade Exception) |
| `MLE` | `MLE`, `CNTPMLE`, `NTPMLE`, `TPMLE`, `RMLE` depending on subtype |
| `BAE` | `BAE` |

### Gaps / Notes

- Sean distinguishes MLE subtypes in the **name** column (e.g. "Convertible Non-Taxpayer MLE", "Room MLE")
- Our warehouse stores these as distinct `exception_type_lk` codes
- Sean's amount column appears to be `remaining_amount` (balance left to use), not `original_amount`

---

## 8. Open Questions / TODO

1. **MLE subtype display** — Verify our `exception_type_name` lookup matches Sean's labels (e.g. "Non-Taxpayer MLE" vs our description).

2. **Trade Machine integration** — `machine.json` references `'Exceptions Warehouse - 2024'!` (external workbook link). We should confirm our `exceptions_warehouse` is being used correctly in trade validation.

3. **Filter logic for tooling** — Sean's sheet just shows all active exceptions. Our warehouse already filters to `record_status_lk = 'APPR'` and `remaining_amount > 0`.
