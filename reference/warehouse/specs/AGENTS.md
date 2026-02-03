# AGENTS.md — `reference/warehouse/specs/`

**Updated:** 2026-02-03

These specs document Sean’s current workbook exports (`reference/warehouse/*.json`) in a way that future agents can quickly become **elite salary cap / trade analysts**.

This folder contains two different kinds of documents:

1) **Core specs** (Y warehouse, system values, trade tools, etc.)
2) **Meta docs** (parameterization decisions, parity notes, helper function specs)

If you’re new, start with the **S‑Tier** list below.

---

## How to read (goal-oriented)

### If you only have 30–60 minutes
Read S‑Tier items 1–7.

### If you’re building trade/cap tooling and need parity
Read all S‑Tier + A‑Tier.

---

## S‑Tier (must-read: the core mental model)

These are the highest-leverage docs for “think like Sean” salary-cap analysis.

1. **Workbook map / dependency graph**: [`00-index.md`](00-index.md)
2. **Shared workbook building blocks** (rosters, lookups, fill, proration, tax): [`patterns.md`](patterns.md)
3. **The central warehouse worldview** (one row/player, multi-year): [`y.md`](y.md)
4. **CBA constants / thresholds / max tiers**: [`system_values.md`](system_values.md)
5. **Roster charges + fill-to-12/14 nuance (+14 day sign window in Matrix)**: [`roster_fill_logic.md`](roster_fill_logic.md)
6. **Minimum salary reference** (rookie/vet mins): [`minimum_salary_scale.md`](minimum_salary_scale.md)
7. **Luxury tax** (Excel view + DB primitive):
   - [`tax_array.md`](tax_array.md)
   - [`fn_luxury_tax_amount.md`](fn_luxury_tax_amount.md)
8. **League dashboard mindset** (who’s over/under; tax/refund framing): [`team_summary.md`](team_summary.md)
9. **2‑team trade matching rules** (expanded/standard; can‑bring‑back framing): [`machine.md`](machine.md)
10. **Exception inventory (TPE/MLE/BAE)**: [`exceptions.md`](exceptions.md)
11. **Trade kicker constraint logic** (kicker bounded by max tiers): [`trade_bonus_amounts.md`](trade_bonus_amounts.md)
12. **Multi‑team trade planning + apron constraints + proration**: [`the_matrix.md`](the_matrix.md)
13. **Draft pick assets (ownership DSL + summary grid):**
    - [`draft_picks.md`](draft_picks.md)
    - [`pick_database.md`](pick_database.md)

---

## A‑Tier (deepening layer: edge rules + implementation parity)

- Contract-year detail layer / option derivation: [`dynamic_contracts.md`](dynamic_contracts.md)
- Guarantees / protections lookup: [`contract_protections.md`](contract_protections.md)
- Minimum scale parity vs PCMS (years 2–5 derivation): [`minimum-salary-parity.md`](minimum-salary-parity.md)
- “Can bring back” inverse trade matching primitive: [`fn_can_bring_back.md`](fn_can_bring_back.md)
- Trade-matching threshold parameterization + parity discussion: [`tpe-threshold-parameterization.md`](tpe-threshold-parameterization.md)
- Waiver / buyout / stretch / set-off math (canonical rules): [`buyout-waiver-math.md`](buyout-waiver-math.md)
- Rookie scale deeper modeling (cap holds / QO / FA amounts): [`rookie_scale_amounts.md`](rookie_scale_amounts.md)

---

## B‑Tier (useful applications; mostly repetitions of the core patterns)

These are helpful once you know the primitives, but are largely “views” built from the same patterns.

- Interactive salary book view: [`playground.md`](playground.md)
- Team salary book variant: [`team.md`](team.md)
- Team finance view (renegotiation + embedded trade block): [`finance.md`](finance.md)
- High/low salary search tool: [`high_low.md`](high_low.md)

Meta / plumbing (important for tooling work, less important for analyst intuition):
- External workbook refs resolution: [`external-refs.md`](external-refs.md)
- Repeater flag parameterization: [`repeater-flag-parameterization.md`](repeater-flag-parameterization.md)
- Season-day constants decision (174 days; playing_start vs season_start): [`season-day-constants-decision.md`](season-day-constants-decision.md)
- Year-horizon decision (2030 vs 2031): [`year-horizon-decision.md`](year-horizon-decision.md)

---

## C‑Tier (stubs / duplicates / examples)

### Stubs (saved views)
- [`por.md`](por.md) (Playground snapshot)
- [`2025.md`](2025.md) (Playground snapshot)
- [`ga.md`](ga.md) (Team/Playground variant)

### Examples (scenario worksheets)
These are “worked examples,” not canonical rules.

- [`example_buyout_calculator.md`](example_buyout_calculator.md)
- [`example_kuzma_buyout.md`](example_kuzma_buyout.md)
- [`example_set_off.md`](example_set_off.md)
