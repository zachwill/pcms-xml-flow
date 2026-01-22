# queries/sql/

Runnable SQL artifacts (copy/paste into `psql` or use with `-f`).

## Usage

```bash
# Print the full result set (all rows)
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/y_warehouse.sql

# Tip: for LIMIT / WHERE experimentation, open an interactive session:
psql "$POSTGRES_URL"
# then run:
#   \i queries/sql/y_warehouse.sql
# and/or copy the query into a scratch buffer and add LIMIT/filters.
```

### Export to CSV (recommended)

From an interactive `psql` session:

```sql
\copy (
  -- paste the query from y_warehouse.sql here
) TO 'y_warehouse.csv' CSV HEADER;
```

## Files

- `y_warehouse.sql` – forward-looking player warehouse (2025–2030), one row per active player
