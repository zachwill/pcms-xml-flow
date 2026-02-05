# Basecamp Rails references — Index

Goal: extract *portable patterns* from the `fizzy.txt` and `campfire.txt` dumps to accelerate building our own Rails/Postgres site.

Constraints:
- Don’t boil the ocean — prefer small, high-signal files.
- Capture patterns and decisions; avoid copying large blocks of app-specific code.
- Always record the **dump filename** + **file path** you learned from.

## How the dumps are formatted

Each dump contains many `File:` blocks:

```text
================
File: config/routes.rb
================
...contents...
```

Find offsets with ripgrep:

```bash
rg -n "^File: config/routes\\.rb$" reference/basecamp/fizzy.txt
```

Then open the dump near that line number.

## What we want to extract (specs/notes)

1) **Navigation / search playbook**
   - How to quickly locate key files in the dumps
   - Common `rg` one-liners
   - See: `01-dump-navigation.md`

2) **Rails stack + gems (Rails 8-era defaults)**
   - Hotwire, propshaft/importmap conventions
   - jobs/caching/realtime choices (Solid* vs Resque, Redis, etc)
   - deployment/runtime (Kamal, Thruster)
   - See: `02-rails-stack-and-gems.md`

3) **Request context + AuthN/AuthZ**
   - `Current` pattern
   - session management
   - authorization style (roles/permissions)
   - See: `03-current-authentication-authorization.md`

4) **Routing + controller organization**
   - namespacing conventions
   - resource shapes, REST patterns
   - how they keep controllers thin
   - See: `04-routes-and-resource-shapes.md`

5) **UI patterns (server-rendered + Hotwire)**
   - Turbo Frames/Streams usage
   - Stimulus controller patterns
   - partial + presenter conventions
   - See: `06-ui-hotwire-patterns.md`

6) **Ops / CI / security / observability**
   - CI scripts, linting, Brakeman, audits
   - logging, Sentry, metrics
   - See: `05-ops-jobs-telemetry-deploy.md`

7) **DB conventions we may want**
   - migrations, keys, multi-tenancy, sharding patterns
   - and how we adapt to Postgres + multi-schema (`pcms` + `web`)
   - See: `07-db-conventions.md`

8) **Multi-tenancy via `SCRIPT_NAME` (Fizzy pattern)**
   - how Fizzy mounts the app at `/<account_slug>` without route namespacing
   - ActionCable/Turbo/ActiveJob implications
   - See: `08-multi-tenancy-script-name.md`

9) **Fizzy framework patches (`lib/rails_ext/*`)**
   - small Rails monkey patches + why they exist
   - “should we adopt?” notes for each patch
   - See: `09-rails-ext-inventory.md`

## Dump files we have

- `reference/basecamp/fizzy.txt`
- `reference/basecamp/campfire.txt`
