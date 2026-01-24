# PCMS Salary Book (web)

This directory contains the **Salary Book** web app for this repo.

- Runtime: **Bun**
- UI: **React + TypeScript**
- API: Bun `routes` under `/api/*`
- Data: reads from Postgres `pcms.*` tables (typically `*_warehouse` views/tables)

## Prereqs

- Bun installed
- A Postgres database with the `pcms` schema populated (run the Python import flow in the repo root)
- `POSTGRES_URL` set when using Salary Book endpoints

## Dev

```bash
cd web
bun install

# Start dev server (hot reload)
POSTGRES_URL="$POSTGRES_URL" bun run dev

# Optional: choose a port
PORT=3001 POSTGRES_URL="$POSTGRES_URL" bun run dev
```

Default port is **3002** if `PORT` is not set.

## Tests

```bash
cd web
bun test
```

Tests spin up a server on an ephemeral port and hit `/api/health`.
