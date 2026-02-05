# DB conventions + how to adapt to Postgres multi-schema

Basecamp apps here are not Postgres-first, but they contain a lot of *portable* DB + schema hygiene patterns.

---

## Fizzy: adapter flexibility + multi-DB composition

### Dynamic database.yml
Source: `fizzy.txt` → `config/database.yml`

- Delegates to `config/database.<adapter>.yml` depending on `Fizzy.db_adapter`.
- Supports at least:
  - `config/database.sqlite.yml`
  - `config/database.mysql.yml` (adapter `trilogy`)

### Separate DBs for Rails subsystems
Source: `fizzy.txt` → `config/database.sqlite.yml` + `config/database.mysql.yml`

Common layout:
- `primary`
- `cable` (ActionCable)
- `cache` (Solid Cache)
- `queue` (Solid Queue)

This maps well to Postgres too (same server, different DBs or different schemas/search_path per connection).

---

## Fizzy: read/write splitting + replicas (optional)

Sources:
- `fizzy.txt` → `lib/rails_ext/active_record_replica_support.rb`
- `fizzy.txt` → `config/initializers/multi_db.rb`
- `fizzy.txt` → `config/initializers/database_role_logging.rb`
- `fizzy.txt` → `lib/deployment/database_resolver.rb`

Patterns:
- `ApplicationRecord` calls `configure_replica_connections`.
- If a `replica` db config exists:
  - `connects_to database: { writing: :primary, reading: :replica }`
  - Rails database selector/resolver middleware is configured.
  - Logs are tagged with the active role.

---

## Fizzy: UUID strategy (and why it matters)

Sources:
- `fizzy.txt` → `config/application.rb` (generators default to UUID PKs)
- `fizzy.txt` → `lib/rails_ext/active_record_uuid_type.rb`
- `fizzy.txt` → `config/initializers/uuid_primary_keys.rb`

Key idea:
- UUIDs are the default primary keys.
- For MySQL + SQLite, they implement a **custom UUID type**:
  - generates UUIDv7
  - stores as binary/blob
  - exposes a **base36 string representation** (shorter than hex)

We don’t need the MySQL/SQLite adapter patches, but the *decision* is relevant:
- Postgres can do native `uuid` columns.
- We can still consider UUIDv7 and/or shorter public IDs if URLs matter.

---

## Fizzy: multi-tenant safety in framework models

Source: `fizzy.txt` → `config/initializers/uuid_framework_models.rb`

- Injects `belongs_to :account` into:
  - ActionText::RichText
  - ActiveStorage::Blob/Attachment/VariantRecord

This is a strong pattern if we allow uploads in a multi-tenant app.

---

## Solid Cable/Cache/Queue vs Redis/Resque

### Fizzy
- ActionCable uses Solid Cable (DB-backed):
  - `fizzy.txt` → `config/cable.yml`
- Solid Cache uses `config/cache.yml`.
- Solid Queue uses `config/queue.yml` + recurring jobs `config/recurring.yml`.

### Campfire
- SQLite primary DB only.
- ActionCable uses Redis:
  - `campfire.txt` → `config/cable.yml`
- Jobs via Resque.

---

## Campfire: SQLite + FTS search index

Source: `campfire.txt` → `app/models/message/searchable.rb`

- Uses a SQLite FTS virtual table (`message_search_index`) and a join in a scope:
  - `joins("join message_search_index idx on messages.id = idx.rowid")`

The exact implementation is SQLite-specific, but the pattern is portable:
- maintain a dedicated search index structure
- keep the query surface as a simple `scope :search`

---

## How we adapt this to *our* Postgres world

We already have many schemas and `pcms` is the imported source of truth.

Proposed structure:
- `pcms` schema: imported + derived warehouse tables (read-only from Rails)
- `web` schema: Rails-owned tables (write-side: slugs, notes, scenarios, overrides)

Implementation options in Rails:

1) **Postgres search_path approach**
- Set `schema_search_path` so migrations land in `web` but reads can still see `pcms`.
  - This is what `web/config/database.yml` does by default.

2) **Explicit schema-qualified models**
- Read models map to `pcms.*`:
  - `self.table_name = "pcms.salary_book_warehouse"`

3) Separate connections only if it buys clarity
- e.g., a dedicated connection for `pcms` read-only, but likely unnecessary.

Also decide where Solid Queue/Cache/Cable tables live:
- simplest: keep them in the same Postgres DB, in `web` schema
- or separate schemas (`web_queue`, `web_cache`) by using separate DB configs with different `schema_search_path`.
