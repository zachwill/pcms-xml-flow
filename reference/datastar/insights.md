# Datastar — working notes & gotchas (ZachBase-derived)

This is a **curated cheat sheet** for *using Datastar well*.

- **Not** a replacement for vendor docs → see `reference/datastar/docs.md`.
- Focus: conventions that keep server-driven UIs maintainable, plus the stuff that tends to bite.

---

## 1) Mental model (keep this in RAM)

- **Hypermedia-first:** the backend streams **HTML** (and/or signal patches) that mutate the DOM.
- **HTML is the contract:** stable `id` attributes (or explicit CSS selectors) are your patch targets.
- **Two reactive paths:**
  1) **Backend → frontend** via HTML responses, JSON Merge Patch into signals, or SSE events.
  2) **Frontend → frontend** via signals + `data-*` attributes (no custom JS required for most UI state).

Rule of thumb:
- Durable state + permissions + “what’s possible next” → **server decides**.
- Ephemeral UI state (open dialogs, hover preview, selection highlight) → **signals**.

---

## 2) Signal naming conventions (treat these as hard rules)

### 2.1 Global signals (serialized + sent to backend) — flatcase

Project convention: **signals use flatcase**: all-lowercase with **no separators**. Just mash words together.

- ✅ `search`, `selected`, `cmdkactive`, `newslimit`, `playerid`, `shotchart`
- ❌ `player-id`, `selectedPlayer`, `newsLimit`, `player_id`

Why this matters (Datastar gotcha):
- HTML `data-*` attributes are case-insensitive and Datastar **normalizes** hyphenated signal names into **camelCase**.
  - Example: `data-bind:foo-bar` creates `$fooBar` (not `$foo-bar`).
- Avoids bracket-notation (`$['drawer-title']`) and case-conversion surprises.
- Makes regex include/exclude filters predictable.
- Makes it easier for agents to generate expressions reliably.

Non-signal keys (CSS props, normal attributes, and custom event names) can still be kebab-case.

### 2.2 Local signals (browser-only)

Any signal key that begins with `_` is **local** (not automatically serialized/sent with requests).

Primary uses:
- **DOM refs (mandatory)**
- Local-only debug metadata (ex: `__meta`)
- Large objects you *do not* want shipped back to the server

### 2.3 DOM element refs (the one exception)

Refs **MUST** use underscore prefix.

- `data-ref="_dialog"` → use as `$_dialog` in expressions

Reason: DOM nodes contain cyclic references and cannot be JSON-serialized. The underscore keeps the ref local.

Do **not** use underscore for non-ref “normal” signals.

---

## 3) Expressions: syntax + recurring pitfalls

- Datastar expressions are **sandboxed JS strings**.
- **Semicolons matter.** Line breaks are *not* statement separators.
- **Evaluation order matters:** Datastar walks the DOM depth-first and executes attributes left-to-right.
  - If `data-init` triggers network work, place `data-indicator` **before** `data-init` so loading state is visible immediately.
- Special identifiers:
  - `el` → the current element
  - `evt` → the event object (inside `data-on:*` handlers)
  - `$signals` → all signals
- Prefer actions (`@get`, `@post`, …) for side effects.
  - `@peek(() => $foo)` is useful when you need to read a signal without subscribing (avoids accidental reactivity).
- Avoid `await` inside expressions.
  - If you need async coordination, use **CustomEvent** bridging (see section 6).

---

## 4) Patching strategy: how to stay sane

### 4.1 Patch whole sections, not tiny diffs

Datastar’s morphing is good. Lean on it.

When an interaction “commits”, stream the entire card/panel/drawer region (with stable IDs) instead of trying to surgically patch little spans.

### 4.1.1 Morph-by-id patch sets (you don’t need a full page)

Datastar can patch **multiple disjoint regions** from a single `text/html` response by returning **multiple top-level elements** with stable `id`s.

Key constraint: the elements you want to patch must be **top-level siblings** in the response HTML. Wrapping them in a parent `<div>` will prevent morph-by-id from seeing them.

Write-up + examples: `reference/datastar/morph_by_id.md`.

### 4.2 Keep IDs stable

Stable `id` attributes are the simplest, most reliable contract for morphing.

### 4.3 Protect third-party widgets

If a subtree is managed by something else (charts, complex web components), mark the host with:
- `data-ignore-morph`

Then patch around it.

Also useful:
- `data-ignore` / `data-ignore__self`
- `data-preserve-attr="open value ..."` to preserve user-controlled attributes (ex: `<details open>`)

### 4.4 Backend response types (cheat sheet)

Datastar behavior is driven by the response `Content-Type`:

