# Multi-tenancy via `SCRIPT_NAME` (Fizzy pattern)

Fizzy is the best “reference implementation” in these dumps for **multi-tenant Rails** without rewriting every route.

The core trick: *mount the same Rails app under a tenant prefix* by rewriting Rack’s `SCRIPT_NAME` and `PATH_INFO`.

This produces URLs like:
- `/123/boards/…`
- `/456/cards/…`

…but inside Rails routes remain un-namespaced.

---

## 1) Tenant extraction middleware

Source: `fizzy.txt` → `config/initializers/tenanting/account_slug.rb`

- A Rack middleware (`AccountSlug::Extractor`) runs early.
- If the request path begins with `/<digits>`:
  - moves that prefix to `request.script_name`
  - strips it from `request.path_info`
  - stores the decoded account id in `env["fizzy.external_account_id"]`
- Then it finds the `Account` and wraps the request in:
  - `Current.with_account(account) { @app.call(env) }`

Takeaway:
- Rails URL helpers will automatically include `script_name`.
- You don’t have to wrap every route in `scope "/:account"`.

---

## 2) Account slug helpers

Source: `fizzy.txt` → `app/models/account.rb`

- `Account#slug` returns `"/#{AccountSlug.encode(external_account_id)}"`.

Takeaway:
- “external_account_id” decouples public routing from internal UUIDs.

---

## 3) Controllers that must escape tenant scope

Source: `fizzy.txt` → `app/controllers/concerns/authentication.rb`

Macro:
- `disallow_account_scope`:
  - skips `require_account`
  - redirects if the request is already tenanted

Used for:
- sessions, signups, magic link entrypoints

---

## 4) ActionCable + Turbo Streams must be script-name aware

### ActionCable URL
Source: `fizzy.txt` → `app/helpers/tenanting_helper.rb`
- emits `<meta name="action-cable-url" content="#{request.script_name}#{mount_path}">`

### Turbo Streams render context
Source: `fizzy.txt` → `config/initializers/tenanting/turbo.rb`
- patches `Turbo::StreamsChannel.render_format` to render using:
  - `ApplicationController.renderer.new(script_name: Current.account.slug)`

Without this, background-rendered stream templates can produce wrong URLs.

---

## 5) Jobs must carry tenant context

Source: `fizzy.txt` → `config/initializers/active_job.rb`

- Serializes `Current.account` into job payload (`to_gid`).
- On perform, rehydrates and wraps `perform_now` in `Current.with_account(account)`.

Takeaway:
- Prevents “jobs running without tenant context” bugs.

---

## 6) Routes and redirects must preserve `request.script_name`

Source: `fizzy.txt` → `config/routes.rb`

Example:
- legacy redirect blocks use `request.script_name` to keep tenant prefix.

---

## How we might use this

We may not need multi-tenancy immediately, but if we ever want:
- multiple orgs/accounts
- account switching
- isolated write-side data per account

…this is a proven pattern to adopt.

If we do adopt it, we should also define which schemas are tenant-scoped:
- `pcms` may remain global/imported
- `web` tables could be scoped by `account_id` (or separate schemas per account, but that’s heavier)
