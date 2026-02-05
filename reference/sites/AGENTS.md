# AGENTS.md — `reference/sites/`

## Purpose

These are *reference notes* from external sites.

They help answer:
- “What interaction patterns work for dense, link-rich sports/finance data?”
- “What should `web/` feel like once PCMS is modeled correctly in Postgres?”

## Key synthesis doc

Read this first when making product-architecture decisions in `web/`:
- `reference/sites/INTERACTION_MODELS.md`

It spells out the repo’s current interaction thesis:
- **Tools/workbenches** (Salary Book-style: scroll is state + sidebar drill-ins)
- **Entity workspaces** (single entity, scroll-first module stacks + scrollspy nav)
- **Catalog/inbox** (directory + digest surfaces; not a Netflix grid)

## Rules / conventions

- Treat these notes as inspiration, not truth.
- When a UI pattern implies a derived metric, document the derivation separately and tie it back to:
  - specific `pcms.*` fields/warehouses/functions, and/or
  - the CBA.
- Keep additions lightweight:
  - prefer short notes and labels over dumping entire pages
  - capture the *job-to-be-done*, the *modules*, and the *interaction patterns*
- If a new reference changes our product thesis, update `INTERACTION_MODELS.md` (don’t let it drift).
