# `Current`, authentication, authorization patterns

This doc captures *portable patterns* from Basecamp-style Rails apps.

---

## 1) `Current` as the request context container

### Fizzy
Source: `fizzy.txt` → `app/models/current.rb`

- Attributes:
  - `session`, `user`, `identity`, `account`
  - request metadata: `http_method`, `request_id`, `user_agent`, `ip_address`, `referrer`
- Derived assignment:
  - setting `Current.session` sets `Current.identity`
  - setting `Current.identity` selects `Current.user` *for the current account*
- Helpers:
  - `Current.with_account(account) { ... }`
  - `Current.without_account { ... }`

Request metadata population:
- `fizzy.txt` → `app/controllers/concerns/current_request.rb`
  - populates `Current.*` from `request` in a before_action.

### Campfire
Source: `campfire.txt` → `app/models/current.rb`

- Attributes:
  - `session`, `user`, `request`
- `Current.account` is `Account.first` (single-tenant assumption).
- `SetCurrentRequest` concern stores `Current.request`.

---

## 2) Authentication concerns (the “macro” style)

### Fizzy: identity-first + magic links + bearer tokens
Source: `fizzy.txt` → `app/controllers/concerns/authentication.rb`

Key behaviors:
- `before_action :require_account` then `:require_authentication`
- Cookie-backed sessions:
  - `Session.find_signed(cookies.signed[:session_token])`
  - cookie stores a **signed_id**, not a raw token
- Supports API-style auth:
  - `Authorization: Bearer <token>`
  - resolves to `Identity.find_by_permissable_access_token(token, method: request.method)`
- Nice controller macros:
  - `allow_unauthenticated_access` (skips require_authentication, resumes session)
  - `require_unauthenticated_access` (redirects authenticated users)
  - `disallow_account_scope` (used for non-tenanted controllers like login)

Magic-link login flow:
- `fizzy.txt` → `app/controllers/sessions_controller.rb`
  - sign-in and sign-up both trigger `Identity#send_magic_link`
- `fizzy.txt` → `app/controllers/sessions/magic_links_controller.rb`
  - consumes code via `MagicLink.consume(code)`
  - uses `secure_compare` against an “email pending authentication” cookie
  - on success: `start_new_session_for magic_link.identity`
- `fizzy.txt` → `app/models/identity.rb`, `app/models/magic_link.rb`

### Campfire: email/password + bot keys
Source: `campfire.txt` → `app/controllers/concerns/authentication.rb`

Key behaviors:
- Cookie-backed sessions using a raw token:
  - cookie value is `session.token` (model has `has_secure_token`)
- Password auth:
  - `SessionsController#create` uses `User.active.authenticate_by(email_address:, password:)`
- Bot auth:
  - `:bot_key` param enables bot authentication (opt-in per controller via `allow_bot_access`)
- CSRF handling:
  - `protect_from_forgery ... unless: -> { authenticated_by.bot_key? }`

---

## 3) Authorization

### Fizzy
Source: `fizzy.txt` → `app/controllers/concerns/authorization.rb`

- Account gate:
  - `ensure_can_access_account` checks:
    - `Current.account.active?`
    - `Current.user&.active?`
  - HTML redirects to `session_menu_path(script_name: nil)`; JSON returns 403.
- Convenience guards:
  - `ensure_admin` (user admin)
  - `ensure_staff` (identity staff)

### Campfire
Source: `campfire.txt` → `app/controllers/concerns/authorization.rb`

- Minimal guard:
  - `ensure_can_administer` delegates to `Current.user.can_administer?`

---

## 4) Rate limiting and “browser gating”

Both apps use Rails 8-era controller macros:
- `rate_limit to:, within:, only:, with:`
  - Campfire: `campfire.txt` → `app/controllers/sessions_controller.rb`
  - Fizzy: `fizzy.txt` → `app/controllers/sessions_controller.rb` + `sessions/magic_links_controller.rb`

Browser gating:
- Fizzy `ApplicationController` uses: `allow_browser versions: :modern`.
- Campfire has an `AllowBrowser` concern with explicit minimum versions.

### Parameter handling: `params.expect` (Fizzy) vs `require/permit` (Campfire)
- Fizzy leans on Rails 8’s stricter `params.expect(...)` API throughout controllers.
  - Example patterns seen:
    - `params.expect(:email_address)`
    - `params.expect(user: [ :name, :avatar ])`
    - `params.expect(webhook: [ :name, :url, subscribed_actions: [] ])`
- Campfire mostly uses classic strong params:
  - `params.require(:user).permit(...)`

Takeaway:
- For our app, `params.expect` is worth adopting if we’re on Rails 8+ (more explicit “shape checking” than `permit`).

---

## 5) Cross-cutting multi-tenant patterns (Fizzy)

Fizzy’s multi-tenancy is **script_name-based mounting** (account prefix in the URL) and shows up in:
- Rack middleware rewriting `SCRIPT_NAME` / `PATH_INFO`:
  - `fizzy.txt` → `config/initializers/tenanting/account_slug.rb`
- Turbo stream rendering with the right `script_name`:
  - `fizzy.txt` → `config/initializers/tenanting/turbo.rb`
- Jobs carrying account context:
  - `fizzy.txt` → `config/initializers/active_job.rb`

(We keep deeper notes in `08-multi-tenancy-script-name.md`.)

---

## What we should steal for our Rails app

High-leverage patterns for our repo:
- Use `Current` + concerns-first `ApplicationController` composition.
- Adopt the macro style:
  - `allow_unauthenticated_access`, `require_unauthenticated_access`
- Use Rails’ built-in `rate_limit` for sensitive endpoints.

Open design choice for us:
- Auth style:
  - Campfire-style password auth is simplest for an internal tool.
  - Fizzy-style Identity + magic links + bearer tokens is excellent if we want:
    - account switching
    - API access tokens
    - passwordless login

DB adaptation reminder:
- Read-only models mapped to `pcms.*_warehouse`.
- Write-side models (sessions, users, annotations, scenarios) live in `web.*`.
