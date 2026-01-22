# replicas/trade_machine

Goal: reproduce the core data needs for Sean’s `Trade Machine.txt`:

- roster lists by team (sorted by salary)
- per-player “max incoming” and “min outgoing” based on CBA rule bands
- scenario-year toggle (2024 vs 2025) and ruleset toggle (Expanded vs Standard)

## Data inputs

- Player salary (X warehouse for 2024, Y warehouse for 2025 offseason)
- Rule bands (not in PCMS) → add `pcms.trade_rules` or compute in app code

## Method A (recommended): store rule bands in DB, compute in SQL

### 1) `pcms.trade_rules` table

See `SEAN.md` Task 2.1 for schema + seed values.

### 2) Band lookup (inline)

```sql
SELECT
  r.description,
  (outgoing_salary * COALESCE(r.multiplier, 1) + r.flat_adder)::bigint AS max_incoming
FROM pcms.trade_rules r
WHERE r.salary_year = ${YEAR}
  AND r.rule_type = ${RULESET}
  AND ${outgoing_salary} >= r.threshold_low
  AND (r.threshold_high IS NULL OR ${outgoing_salary} < r.threshold_high);
```

### 3) “Can Bring Back” export

For a given team + year:

- join roster → compute max_incoming for each player
- return (player_name, outgoing_salary, max_incoming)

## Method B: compute bands in application code

Export roster salaries only, apply band logic in TS/Python.

## Known fidelity gaps

- Real matching rules depend on apron/taxpayer status and other constraints.
- Sean’s sheets sometimes simplify “Standard” rules.

Reasonable v1: implement bands + join `pcms.tax_team_status` to choose the ruleset.
