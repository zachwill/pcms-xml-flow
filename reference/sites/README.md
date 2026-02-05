# Reference site notes (`reference/sites/`)

This folder contains lightweight notes from external sites that present dense “catalog + finance + constraints” data clearly.

These notes exist to:
- capture useful **information architecture / interaction** patterns (filters, timelines, rollups, drill-ins)
- identify what end-users expect to search, compare, and pivot between
- guide which Postgres warehouses/functions the product should support well

## Files

Source notes:
- `bricklink.txt`
- `builtwith.txt`
- `capfriendly.txt`
- `pcms.txt`
- `puckpedia.txt`
- `salaryswish.txt`
- `spotrac.txt`

Synthesis:
- `INTERACTION_MODELS.md` — repo-specific takeaways (tools vs entity workspaces vs catalog/inbox)

## Important caveat

These sources are **not authoritative** for PCMS semantics.

Use them as product inspiration, while validating any derived calculations or terminology against:
- PCMS artifacts
- our modeled `pcms.*` fields/warehouses
- and (when relevant) the CBA
