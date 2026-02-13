# Ruby on Rails + Datastar: SSE streaming + patching patterns

Datastar is a *hypermedia-first* runtime: the backend returns **HTML** (and/or signal patches) and Datastar morphs them into the DOM.

This doc is **Rails-specific glue** (ActionController::Live, SSE framing, production gotchas). For Datastar-wide conventions and footguns, read:

- `reference/datastar/insights.md` (curated field notes / naming rules)
- `reference/datastar/docs.md` (vendor snapshot)
- `prototypes/salary-book-react/docs/bun-sse.md` (SSE framing helpers — useful even if you’re not on Bun)

---

## 0) Conventions that matter in Rails templates

### 0.1 Signals: prefer **flatcase** (all lowercase, no separators)

Project convention: **global signal keys are flatcase**.

- ✅ `playerid`, `latestupdate`, `welcomemessage`
- ❌ `player_id` (snake_case), `latestUpdate` (camelCase), `welcome-message` (kebab-case)

Why we still recommend flatcase on Rails:

- HTML `data-*` attribute **names are case-insensitive**, and Datastar supports a *name syntax* like `data-bind:foo-bar`.
  - Hyphenated names are **normalized to camelCase** (`foo-bar` → `$fooBar`). That’s valid but easy to misread.
  - CamelCase in attribute *names* is a trap (`data-bind:fooBar` becomes `data-bind:foobar`).
- Flatcase avoids normalization surprises and keeps agent-generated markup consistent.

If you want a compromise:

- **snake_case** is *usually fine* (underscores survive HTML lowercasing and JS identifiers allow `_`), but you must stay consistent and avoid leading `_` unless you truly want a local-only signal.
- **kebab-case** is the one to avoid for signals because you’ll end up referencing `$fooBar` anyway.

### 0.2 Local-only signals + DOM refs: underscore prefix

- Any signal key that begins with `_` is **local** (browser-only / not serialized back to the backend).
- **DOM refs must be underscore-prefixed** so they don’t get serialized:
  - `data-ref="_dialog"` → use as `$_dialog` in expressions.

### 0.3 Patching strategy: stable IDs + “patch whole sections”

- Prefer patching **whole regions** (cards/panels/drawers) using stable `id`s.
- Protect third-party widget roots with `data-ignore-morph` and patch around them.

---

## 1) Choose response type by patch shape

Datastar behavior is driven by the response **Content-Type**:

| Response Content-Type | What Datastar does | When to use |
|---|---|---|
| `text/html` | Morph top-level elements into the DOM (by `id` by default). | Most UI updates. Simplest path. |
| `application/json` | JSON Merge Patch into signals. | Pure “data only” updates. |
| `text/event-stream` | Apply `datastar-patch-elements` / `datastar-patch-signals` events. | Multi-region/disjoint patches, ordered patch sequences, streaming/progress, and long-lived feeds. |

Rule of thumb:
- Single-region update → `text/html`
- Multi-region update:
  - if you only need to patch elements and can return multiple **top-level** `id` roots → `text/html` morph-by-id patch set (see `reference/datastar/morph_by_id.md`)
  - if you need signals, explicit modes/selectors, ordering, or streaming → short-lived `text/event-stream` (one-off SSE is fine)
- Signal-only update → `application/json`

---

## 2) Enabling Server-Sent Events in Rails

Rails supports SSE via **ActionController::Live**.

High-level checklist:

- Include `ActionController::Live` in the controller.
- Set `Content-Type: text/event-stream`.
- Add headers to prevent buffering (`Cache-Control: no-cache, no-transform`, `X-Accel-Buffering: no`).
- Be aware of **thread usage**: each open stream typically consumes a server thread.

### Example: one-off SSE response that patches signals + elements

This pattern is common with Datastar: the request is “normal”, but the response streams 1–N Datastar patch events and then closes.

```ruby
class StatusController < ApplicationController
  include ActionController::Live

  def show
    response.headers["Content-Type"] = "text/event-stream; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-transform"
    response.headers["X-Accel-Buffering"] = "no"   # nginx
    response.headers["Last-Modified"] = Time.now.httpdate # helps defeat some ETag buffering

    sse = SSE.new(response.stream, retry: 5_000)

    begin
      # 1) Patch signals (flatcase)
      sse.write(
        "signals #{ { status: 'connected' }.to_json }",
        event: "datastar-patch-signals",
      )

      # 2) Patch elements (inner HTML of #status)
      html = render_to_string(partial: "status")
      data_lines = [
        "mode inner",
        "selector #status",
        *html.lines.map { |l| "elements #{l.chomp}" },
      ]

      sse.write(data_lines.join("\n"), event: "datastar-patch-elements")
    rescue ActionController::Live::ClientDisconnected
      # client navigated away / closed tab
    ensure
      sse.close
    end
  end
end
```

Notes:

- `SSE#write` splits the payload on newlines and prefixes each one with `data:`.
- For `datastar-patch-elements`, Datastar expects the payload lines to include `mode`, `selector`, and one-or-more `elements ...` lines (see section 4).

---

## 3) One-off SSE responses vs persistent streams

### One-off (request/response) SSE

Good for:

- form submissions where you want to patch multiple regions
- streamed progress (a few updates) and then close

### Persistent SSE streams

Good for:

- notifications
- live dashboards
- job log tails

Remember:

