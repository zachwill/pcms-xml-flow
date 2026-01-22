# components/active_contracts

Reusable logic to select the “current” contract + latest version for each player.

This is the core join for nearly every replica export.

## Method A (recommended): CTE pattern (copy/paste)

```sql
WITH active_contracts AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (
      PARTITION BY c.player_id
      ORDER BY
        (c.record_status_lk = 'APPR') DESC,
        (c.record_status_lk = 'FUTR') DESC,
        c.signing_date DESC NULLS LAST,
        c.contract_id DESC
    ) AS rn
  FROM pcms.contracts c
  WHERE c.record_status_lk IN ('APPR', 'FUTR')
),
latest_versions AS (
  SELECT
    cv.*,
    ROW_NUMBER() OVER (
      PARTITION BY cv.contract_id
      ORDER BY cv.version_number DESC
    ) AS rn
  FROM pcms.contract_versions cv
)
SELECT
  ac.contract_id,
  ac.player_id,
  ac.signing_team_id,
  ac.team_code,
  lv.version_number,
  lv.contract_type_lk,
  lv.record_status_lk AS version_status_lk,
  lv.is_two_way,
  lv.is_poison_pill,
  lv.poison_pill_amount,
  lv.is_trade_bonus,
  lv.trade_bonus_percent,
  lv.trade_bonus_amount,
  lv.is_no_trade
FROM active_contracts ac
JOIN latest_versions lv
  ON lv.contract_id = ac.contract_id
 AND lv.rn = 1
WHERE ac.rn = 1;
```

### Notes
- This picks **one** active contract per player.
- If we later need “multiple active contracts” (rare), remove `ac.rn = 1`.

## Method B: formalize as a view

When we’re ready to stabilize names, convert Method A into:

- `pcms.vw_active_contract_versions` (view)
- or `pcms.mv_active_contract_versions` (materialized view) if perf becomes a concern.

## Known gaps

- `people.team_code` (current team) can differ from `contracts.team_code`.
  - In the live DB, `people.team_code` is often blank for many historical players.
  - For replicas, prefer `contracts.team_code` (active contract) and/or derive roster from `team_budget_snapshots`.
  - Expose both when possible.
