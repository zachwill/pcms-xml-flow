# TODO.md — Next Implementation Priorities

**Updated:** 2026-01-31

This repo aims for parity with Sean’s analyst workbook by implementing:
- **warehouse tables** (`pcms.*_warehouse`) for fast, tool-facing reads
- small, composable **SQL primitives** (`pcms.fn_*`) for trade/cap math
- **assertion-style SQL tests** in `queries/sql/`

---

## ✅ Completed (2026-01-31)

These were the three “missing primitives” called out in `SALARY_BOOK.md` and the warehouse specs.

### 1) Inverse trade matching (“Can Bring Back”)
- Migration: `migrations/058_fn_can_bring_back.sql`
- Functions:
  - `pcms.fn_min_outgoing_for_incoming()` (core inverse primitive)
  - `pcms.fn_can_bring_back()` (wrapper)
  - `pcms.fn_player_can_bring_back()` (player lookup wrapper)
  - `pcms.fn_trade_salary_range()` (min/max window helper)
- Tests:
  - `queries/sql/056_can_bring_back_assertions.sql`

### 2) Multi-year minimum salary escalators
- Migration: `migrations/059_fn_minimum_salary.sql`
- Function:
  - `pcms.fn_minimum_salary(salary_year, years_of_service, contract_year, league_lk)`
- Tests:
  - `queries/sql/057_minimum_salary_assertions.sql`

### 3) Buyout / waiver primitives
- Migration: `migrations/060_fn_buyout_primitives.sql`
- Functions:
  - `pcms.fn_days_remaining()`
  - `pcms.fn_stretch_waiver()`
  - `pcms.fn_setoff_amount()`
  - `pcms.fn_buyout_scenario()`
- Tests:
  - `queries/sql/058_buyout_primitives_assertions.sql`

### Test runner wiring
- Updated: `queries/sql/run_all.sql` now includes the new assertion files.

---

## Next Priorities (post-primitives)

Now that the core primitives exist, the next gaps are **higher-level workbook sheets** that combine them.

### Priority A: Roster-charge penalties / incomplete roster penalties
**Sean source:** `team_summary.json` / `reference/warehouse/specs/team_summary.md`

What we need:
- A primitive/function that computes the “<12” and “<14” roster-charge penalties using:
  - `pcms.fn_minimum_salary()` for the rookie (0-YOS) and vet (2-YOS) minimums
  - `/174` proration via `pcms.fn_days_remaining()` (or a new date helper)

Suggested output:
- A small function returning both penalties for a team/date (or a pure numeric helper).

Why now:
- This is one of the last “Team Summary” deltas that analysts notice immediately.

### Priority B: Extension calculator
**Sean source:** `the_matrix.json` / `reference/warehouse/specs/the_matrix.md`

What we need:
- Max extension starting salary rules (120%/140%, 8% raises, etc.)
- Eligibility gates (service-time / contract type) where possible

Approach:
- Build small primitives first (max starting salary, max annual raise, max years), then compose.

### Priority C: High / Low contract projections
**Sean source:** `high_low.json` / `reference/warehouse/specs/high_low.md`

What we need:
- Best/worst case scenarios based on options + incentives + guarantee levels
- Likely driven by `pcms.salary_book_warehouse` option/bonus/guarantee columns

### Priority D: Multi-team trade scenarios
**Sean source:** `the_matrix.json` (complex trade algebra)

What we need:
- Extend beyond the current 2-team, TPE-first planner
- Likely: represent each leg explicitly and solve iteratively (builds on existing trade primitives)

---

## Follow-up Validations (spot checks)

These are not blockers (tests already exist), but are good sanity checks when time permits:

1) **Luxury tax** spot-check vs Sean’s `team_summary.json` “Tax Payment” column:
   - Pick 2–3 teams (e.g., BOS / PHX / MIN) and compare `pcms.fn_team_luxury_tax(team, 2025)`

2) **Can Bring Back** spot-check vs `reference/warehouse/machine.json`:
   - Verify a couple salary points around the tier boundaries.

3) **Minimum salary** spot-check vs `reference/warehouse/minimum_salary_scale.json`:
   - Expect small deltas for 2025/2026 because Sean hardcodes CBA-published values.

4) **Buyout scenario** spot-check vs `reference/warehouse/buyout_calculator.json`:
   - Current implementation matches the proration + give-back allocation pattern.
   - Open question remains for contract-specific guarantee adjustments and trade-kicker handling.

---

## How to run tests

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```
