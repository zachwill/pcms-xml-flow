# Missing data & fallbacks

We should expect incomplete ingestion while building replica exports.

## High-impact missing pieces (from SEAN.md)

- `pcms.team_transactions` (cap hold adjustments) – impacts Team Master / cap-hold modeling
- contract nested detail tables (`contract_protections`, `payment_schedule_details`, etc.) – impacts “true” trade math and some display fields
- formal trade-rule bands (CBA matching rules) – required for Trade Machine/Give-Get validation

## Practical fallbacks

### Roster source

1) Preferred: `pcms.people.team_code` (simple) + active contract join
2) Fallback: `pcms.team_budget_snapshots` latest ledger row per team/year/player

### Dead money

1) `pcms.transaction_waiver_amounts` aggregated by team/year
2) If missing: output 0/NULL

### Trade kicker

1) `pcms.salaries.trade_bonus_amount_calc` for the anchor year
2) else `pcms.contract_versions.trade_bonus_amount` / `trade_bonus_percent`

### Options

Use `pcms.salaries.option_lk` and `option_decision_lk`.
- If `option_decision_lk = 'POD'`, treat as guaranteed.
- If `option_decision_lk = 'POW'`, treat as not applicable (can null out that year).

## Validation ideas

- Compare roster counts per team vs expected (~15)
- Spot-check known players’ salaries
- Ensure constants align with `league_system_values`
