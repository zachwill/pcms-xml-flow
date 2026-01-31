# Blueprints (Design Reference)

**Purpose:** capture *tacit knowledge* and *design intent* for Sean-style NBA salary cap tooling — in a form that’s stable, reviewable, and executable later.

This folder supersedes the former root-level `INSIGHTS.md` (now removed); new insights should land here.

This folder is intentionally different from:
- `reference/warehouse/` — a snapshot export of Sean’s workbook (JSON)
- `reference/warehouse/specs/` — auto-generated “what exists today” sheet specs

These **Blueprints** are the "what we’re trying to build" documents: mental models, UI/cockpit rules, and worksheet architecture.

## How to use these docs

- When debating **what a number means**, start with **Mental Models & Design Principles**.
- When designing or rebuilding sheets (Excel or web), start with the **Excel Cap Book Blueprint**.
- Treat these as the canonical place to record new insights before changing DB schema, SQL primitives, or UX.

## Files

- [`mental-models-and-design-principles.md`](mental-models-and-design-principles.md)
  - The non-negotiable mental models: ledger trust, “exists vs counts,” scenario-as-journal, explicit policies, explainability.

- [`excel-cap-book-blueprint.md`](excel-cap-book-blueprint.md)
  - A proposed workbook architecture: command bar, cockpit sheet, plan journal, subsystems (trade, signings, waive/stretch), audit.

- [`excel-workbook-data-refresh-blueprint.md`](excel-workbook-data-refresh-blueprint.md)
  - How we’d populate the workbook from Postgres: dataset selection, refresh pipeline, validation, and distribution.

- [`excel-workbook-data-contract.md`](excel-workbook-data-contract.md)
  - The stable interface between Postgres and the workbook `DATA_*` sheets: required datasets, keys, and column meanings.

## Conventions

- Prefer concrete, testable statements.
  - Example: “Every headline total must have a contributing-rows drilldown” (testable)
  - Not: “Make it intuitive.”

- Separate **facts** (what PCMS currently provides) from **assumptions/policies** (analyst knobs).

- When adding new rules, include:
  - where it appears in the UI (adjacent to which input)
  - how it is audited/reconciled
  - what the failure mode looks like (what goes wrong if it’s implicit)
