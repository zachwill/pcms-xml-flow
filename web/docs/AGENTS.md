# AGENTS.md — `web/docs/`

This folder contains implementation-facing docs for Rails + Datastar UI work.

## Read order (default)

1. `web/docs/design_guide.md`
   - Visual system, shell patterns (A/B/C), row/cell density rules.
2. `web/docs/datastar_sse_playbook.md`
   - Multi-region updates, SSE patterns, streaming semantics.
3. `web/docs/agent_browser_playbook.md`
   - Project-scoped browser automation workflow for design QA and interaction smoke tests.

## Contracts

`web/docs/contracts/` documents feature-level event contracts and UI behavior:
- `combobox_player_search.md`
- `salary_book_team_switch_events.md`
- `salary_book_view_switch_events.md`

Read these before changing behavior tied to those features.

## Scope note for agent-browser

We intentionally use a **subset** of upstream agent-browser functionality for this project:
- Snapshot/ref workflow (`snapshot -i -C -c` + `@eN` refs)
- Visual capture (`screenshot --annotate`, `--full`)
- Basic waits and state checks

Advanced provider/infrastructure features (cloud providers, iOS, CDP streaming, profiler-heavy flows) are optional and not required for routine `web/` design iteration.
