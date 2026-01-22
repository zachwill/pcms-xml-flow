# replicas/x_warehouse ("X.txt")

Goal: produce a **current-season** warehouse used by Trade Machine and Give/Get.

Sean’s X sheet is anchored on **2024** salaries (2024–2029 grid), plus trade-math columns.

## Output shape (minimum viable)

One row per player (NBA players only):

- `player_name (Last, First)`, `team_code` (prefer active contract team_code; `people.team_code` is often blank)
- Cap salaries: `cap_2024..cap_2029`
- Cap %: `pct_cap_2024..pct_cap_2029`
- Total remaining value from 2024: `total_from_2024`
- Trade kicker: `trade_bonus_percent`, `trade_kicker_amount_2024` (best effort)
- Options: `option_2024..option_2029`
- Trade-math (approx): outgoing_buildup_2024, incoming_buildup_2024, incoming_salary_2024
- Tax/apron: `tax_2024..tax_2029`, `apron_2024..apron_2029`

## Method A: reuse components, shift the year window

Use:
- `components/active_contracts.md`
- `components/salary_pivot.md`

Then select 2024..2029 columns and cap constants for those years.

### “Total remaining”

Approximate:

```sql
COALESCE(sp.cap_2024,0) + COALESCE(sp.cap_2025,0) + COALESCE(sp.cap_2026,0)
+ COALESCE(sp.cap_2027,0) + COALESCE(sp.cap_2028,0) + COALESCE(sp.cap_2029,0)
  AS total_from_2024
```

### Trade-math (best effort)

If we have `salaries.trade_bonus_amount_calc` for 2024:

- outgoing_buildup_2024 = cap_2024 (unless poison pill; see below)
- incoming_buildup_2024 = cap_2024 + trade_bonus_amount_2024
- incoming_salary_2024 = incoming_buildup_2024

#### Poison pill handling (likely incomplete)

We have:
- `contract_versions.is_poison_pill` + `poison_pill_amount`
- `people.is_poison_pill` + `poison_pill_amt`

Without a full poison-pill implementation, we should:

- expose `is_poison_pill`, `poison_pill_amount`
- keep outgoing_buildup = cap salary (documented approximation)

## Data gaps impacting fidelity

- outgoing/incoming values can differ from cap salary due to:
  - poison pill
  - unlikely bonuses / incentive treatment
  - base-year compensation

Later enrichment candidates:
- `ledger_entries` (cap/tax/apron values by date)
- `team_budget_snapshots` (cap/tax/mts by ledger date)
