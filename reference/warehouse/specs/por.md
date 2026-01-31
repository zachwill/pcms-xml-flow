# POR Spec (Playground snapshot)

**Source:** `reference/warehouse/por.json`  
**Rows:** 70  
**Relationship:** exact duplicate of `playground.json`

---

## 1. Purpose

The **POR** sheet is a **team-specific snapshot** of the Playground Salary Book view, with the team selector pre-set to Portland (`D1 = "POR"`).

Practically, this exists as a convenience tab in Excel ("saved view"), not as unique logic.

---

## 2. Evidence it is identical to Playground

`por.json` is **byte-for-byte identical** to `playground.json`.

Evidence (from prior inspection):
- Same file size: **97,834 bytes**
- Same MD5: **`6117c9f053cef95efcb58d575762526f`**
- Same row count: **70**
- Same structure when normalized (`jq -S`)

Implication: any logic described in [`playground.md`](playground.md) applies 1:1 here.

---

## 3. Key Inputs / Controls

Same as Playground (see [`playground.md`](playground.md)), except effectively:

| Cell | Meaning | Value in POR |
|------|---------|--------------|
| `D1` | Team code | `POR` (fixed) |

All other inputs/controls (base year, repeater toggles, trade mode, etc.) follow the same layout and formulas as Playground.

---

## 4. Key Outputs

Same as Playground (see [`playground.md`](playground.md)):
- Team roster salary grid (multi-year)
- Team totals vs cap/tax/aprons
- Luxury tax estimate (via `Tax Array`)
- Draft pick ownership grid

---

## 5. Cross-sheet dependencies

Because it is identical to Playground, dependencies are the same.

### POR reads from
- **`Y`** (salary warehouse; `INDEX/MATCH` lookups)
- **`System Values`** (cap/tax/apron thresholds)
- **`Tax Array`** (tax bracket SUMPRODUCT logic)
- **`Pick Database`** (draft pick ownership)

### What references POR
- No other sheets appear to reference `'POR'!` directly.

---

## 6. Key formulas / logic patterns

Same as Playground (see [`playground.md`](playground.md)), including:
- Team-filtered roster list via `LET` + `FILTER` + `SORTBY`
- Salary lookups into `Y` by player name + year header match
- Tax payment via `SUMPRODUCT` against `Tax Array` brackets

---

## 7. Mapping to Postgres

Same as Playground, scoped to team_code = POR:

| Concept | Our Table(s) |
|---------|--------------|
| Player salaries by year | `pcms.salary_book_warehouse WHERE team_code = 'POR'` |
| Cap/Tax/Apron levels | `pcms.league_system_values` |
| Team totals | `pcms.team_salary_warehouse WHERE team_code = 'POR'` |
| Dead money | `pcms.dead_money_warehouse WHERE team_code = 'POR'` |

---

## 8. Open Questions / TODO

- [ ] Confirm if the workbook contains **other team-clone tabs** that were *not* exported (e.g., `bos.json`, `lal.json`).
- [ ] If Sean uses team-specific tabs heavily, consider whether our tooling should support **"saved views"** (pre-filtered team dashboards).
