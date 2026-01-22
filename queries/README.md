# queries/

This folder is the **new** scratchpad + repeatable SQL checks for this repo.

Principles:
- Postgres (`$POSTGRES_URL`) is the source of truth.
- Prefer **assertion-style** SQL that fails fast (so it can be used in CI later).
- Keep anything tool-facing in `pcms.*_warehouse`; these are just queries/tests.

## Run everything

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```

## Run a single file

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/020_exceptions_warehouse_assertions.sql
```

## Conventions
- Files in `queries/sql/` are meant to be runnable.
- Use `DO $$ ... RAISE EXCEPTION ... $$;` for assertions.
- Keep tests **data-robust** (avoid hardcoding player ids unless the test itself seeds fixtures).
