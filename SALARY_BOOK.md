# Salary Book Query Guide

Reference for querying PCMS contract/salary data to produce the Salary Book view.

---

## Data Model

```
pcms.contracts (1 per contract)
  └── pcms.contract_versions (1+ per contract, tracks amendments)
        └── pcms.salaries (1 per version per year)
              └── pcms.payment_schedules (optional, payment timing)
                    └── pcms.payment_schedule_details (individual payment dates)
```

### Key Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `pcms.contracts` | `contract_id` | Contract header (signing team, dates, status) |
| `pcms.contract_versions` | `(contract_id, version_number)` | Amendments, extensions, option decisions |
| `pcms.salaries` | `(contract_id, version_number, salary_year)` | Year-by-year salary figures |
| `pcms.people` | `person_id` | Player names (joins via `player_id`) |

---

## Contract Status Codes

The `record_status_lk` field determines if a contract is active:

| Status | Count | Meaning | Include in Salary Book? |
|--------|-------|---------|-------------------------|
| **APPR** | ~528 | Approved/Active | ✅ Yes |
| **FUTR** | ~29 | Future (signed extension not yet active) | ✅ Yes |
| **COMP** | ~2,529 | Completed (expired naturally) | ❌ No |
| **TERM** | ~3,632 | Terminated (buyout, waived) | ❌ No |
| **REL** | ~1,063 | Released | ❌ No |
| **REPL** | ~131 | Replaced (superseded by new contract) | ❌ No |
| **MATCH** | ~23 | RFA match in progress | ❌ No (transient) |
| **NMTCH** | ~38 | RFA offer not matched | ❌ No |
| **VOID** | ~98 | Voided (never valid) | ❌ No |

**Filter for active contracts:**
```sql
WHERE c.record_status_lk IN ('APPR', 'FUTR')
```

---

## Version Numbers

Contracts can have multiple versions (amendments, option decisions). The `version_number` field uses a decimal format that gets normalized:

- `1.0` → `100` (original)
- `1.01` → `101` (first amendment)
- `2.0` → `200` (major revision)
- `2.01` → `201` (amendment to v2)

**Always use the latest version** for current salary display:
```sql
WHERE v.version_number = (
  SELECT MAX(version_number) 
  FROM pcms.contract_versions cv
  WHERE cv.contract_id = c.contract_id
)
```

---

## Key Salary Fields

From `pcms.salaries`:

