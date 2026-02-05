# prototypes/salary-book-react/AGENTS.md — Salary Book React prototype

> Notes for AI coding agents working in **prototypes/salary-book-react/**.

## What this is

This directory is the **previous Bun + React + TypeScript** Salary Book prototype.

It’s kept for:
- UX/markup reference (dense table grammar, right-panel overlay behavior)
- JS runtime reference (scroll spy, scroll sync, overlay transitions)
- historical API/SQL contracts (what queries the UI needed)

**Canonical app going forward:** `web/` (Rails + Datastar).

Canonical docs/specs now live in `web/`:
- `web/AGENTS.md`
- `web/specs/*`
- `web/MIGRATION_MEMO.md`

---

## Running locally (prototype)

```bash
cd prototypes/salary-book-react
bun install

POSTGRES_URL="$POSTGRES_URL" bun run dev
```

Notes:
- `src/server.ts` defaults to **port 3002** if `PORT` is not set.
- This prototype reads from Postgres (`pcms.*` warehouses) via `POSTGRES_URL`.

---

## Project structure (prototype)

```
src/
  server.ts           # Bun server entry point (Bun.serve)
  client.tsx          # React app entry point
  index.html          # HTML shell
  api/
    routes/           # API route handlers (salary-book.ts, etc.)
  features/SalaryBook/
    shell/            # scroll-spy, transitions
    components/       # MainCanvas + RightPanel
  lib/
    animate.ts        # WAAPI helpers (commitStyles()+cancel())
    utils.ts          # cx(), focusRing(), formatters

docs/                 # Bun-specific runtime notes (kept with prototype)

tests/                # Bun test harness
```

---

## Guardrails

- Treat this directory as **reference / prototype**.
- New feature work should generally go to the Rails app in `web/`.
- Don’t duplicate cap/trade logic in TS — it belongs in SQL (`migrations/`).
