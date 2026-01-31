# Contract Protections Spec

**Source:** `reference/warehouse/contract_protections.json`  
**Rows:** 614

---

## 1. Purpose

`Contract Protections` is a **guarantee / protection lookup table** keyed by:

- Contract ID
- Version number
- Player ID
- Protection year

It is used to classify a given contract-year as:
- `Full` (fully guaranteed)
- `Partial` / `Part./Cond` (partially/conditionally guaranteed)
- `None` / `None/Cond` (non-guaranteed)

This drives downstream logic like the derived `OPTION` code in `dynamic_contracts.json`.

---

## 2. Key Inputs / Controls

None. This is a raw data table (likely copy/paste from PCMS).

---

## 3. Key Outputs

A single table with these headers (row 1):

| Col | Header | Example |
|---|---|---|
| A | Contract Id | `99966` |
| B | Version Number | `1` |
| C | Player ID | `1630700` |
| D | Type | `Injury or Illness,Lack of Skill,` |
| E | Protection Year | `2026` |
| F | Protection Coverage | `Full` |

Rows 2+ are data.

---

## 4. Layout / Zones

- Row 1: headers
- Rows 2–614: data

---

## 5. Cross-Sheet Dependencies

### Contract Protections is referenced by:

- `dynamic_contracts.json` column `O` looks up guarantee coverage by `(player_id, salary_year)`:

```excel
=INDEX('Contract Protections'!F:F, MATCH(1, ('Contract Protections'!C:C=C3) * ('Contract Protections'!E:E=J3), 0))
```

Notes:
- `dynamic_contracts` also shows an **external workbook artifact** in its header row:
  - `O2: ='[2]Contract Protections'!F1`

### Contract Protections references:

None (self-contained table).

---

## 6. Mapping to Postgres

Most direct mapping is to **`pcms.contract_protections`** (one row per contract version × salary year protection entry).

| Sean column | Our table | Notes |
|---|---|---|
| Contract Id / Version Number | `pcms.contract_protections` | join keys: `contract_id`, `version_number` |
| Player ID | `pcms.contract_protections` + `pcms.people` | protections store `player_id`; join to `pcms.people` for identity |
| Protection Year | `pcms.contract_protections.salary_year` | year of the salary row |
| Coverage (Full/Partial/None/Cond) | `pcms.contract_protections.protection_coverage_lk` | values include `FULL`, `NONE`, `NOCND` (+ partial/conditional variants) |
| Protection amount (if partial) | `pcms.contract_protections.protection_amount` / `effective_protection_amount` | used to derive guaranteed dollars |

Practical warehouse mapping:
- `pcms.refresh_salary_book_warehouse()` joins `pcms.salaries` to `pcms.contract_protections` by `(contract_id, version_number, salary_year)`.
- That join drives tool-facing fields like `guaranteed_amount_20xx` and `is_fully_guaranteed_20xx` / `is_partially_guaranteed_20xx`.

---

## 7. Open Questions / TODO

- [ ] Validate whether the lookup should key on `(contract_id, version_number, year)` instead of `(player_id, year)` (the workbook uses player_id + year, which assumes uniqueness).
- [ ] The `Type` column is a CSV list of triggers (injury, skill, etc.). We currently do not surface this in tool caches.
- [ ] There appear to be occasional duplicate player/year rows; confirm if they are benign duplicates or represent multiple protection types.
