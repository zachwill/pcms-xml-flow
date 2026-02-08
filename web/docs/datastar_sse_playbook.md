# Datastar SSE playbook (web)

Use this when implementing interactions that patch HTML from Rails.

## Response decision rule

- **Single-region update** → `text/html`
- **Multi-region/disjoint update** (or ordered patch steps) → `text/event-stream` (one-off SSE is normal)
- **Signals-only update** → `application/json`

## Multi-region update rule (hard)

If one interaction must update two or more of:
- `#commandbar`
- `#maincanvas`
- `#rightpanel-base`
- `#rightpanel-overlay`
- `#flash`

→ respond with `text/event-stream` and stream patches in order.

Do **not** do multiple fetches or client-side stitching.

## Using the `Datastar` concern

The repo provides `app/controllers/concerns/datastar.rb` with all the SSE boilerplate.

```rb
class MyController < ApplicationController
  include Datastar

  def update
    with_sse_stream do |sse|
      # Patch HTML into a selector
      patch_elements(sse, selector: "#rightpanel-overlay", html: overlay_html, mode: "inner")

      # Patch HTML using morph-by-id (no selector — matches on element id attrs)
      patch_elements_by_id(sse, section_html)

      # Convenience: patch #flash
      patch_flash(sse, "Loading…")

      # Patch signals
      patch_signals(sse, overlaytype: "player", status: "done")
    end
  end
end
```

### Available methods

| Method | Purpose |
|--------|---------|
| `with_sse_stream { \|sse\| ... }` | Sets headers, yields SSE writer, handles cleanup |
| `patch_signals(sse, **signals)` | Sends `datastar-patch-signals` event |
| `patch_elements(sse, selector:, html:, mode:)` | Sends `datastar-patch-elements` with selector |
| `patch_elements_by_id(sse, html)` | Sends `datastar-patch-elements` (morph by id) |
| `patch_flash(sse, message)` | Convenience for patching `#flash` |

### Patch modes

From Datastar docs — `mode` options for `patch_elements`:

| Mode | Behavior |
|------|----------|
| `inner` | Replace element's innerHTML (default) |
| `outer` | Replace entire element |
| `replace` | Same as outer |
| `prepend` | Insert at start of element |
| `append` | Insert at end of element |
| `before` | Insert before element |
| `after` | Insert after element |
| `remove` | Remove element |

## Raw SSE format (for reference)

If you need to understand what's happening under the hood:

```text
event: datastar-patch-elements
data: mode inner
data: selector #flash
data: elements <div id="flash">Loading…</div>

event: datastar-patch-signals
data: signals {"status":"done","overlaytype":"player"}
```

For morph-by-id (no selector/mode):

```text
event: datastar-patch-elements
data: elements <div id="team-bos">...</div>
data: elements   <div class="row">...</div>
data: elements </div>
```

## Repo examples

- Concern: `web/app/controllers/concerns/datastar.rb`
- SSE usage (Salary Book): `web/app/controllers/tools/salary_book_sse_controller.rb`
- HTML bootstrap (entities): `web/app/controllers/entities/players_sse_controller.rb`, `teams_sse_controller.rb`
- Routes:
  - `GET /tools/salary-book/sse/bootstrap` (shell → full maincanvas hydration, SSE)
  - `GET /tools/salary-book/sse/patch-template`
  - `GET /tools/salary-book/sse/demo` (legacy alias)
  - `GET /players/:slug/sse/bootstrap` (text/html, morph-by-id)
  - `GET /teams/:slug/sse/bootstrap` (text/html, morph-by-id)

## Entity page bootstrap pattern (text/html, not SSE)

Entity pages (players, teams) use a simpler pattern than the Salary Book:
the bootstrap endpoint returns **`text/html`** with all rendered sections
concatenated. Datastar morphs each top-level element by its `id` attribute.

```ruby
# Controller — return concatenated HTML partials
def bootstrap
  load_workspace_data!
  html_parts = SECTION_PARTIALS.map { |p| render_to_string(partial: p) }
  render html: html_parts.join("\n").html_safe, layout: false
end
```

```erb
<%# View — fire once when element is processed by Datastar %>
<div id="player-bootstrap" class="hidden" aria-hidden="true"
     data-init="@get('/players/<%= @player_slug %>/sse/bootstrap')">
</div>
```

Why not SSE here? Entity workspaces have a fixed set of sections that all
render from the same data load. A single `text/html` response is simpler,
avoids `ActionController::Live` threading, and Datastar's morph handles
the rest.

## Avoid these traps

- Missing anti-buffering headers (the concern handles this for SSE).
- Treating SSE as "only long-lived" — one-off SSE is fine and preferred for multi-region.
- Emitting too many micro-patches instead of section-level patches.
- Forgetting disconnect handling (the concern handles this for SSE).
- Using SSE when `text/html` morph-by-id is sufficient (entity pages).
- Missing `Cache-Control: no-store` on bootstrap endpoints (prevents stale 304s).
