# Mental Models & Design Principles (Sean-style Cap Tooling)

**Updated:** 2026-01-31

This document captures the *tacit knowledge* behind Sean's workbook and the emerging Postgres-backed tooling.

It's meant to answer:
- "What are we actually building?"
- "What must always be true for analysts to trust it?"
- "Where do cap tools usually betray users?"

---

## 1) Trust is the product: the Ledger Model

NBA cap work is fundamentally ledger work.

Analysts need a snapshot that is:
- **authoritative** ("this is what counts"),
- **reconcilable** ("show me the contributing rows"), and
- **defensible** ("show me which assumptions/rules were applied").

### The core trap: "rows that exist" vs "rows that count"

Cap tools fail when:
- detail tables contain rights/holds/artifacts that *exist* but *don't count*, and
- totals are computed from a different definition than the drilldown.

**Non-negotiable rule:**
- All displayed totals must be sourced from (or reconcile to) the **authoritative counting ledger** (team budget snapshot / warehouse).
- Detail tables may be shown, but they must be explicitly labeled and scoped to the snapshot buckets.

### Implication: every headline number needs an audit path
For any primary readout (cap total, tax total, apron room, roster count, tax payment), the system must expose:
- a **contributing rows** list
- an **assumptions applied** list
- a **delta vs baseline** list

If that's missing, the tool will eventually lose trust.

---

## 2) Scenario = Baseline + Plan Journal + Derived State

A "scenario" is not a static object.

It is:
1. **Baseline state** - facts (warehouses / snapshots)
2. **Plan journal** - ordered actions (trade, waive, sign, stretch, renounce, use exception, etc.)
3. **Derived state** - recomputed roster + totals + constraints + alerts

### Why: analysts work by transformations, not edits
They try a move, observe consequences, then try a different move.

### Branching is a workflow problem
Two common analyst workflows:
- **Lane-based branching:** compare 2-4 deal candidates side-by-side
- **Version-based branching:** v1 → v2 fork at step N with a journal diff

Don't force branching into a single-row serialization problem.

---

## 3) Policies must be explicit (and visible)

Most "complexity" comes from invisible defaults.

Examples:
- fill-to-12 vs fill-to-14 vs fill-to-15
- rookie minimum vs veteran minimum assumptions
- whether two-ways count toward roster size and/or totals (CBA fact: they count toward totals, not roster)
- whether incomplete roster charges are applied (NOT modeled in this workbook — see excel-cap-book-blueprint.md)
- how partial guarantees are treated (display status vs counting status)

### Non-negotiable rule: policies create visible generated rows
If you auto-fill roster spots or generate charges:
- they must appear as **generated rows**
- they must be toggleable
- they must be labeled as assumptions (not facts)

Otherwise, analysts will experience "spooky action at a distance" (numbers change without visible cause).

---

## 4) Cockpit UX principles (dense tools that stay usable)

### 4.1 The Command Bar (always in the same place)
The command bar is the workbook's "operating context." It must be consistent across all sheets:
- Team
- Salary Year (base year)
- As-of date
- Mode (cap vs tax vs apron)
- Active Plan (scenario)
- Policy toggles (roster fill, two-way counting, etc.)

Scattered hidden selectors are a guaranteed failure mode.

### 4.2 4-7 primary readouts
Analysts can't hold 20 numbers in working memory.

A cockpit needs a small stable set of numbers (cap/tax/apron distances, roster count, tax estimate) with drilldown for everything else.

### 4.3 Recognition > recall
If a rule tier matters, show it adjacent to the input it governs.

Examples:
- salary matching tiers displayed next to trade inputs
- apron gates + hard-cap triggers displayed where exceptions/signings are chosen

### 4.4 Constraints as first-class outputs
Don't just output "max incoming." Output:
- whether the move is legal
- which constraint blocks it
- which rule/tier caused the block
- what would change the result (e.g., different year/date/mode)

### 4.5 Safe editing zones
A cockpit fails if users can accidentally overwrite logic.

Inputs must be:
- visually distinct
- structurally isolated
- protected where possible

---

## 5) Time is a first-class input

Date is not metadata.

The same move on a different date can change:
- proration
- guarantees
- waiver clearance timing
- eligibility windows

**Design rule:** as-of date is part of the scenario context and must be visible everywhere.

---

## 6) No hardcoded business logic (especially money logic)

If it affects totals, legality, or constraints:
- it should be parameterized from system values / source-of-truth tables, OR
- explicitly labeled as an analyst assumption.

Hardcoded repeater status / stale external links / manual overrides eventually destroy trust.

---

## 7) Taxonomy (shared language for rows + actions)

### 7.1 Row types (ledger buckets)
A tool needs an explicit taxonomy for *what a row is*.

Suggested categories (example):
- `ROST` - active roster contracts that count
- `FA` - holds/rights that count
- `TERM` - dead money that counts
- `2WAY` - two-way amounts (often separate totals)
- `GENERATED` - tool-generated assumption rows (roster fill slots)
- `EXISTS_ONLY` - visible artifacts that do not count (for reference only)

### 7.2 Action types (plan journal)
A tool needs an explicit taxonomy for *what actions exist*.

Examples:
- Trade (with legs / TPE absorption)
- Sign (cap room / exception / minimum)
- Waive
- Buyout
- Stretch
- Renounce
- Option decision
- Convert two-way / sign two-way

Each action must define:
- what rows are added/removed/modified
- what constraints it can trigger
- what audit output it must generate

---

## 8) The goal state

A great cap workbook (or app) has:
- a warehouse-backed truth layer
- a cockpit UI that minimizes working-memory load
- subsystem tools that generate journal entries
- an audit layer that explains every number
- explicit policies and visible generated rows

When in doubt: optimize for reconciliation and explainability. Speed comes from trust.