| Field | Use For | Description |
|-------|---------|-------------|
| `contract_cap_salary` | **Cap Hit** | The number shown in Salary Book columns |
| `total_salary` | Actual pay | What player receives (can differ from cap) |
| `contract_tax_salary` | Luxury tax | Salary for tax calculations |
| `contract_tax_apron_salary` | Apron | Salary for apron calculations |
| `likely_bonus` | Cap | Likely incentives (count against cap) |
| `unlikely_bonus` | Info | Unlikely incentives (don't count) |
| `option_lk` | Display | `PLYR`=Player Option, `TEAM`=Team Option, `NONE`=Guaranteed |
| `option_decision_lk` | Display | `POD`=Picked up, `POW`=Declined, null=Pending |

From `pcms.contract_versions`:

| Field | Use For | Description |
|-------|---------|-------------|
| `trade_bonus_percent` | TK column | Trade kicker percentage (e.g., `15.0`) |
| `is_trade_bonus` | Filter | Boolean if trade bonus exists |
| `contract_type_lk` | Info | `REGCT`, `ROOK`, `TWOWAY`, `10DAY`, etc. |

---

## Salary Book Query

The canonical query to produce the spreadsheet-style view:

```sql
SELECT 
  p.first_name || ' ' || p.last_name AS player,
  c.signing_team_id,
  t.team_code,
  MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_cap_salary END) AS "2025",
  MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_cap_salary END) AS "2026",
  MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_cap_salary END) AS "2027",
  MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_cap_salary END) AS "2028",
  MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_cap_salary END) AS "2029",
  MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_cap_salary END) AS "2030",
  v.trade_bonus_percent AS tk,
  -- For option display suffix
  MAX(CASE WHEN s.salary_year = 2025 THEN s.option_lk END) AS "2025_option",
  MAX(CASE WHEN s.salary_year = 2026 THEN s.option_lk END) AS "2026_option"
FROM pcms.contracts c
JOIN pcms.contract_versions v USING (contract_id)
JOIN pcms.salaries s 
  ON s.contract_id = c.contract_id 
  AND s.version_number = v.version_number
JOIN pcms.people p ON p.person_id = c.player_id
LEFT JOIN pcms.lk_teams t ON t.team_id = c.signing_team_id
WHERE c.record_status_lk IN ('APPR', 'FUTR')
  AND v.version_number = (
    SELECT MAX(version_number) 
    FROM pcms.contract_versions cv
    WHERE cv.contract_id = c.contract_id
  )
GROUP BY 
  p.first_name, p.last_name, 
  c.signing_team_id, t.team_code,
  v.trade_bonus_percent
ORDER BY "2025" DESC NULLS LAST;
```

### For a Single Team

Add team filter:
```sql
WHERE c.record_status_lk IN ('APPR', 'FUTR')
  AND c.signing_team_id = 1610612747  -- LAL
```

Or by team code:
```sql
  AND t.team_code = 'LAL'
```

---

## Display Formatting

### Option Suffixes

Show option type in the cell:

| `option_lk` | Display |
|-------------|---------|
| `PLYR` | `$48.9M (PO)` |
| `TEAM` | `$48.9M (TO)` |
| `NONE` | `$48.9M` |

If `option_decision_lk = 'POD'`, the option was exercised (show as guaranteed).
If `option_decision_lk = 'POW'`, the option was declined (don't show that year).

### Trade Kicker

Display as percentage: `15%` or `—` if null.

### Money Formatting

- Millions with 1 decimal: `$43.0M`
- Or full: `$43,031,940`

---

## Example: Player with Multiple Contracts

**Deandre Ayton** (player_id: 1629028) has 5 contracts in the system:

| contract_id | team | status | Include? |
|-------------|------|--------|----------|
| 75288 | PHX | COMP | ❌ Rookie deal completed |
| 77761 | IND | MATCH | ❌ RFA offer sheet |
| 77762 | PHX | MATCH | ❌ Match process |
| 77773 | PHX | TERM | ❌ Terminated (buyout) |
| **99554** | **LAL** | **APPR** | ✅ Current contract |

Only contract 99554 appears in Salary Book with `record_status_lk = 'APPR'`.

---

## Example: Contract with Option

**Luka Dončić** (player_id: 1629029, contract_id: 76984):

```
2024: $43.0M (NONE)  - Guaranteed
2025: $46.0M (NONE)  - Guaranteed  
2026: $49.0M (PLYR)  - Player Option (exercised: POD)
```

Trade kicker: 15% (earned 2025-02-02 in trade to LAL)

---

## jq Recipes for Local Testing

### Get player's active contract salaries
```bash
jq -r '
  .[] | select(.player_id == 1629029 and .record_status_lk == "APPR") |
  .versions.version | sort_by(.version_number) | last |
  .salaries.salary[] | 
  "\(.salary_year): $\(.contract_cap_salary / 1000000 | . * 100 | round / 100)M \(.option_lk)"
' shared/pcms/nba_pcms_full_extract/contracts.json
```

### List all active contracts for a team
```bash
jq -r '
  .[] | select(.signing_team_id == 1610612747 and .record_status_lk == "APPR") |
  "\(.contract_id): player \(.player_id)"
' shared/pcms/nba_pcms_full_extract/contracts.json
```

### Pivot salaries to object by year
```bash
jq '
  .[] | select(.contract_id == 76984) |
  .versions.version | sort_by(.version_number) | last |
  .salaries.salary | 
  map({(.salary_year | tostring): .contract_cap_salary}) | add
' shared/pcms/nba_pcms_full_extract/contracts.json
```

---

## Dead Money / Cap Holds

Not covered here—dead money comes from terminated contracts that still count against the cap. See `transaction_waiver_amounts.json` and the transactions import for stretched/waived salary obligations.

---

## Related Files

- `SCHEMA.md` — Full database schema
- `AGENTS.md` — Flow architecture overview
- `reference/sean/specs/playground.txt` — Original Salary Book spreadsheet spec
- `import_pcms_data.flow/contracts.inline_script.py` — How contracts are imported