| Content-Type | Browser behavior | Headers you’ll actually use |
|---|---|---|
| `text/html` | Morph patched elements into the DOM (by matching `id`s by default). | `datastar-selector`, `datastar-mode` (`outer|inner|replace|prepend|append|before|after|remove`), `datastar-use-view-transition` |
| `application/json` | Merge Patch into signals (set values to `null` to delete). | `datastar-only-if-missing: true` |
| `text/event-stream` | Stream SSE events (`datastar-patch-elements`, `datastar-patch-signals`). | (SSE framing; see `prototypes/salary-book-react/docs/bun-sse.md`) |
| `text/javascript` | Execute returned script (use sparingly). | `datastar-script-attributes` |

If one interaction updates a single region, `text/html` is usually simplest.
For **multi-region/disjoint updates** (or ordered patch sequences), prefer a short-lived `text/event-stream` response that emits multiple patch events, then closes.
Use long-lived SSE streams for feeds/progress/live data.

---

## 5) Durable vs ephemeral signals (and how to avoid fetch spaghetti)

### 5.1 Centralize server refresh on signal changes

Instead of repeating `@get('/sse/...')` everywhere, you can:

1) Make event handlers only update signals.
2) Put the fetch trigger on a single root element using `data-on-signal-patch`.
3) Use `data-on-signal-patch-filter` to include only the “server-authoritative” signals.

Example pattern (conceptual):

- Filter signals (should trigger server refresh): `team`, `start`, `end`
- UI-only signals (should NOT trigger refresh): `player` (selected row), `hovered`, `_dialog`

This yields a very clean mental model:
- User interactions mutate signals.
- *Some* signals trigger server refresh.
- Everything else stays browser-only.

### 5.2 Datastar sends signals on every request

By default, every non-underscore signal is sent automatically:

- `@get()` → query param: `?datastar=<json>`
- other verbs → JSON body: `{ datastar: ... }`

If your payload gets big or contains junk, use `filterSignals` on the request options.

### 5.3 Cancellation

Default behavior cancels an in-flight request when a new one starts **on the same element**.

If multiple elements should share cancellation, coordinate via an `AbortController` stored in a signal (typically local).

---

## 6) Custom event bus pattern (high leverage)

Use bubbling `CustomEvent`s when multiple UI sections need to trigger the same update.

Good for:
- Table row click / chart point click / sidebar click should all select the same `$player`

Pattern:
- Dispatch: `el.dispatchEvent(new CustomEvent('draft-interaction', { detail: {...}, bubbles: true }))`
- Handle at the root: `signals.events` (or a single `data-on:*` handler) updates signals.

Useful conventions:
- Put payload in `evt.detail`.
- Consider `{ commit: boolean }` to distinguish preview/hover vs commit.
- Prefer kebab-case event names (`draft-interaction`). If needed, use Datastar’s event-name casing modifiers (e.g. `__case.kebab`).
- Document event names + schemas next to the root handler.

---

## 7) TSX / templating tips (if you generate markup programmatically)

- Prefer value syntax for dynamic signal names:
  - `data-bind="search"` (or `data-bind={searchSignal}` in TSX)
  - `data-ref="_dialog"`
- In TSX/JSX, attribute names that include dots (modifiers) often require a spread:

```tsx
<wa-input {...{ "data-on:input__debounce.120ms": "@get('/sse', { openWhenHidden: true })" }} />
```

- Datastar “owns” the bindings it manages — avoid competing sources of truth:
  - Don’t set literal `value="..."` when using `data-bind` or `data-attr:value`.
  - Avoid shipping fallback inline styles like `style="display:none"` when `data-show` controls visibility.
    - Prefer computing the right initial state on the server / via signal defaults to prevent flashes.
  - `data-text` elements should be empty in server markup (don’t mix literal text nodes + `data-text`).

---

## 8) SSE hygiene (production-ish defaults)

- Send `retry: <ms>` at stream start.
- Send keepalive comments (e.g. `: keepalive <ts>`) ~every 15s.
- Stop work when the request `AbortSignal` is aborted.
- For dashboards/streams: `openWhenHidden: true`.

This repo already has framing examples in: `prototypes/salary-book-react/docs/bun-sse.md`.

---

## 9) Backend parsing: read Datastar payload defensively

In practice, you’ll see multiple payload shapes. Parse robustly:

```ts
function parseDatastarPayload(query: Record<string, string | undefined>) {
  const raw = query.datastar;
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;

    const candidate = parsed as Record<string, unknown>;
    // Some clients wrap as { signals: {...} }
    if (candidate.signals && typeof candidate.signals === 'object') {
      return candidate.signals as Record<string, unknown>;
    }
    return candidate;
  } catch {
    return null;
  }
}
```

Progressive enhancement trick:
- Parse explicit query params first (shareable URLs, works without JS).
- Fall back to Datastar signals if query params aren’t present.

---

## 10) Debugging + safety

- `data-json-signals` is the fastest “what is my state?” tool.
- Datastar Inspector (Pro) can monitor SSE events and patches.
- Use local debug signals like `__meta` to annotate streams.

Security:
- Signals are visible and user-mutable. **Never** put secrets in signals.
- Treat all signal values as untrusted input.
- Datastar uses the `Function` constructor; CSPs must allow `'unsafe-eval'`.
