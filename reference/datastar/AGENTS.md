# AGENTS.md — `reference/datastar/`

This folder is the **Datastar reference pack** for this repo. Start here.

---

## TL;DR (conventions to follow)

- **Signals are flatcase**: `activeteam`, `overlaytype`, `displaycapholds` (NOT camelCase, NOT kebab-case)
- **DOM refs are underscore-prefixed**: `data-ref="_dialog"` → use as `$_dialog`
- **Patch whole sections by stable ID**: `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#teamsection-<TEAM>`
- **Response types**: `text/html` (default, morph by ID), `application/json` (signal-only), `text/event-stream` (SSE for multi-part or streaming)
- **Expressions need semicolons** between statements
- **Don't mix static + bound attributes**: no `value="..."` with `data-bind`, no `style="display:none"` with `data-show`

---

## What's in here

| File | Purpose |
|------|---------|
| `insights.md` | **Start here.** Curated conventions, naming rules, patching strategy, gotchas. |
| `rails.md` | Rails-specific: ActionController::Live, SSE framing, production checklists. |
| `basecamp.md` | Synthesis: Basecamp-style Rails patterns translated to Datastar. |
| `docs.md` | Vendor docs snapshot (large). Use for deep reference on attributes/actions. |

---

## Reading order

1. `insights.md` — conventions + gotchas (read first)
2. `rails.md` — if you're building Rails + Datastar
3. `basecamp.md` — for "how would Basecamp do this with Datastar?" patterns
4. `docs.md` — deep reference when you need attribute/action details

Also useful:
- `prototypes/salary-book-react/docs/bun-sse.md` — SSE framing helpers (Bun, but framing applies everywhere)

---

## Common patterns

### Response types (pick the simplest)

| Content-Type | Datastar behavior | When to use |
|--------------|-------------------|-------------|
| `text/html` | Morph elements by `id` | Most updates. Default choice. |
| `application/json` | Merge Patch into signals | Pure signal updates, no DOM change. |
| `text/event-stream` | Stream `datastar-patch-*` events | Multi-part updates, progress, live feeds. |

### Patching strategy

- **Patch whole sections**, not tiny fragments. Datastar morphing is good.
- Keep IDs stable. That's the contract.
- Protect third-party widgets with `data-ignore-morph`.

### Custom JS (keep it minimal)

Datastar + CSS handles most things. Custom JS only when truly needed:
- Scroll spy (emits CustomEvent → Datastar updates signals)
- Overlay exit animations (if CSS `@starting-style` isn't enough)

Sticky headers? CSS. Scroll sync? Usually CSS or Datastar. Lean on the framework.

---

## Guardrails

- **Signals are user-mutable input.** Never trust them for auth/permissions.
- **Don't await inside expressions.** Use CustomEvent bridging for async flows.
- **CSP needs `unsafe-eval`** (Datastar uses Function constructor).

---

## When adding new material

- Keep vendor snapshots as plain `.md` (easy to grep/ingest).
- Put repo-specific patterns in `insights.md`.
- Link new helpers here.
