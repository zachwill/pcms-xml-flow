# agent-browser playbook for `web/`

This is our **project-scoped** guide for using `agent-browser` to improve page design and interaction quality.

Use this instead of the full upstream README unless you need an advanced feature.

---

## What we use it for

1. **Design QA** on non-Salary-Book pages (layout, density, spacing, sticky behavior).
2. **Interaction smoke tests** (filters, sidebar drill-ins, view toggles).
3. **Before/after visual checks** while refactoring ERB/Tailwind.

Not our default focus right now:
- Cloud providers (`browserbase`, `kernel`, `browseruse`)
- iOS/Appium mode
- CDP/streaming APIs
- Full trace/profiler workflows

---

## Prerequisites

```bash
agent-browser install
```

Run the Rails app first (in another terminal):

```bash
bin/dev
```

Default local URL is usually `http://localhost:3000`.

---

## Core workflow (always)

```bash
# 1) Open page
agent-browser open http://localhost:3000/team-summary

# 2) Wait for load
agent-browser wait --load networkidle

# 3) Capture interactive tree (refs)
agent-browser snapshot -i -C -c

# 4) Capture visual baseline
agent-browser screenshot --annotate /tmp/agent-browser/team-summary-before.png

# 5) Interact via refs (@eN), then re-snapshot
agent-browser click @e12
agent-browser snapshot -i -C -c
```

## Evidence package contract (required for redesign tasks)

Use this order every time:
1. Baseline evidence (`/`, `/ripcity/noah`, then the target route).
2. Diagnosis (what to keep, what is weak/confusing, highest-leverage flow issue).
3. Options (1-2 chunk options) for interaction-sensitive redesigns.
4. Approval on direction.
5. Implementation + after evidence.

Artifact path convention:
- Save all snapshots/screenshots under `/tmp/agent-browser/...`.
- Do **not** use repo-local `tmp/agent-browser/...` paths.

### Why this pattern

- `snapshot` refs (`@e1`, `@e2`, …) are deterministic and stable for AI agents.
- `--annotate` screenshots map visual labels to the same refs.
- Re-snapshot after any meaningful page change.

---

## Recommended command subset

### Navigation + interaction

```bash
agent-browser open <url>
agent-browser click <sel-or-ref>
agent-browser fill <sel-or-ref> "..."
agent-browser press Enter
agent-browser scroll down 800
```

### State + inspection

```bash
agent-browser snapshot -i -C -c
agent-browser get text <sel-or-ref>
agent-browser get url
agent-browser get title
agent-browser is visible <sel-or-ref>
agent-browser get styles <selector>
```

### Visual output

```bash
agent-browser screenshot --annotate <path>
agent-browser screenshot --full <path>
```

### Reliability helpers

```bash
agent-browser wait --load networkidle
agent-browser wait <selector>
agent-browser wait --text "..."
agent-browser errors
agent-browser console
```

---

## Design-review checklist (page pass)

For each page (`/two-way-utility`, `/system-values`, `/team-summary`, `/drafts`, `/trades`, `/transactions`, entity pages):

1. **Shell pattern match**
   - Pattern A/B/C from `web/docs/design_guide.md`.
2. **Command bar invariants**
   - `#commandbar` exists, `h-[130px]`, sticky behavior consistent.
3. **Patch boundaries exist where expected**
   - `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#flash`.
4. **Density and rows**
   - No card drift; dense row/table treatment.
   - Numeric cells use `font-mono tabular-nums`.
5. **Hover consistency**
   - Yellow hover treatment on row surfaces.
6. **Scroll ownership**
   - One intentional dense-surface scroll owner; no accidental nested scroll traps.
7. **Dark mode sanity check**
   - `dark:` variants remain readable and consistent.

Capture before/after screenshots in `/tmp/agent-browser/` during active work.

---

## Session hygiene

Use a dedicated session for this project to avoid cross-site state bleed:

```bash
agent-browser --session pcms-web open http://localhost:3000
```

Close when done:

```bash
agent-browser close
```

---

## Fast multi-page audit loop

```bash
agent-browser open http://localhost:3000/team-summary && \
agent-browser wait --load networkidle && \
agent-browser screenshot --full /tmp/agent-browser/team-summary.png
```

Repeat for each route; compare against Salary Book + Noah visual language.

---

## Notes for Datastar pages

- After actions that morph content, run `snapshot` again before the next click.
- Prefer refs from fresh snapshots over stale selectors.
- If an interaction appears flaky, use explicit waits (`wait --text`, `wait <selector>`) before continuing.
