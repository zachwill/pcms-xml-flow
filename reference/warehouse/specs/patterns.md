# Common Patterns (Sean workbook)

This doc captures the **repeated formula patterns / analyst mental models** that show up across many sheets (Playground, Team, Finance, GA, Team Summary, The Matrix, etc.). The goal is to avoid re-documenting the same logic N times.

If you’re reading a presentation sheet spec and thinking “this is the same roster + cap math again”, it probably is.

---

## 1) Roster list by team (Y → FILTER → SORTBY)

**Where:** `playground.json`, `team.json`, `finance.json`, `ga.json`, `the_matrix.json`, `machine.json` roster panels.

**Pattern:**
- Filter the Y warehouse to a team.
- Pull `Name`.
- Sort descending by the selected year’s salary.

Canonical example (Playground `A4`):
```excel
=LET(
  team,   $D$1,
  yr,     E1,
  hdrs,   Y!$D$2:$P$2,
  tbl,    Y!$B$3:$P$1137,
  colIx,  MATCH(yr, hdrs, 0) + 2,
  rows,   FILTER(tbl, INDEX(tbl,,2)=team),
  names,  INDEX(rows,,1),
  sal,    INDEX(rows,,colIx),
  key,    IFERROR(--sal, -10000000000),
  SORTBY(names, key, -1)
)
```

**Postgres analog:**
```sql
SELECT player_name, cap_amount
FROM pcms.salary_book_yearly
WHERE team_code = $team AND salary_year = $year
ORDER BY cap_amount DESC;
```

---

## 2) Salary lookup by player + year header

**Where:** almost everywhere that renders a multi-year grid.

**Pattern:** match a player’s row in Y by name, then match the year header.

```excel
=IFERROR(
  LET(
    r, MATCH(player_name_cell, Y!$B:$B, 0),
    c, MATCH(year_header_cell, Y!$D$2:$J$2, 0),
    v, INDEX(Y!$D:$J, r, c),
    IF(v="-", 0, v)
  ),
0)
```

**Note:** Excel uses name-based lookup; tooling should prefer `player_id` joins.

---

## 3) Threshold lookups (System Values)

**Where:** Team/Playground/Finance/Matrix/Team Summary.

Pattern: `XLOOKUP(year, SystemValues[Season], SystemValues[Salary Cap|Tax Level|Apron 1|Apron 2|Minimum Level])`.

**Postgres analog:** `pcms.league_system_values` keyed by `(league_lk, salary_year)`.

---

## 4) “Fill to 12/14” is two different concepts

This is the most important roster-charge mental model in the workbook. For a deeper recon write-up, see: [`roster_fill_logic.md`](roster_fill_logic.md).

### 4A) Fill to 12 (rookie mins) — **immediate roster charges**

If roster count < 12, add (12 − roster_count) slots at **rookie minimum**.

Typical pattern (Playground row 43):
```excel
IF(roster>=12, 0, (12-roster)*RookieMin) * (days_remaining/174)
```

### 4B) Fill to 14 (vet mins) — **additional minimum slots**

If roster count < 14, add (14 − roster_count) slots at **vet minimum**.

Typical pattern (Playground row 44):
```excel
IF(roster>=14, 0, (14-roster)*VetMin) * (days_remaining/174)
```

### 4C) The Matrix adds a **+14 day “signing grace”** for fill-to-14

Only `the_matrix.json` models the operational/CBA reality that teams can temporarily be below 14.

- `AI5` = trade date
- `AI9` = **Day to Sign (+14)** = `AI5 + 14`
- `AI10` = day-of-season computed from `AI9` (not AI5)
- prorated mins are computed using `AI10`

Result: the **fill-to-14 (vet mins)** rows use `$AI$12`, so they’re priced as if minimum signings happen on **trade_date + 14**, not immediately.

This creates a subtle but real difference vs the Playground/Team/Finance family.

---

## 5) Proration: where “days remaining / 174” comes from

### 5A) Most sheets: anchor date → `DATE(YYYY,4,12)`

Typical:
- `anchor_date` is `TODAY()` (Playground/Team/Finance) or a manual date (GA)
- `days_remaining = DATE(playing_end_year,4,12) - anchor_date + 1`
- `proration_factor = days_remaining / 174`

GA is important because it demonstrates a real analyst workflow: **“set the date” → see prorated roster charges**.

### 5B) Postgres: use playing dates, not league-year dates

In `pcms.league_system_values`:
- `season_start_at` is **league-year start (July 1)** — do *not* use this for regular-season proration.
- Use:
  - `playing_start_at`
  - `playing_end_at`
  - `days_in_season` (usually 174)

Recommended DB-driven proration:
```text
days_remaining = (playing_end_at::date - as_of_date::date + 1)
proration_factor = days_remaining / days_in_season
```

To mirror The Matrix “+14” behavior:
```text
as_of_date = event_date + 14 days
```

---

## 6) Rookie min / Vet min sources (and a workbook gotcha)

Workbook sources vary:
- Some sheets reference **`Minimum Salary Scale`** directly.
- Some sheets look up rows like **"Rookie Min 2025" / "Vet Min 2025"** in Y.

**Gotcha:** those pseudo-rows are not reliably present in the exported `reference/warehouse/y.json` range.

**Tooling rule:** treat the DB as the source of truth:
- Rookie min = `pcms.league_salary_scales.minimum_salary_amount` where `years_of_service = 0`
- Vet min (Sean’s “vet min” roster charge) = the same table where `years_of_service = 2`

---

## 7) Luxury tax (Excel SUMPRODUCT vs DB function)

Excel computes tax owed via `SUMPRODUCT` over `Tax Array` (standard vs repeater columns).

Tooling should use:
- `pcms.fn_luxury_tax_amount(salary_year, over_tax_amount, is_repeater)`
- `pcms.fn_team_luxury_tax(team_code, salary_year)`

See: `tax_array.md`, `fn_luxury_tax_amount.md`.

---

## 8) Repeater flag

Sean hardcodes repeater teams via IF-chains in several sheets.

Tooling should use:
- `pcms.tax_team_status.is_repeater_taxpayer`
- surfaced via `pcms.team_salary_warehouse.is_repeater_taxpayer`

See: `repeater-flag-parameterization.md`.