- Browser connection limits still apply (often ~6 concurrent HTTP/1.1 connections per origin; HTTP/2 raises that limit).
- Many proxies/load balancers kill idle connections (~60s). Plan for heartbeats.

### Example: persistent stream with keepalive + disconnect handling

```ruby
class FeedController < ApplicationController
  include ActionController::Live

  def live
    response.headers["Content-Type"] = "text/event-stream; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-transform"
    response.headers["X-Accel-Buffering"] = "no"

    sse = SSE.new(response.stream, retry: 5_000)

    begin
      loop do
        break if response.stream.closed?

        # Keepalive comment (helps proxies keep the connection open)
        response.stream.write(": keepalive #{Time.now.to_i}\n\n")

        # Example signal push
        sse.write(
          "signals #{ { timestamp: Time.now.to_i }.to_json }",
          event: "datastar-patch-signals",
        )

        sleep 15
      end
    rescue ActionController::Live::ClientDisconnected
      # disconnect
    ensure
      sse.close
    end
  end
end
```

Frontend tip:

- For dashboard-style streams, call Datastar backend actions with `{ openWhenHidden: true }` so the connection stays open when the tab is backgrounded.

---

## 4) Datastar SSE event framing (manual)

Datastar SSE events are **not** “just send HTML/JSON”. The `data:` lines are structured.

### `datastar-patch-signals`

- Send a single line starting with `signals ` followed by JSON.

```text
event: datastar-patch-signals
data: signals {"status":"connected"}

```

### `datastar-patch-elements`

- Send `mode <mode>` and `selector <css selector>` lines.
- Then send one-or-more `elements <html...>` lines.

```text
event: datastar-patch-elements
data: mode inner
data: selector #status
data: elements <p>Connected.</p>

```

Practical Rails helper for element payloads:

```ruby
def datastar_elements_payload(selector:, html:, mode: "inner")
  [
    "mode #{mode}",
    "selector #{selector}",
    *html.lines.map { |l| "elements #{l.chomp}" },
  ].join("\n")
end
```

Then:

```ruby
html = render_to_string(partial: "status")
sse.write(datastar_elements_payload(selector: "#status", html: html), event: "datastar-patch-elements")
```

---

## 5) Optional: Datastar Ruby SDK

Datastar has a Ruby SDK: https://github.com/starfederation/datastar-ruby

If you adopt it, the goal is simply to avoid hand-assembling the `mode`/`selector`/`elements` and `signals` payloads.

Keep the naming conventions above (flatcase signals; underscore-prefixed refs) even if the SDK makes other styles *possible*.

---

## 6) Reading Datastar signals in Rails requests (parsing `params[:datastar]`)

Datastar backend actions send signals automatically with each request:

- `@get()` typically sends `?datastar=<json>` (string)
- other verbs typically send a JSON body like `{ datastar: {...} }` (already parsed)

Parse defensively (and treat it as **untrusted input**):

```ruby
def datastar_signals
  raw = params[:datastar]

  parsed =
    case raw
    when String
      JSON.parse(raw) rescue nil
    when ActionController::Parameters
      raw.to_unsafe_h
    when Hash
      raw
    else
      nil
    end

  return {} unless parsed.is_a?(Hash)

  # Some clients wrap as { "signals": {...} }
  if parsed["signals"].is_a?(Hash)
    parsed["signals"]
  else
    parsed
  end
end
```

Recommended usage pattern:

- Prefer explicit query params (shareable URLs / works without JS).
- Fall back to Datastar signals only if explicit params aren’t present.
- Use an allowlist (`slice`) of keys you expect (don’t blindly trust everything in `datastar`).

---

## 7) Reliability checklist (production SSE)

- Send `retry: <ms>` (Rails can set this via `SSE.new(..., retry: ...)`).
- Send keepalive comments (`: keepalive ...`) about every ~15s.
- Disable buffering:
  - `Cache-Control: no-cache, no-transform`
  - `X-Accel-Buffering: no` (nginx)
  - Consider disabling `Rack::ETag` / `Rack::ConditionalGet` for SSE endpoints if you see buffering.
- Stop work on disconnect (`ActionController::Live::ClientDisconnected`) and close the stream.

---

## 8) Security checklist

- **Signals are user-mutable input.** Never put secrets in signals; validate/authorize based on server truth.
- Escape/sanitize any user-generated HTML you patch into the DOM.
- Authenticate/authorize streams like any other endpoint.
- Mitigate DoS:
  - rate limit connections
  - cap per-user streams
  - monitor threads/file descriptors
- Datastar evaluates expressions using `Function` internally; CSPs generally need `'unsafe-eval'`.

---

## 9) Performance + deployment notes

- Each open SSE connection can occupy a Rails server thread (e.g., Puma). Size thread pools accordingly.
- Don’t do heavy work inside the streaming loop. Offload to background jobs / pubsub.
- In multi-node deployments, reconnects may hit a different node. For broadcasts, use Redis/pubsub/etc.
- Prefork-only servers (e.g., Unicorn) are a poor fit for long-lived SSE.

---

## Sources / references

- Rails API — ActionController::Live::SSE
  - https://api.rubyonrails.org/classes/ActionController/Live/SSE.html
- Datastar docs — SSE events + backend requests
  - https://data-star.dev/
  - https://data-star.dev/reference/sse_events
  - https://data-star.dev/guide/backend_requests
- Datastar Ruby SDK
  - https://github.com/starfederation/datastar-ruby
