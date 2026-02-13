# Datastar morph-by-id patch sets (`text/html`)

Datastar can patch multiple DOM regions **without SSE** by returning a `text/html` response that contains **multiple top-level elements** with stable `id`s.

This is easy to miss if you assume you must return a full page or that Datastar works like htmx OOB swaps.

---

## Core rule (the thing people get wrong)

When a Datastar backend action (`@get()`, `@post()`, etc.) receives a response with:

- `Content-Type: text/html`

Datastar:

1. Parses the response HTML.
2. Takes the **top-level elements** in the response (the direct children of the parsed document/fragment).
3. For each top-level element that has an `id`, it **morphs** it into the existing DOM element with the same `id`.

### Implications

- You **do not** need to return an entire page.
- You **can** return a fragment that contains only the patch targets.
- Only the `id`s you include in the response will be touched.

---

## Top-level means *top-level*

This works:

```html
<div id="maincanvas">...</div>
<div id="rightpanel-base">...</div>
```

This does **not** (because `#rightpanel-base` is not top-level):

```html
<div>
  <div id="rightpanel-base">...</div>
</div>
```

If you need wrappers for layout in ERB, put them **inside** the patch root, not around it.

---

## The target must already exist in the DOM

For morph-by-id to work, the current page must already contain the patch target:

```html
<div id="rightpanel-base"></div>
```

If it doesn’t exist, there is nothing to morph into.

(Our repo leans on this by maintaining stable placeholders like `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#flash`.)

---

## How this differs from “return the whole page”

Datastar *can* morph very large HTML chunks (even full documents), but that’s optional.

In practice:

- Returning a whole page increases incidental churn (more markup to diff, more chances to accidentally re-trigger `data-init`, etc.).
- Returning only the patch set (a few section roots) is usually easier to reason about and review.

You still get the main benefit: **morphing** preserves DOM state inside unchanged subtrees where possible.

---

## How this differs from htmx OOB

This is similar in spirit to htmx “out-of-band” updates (multiple disjoint regions in one response), but the key behavioral difference is:

- Datastar’s `text/html` morph-by-id patches **top-level elements**.
- It is *not* “scan the entire response for any element with an `id` and patch it wherever it appears.”

If you want explicit selectors / patch modes, use SSE (`datastar-patch-elements`) or Datastar’s patch headers.

---

## Rails sketch: one request, multiple region updates (no SSE)

Controller:

```rb
# GET /tools/salary-book/patch?team=BOS&year=2025

def patch
  main_html = render_to_string(partial: "tools/salary_book/maincanvas_team_frame", locals: { ... })
  sidebar_html = render_to_string(partial: "tools/salary_book/sidebar_team", locals: { ... })

  # IMPORTANT: concatenate the *top-level* patch roots.
  # Each partial must render a top-level element whose id matches the existing DOM.
  html = [main_html, sidebar_html].join("\n")

  render html: html.html_safe, layout: false, content_type: "text/html"
end
```

Each partial should render its own patch root, e.g.:

```erb
<div id="salarybook-team-frame"> ... </div>
```

```erb
<div id="rightpanel-base"> ... </div>
```

---

## When `text/html` morph-by-id is a good choice

Use this when:

- you’re patching **elements only** (no signal patch required)
- you want an **atomic** multi-region update in one request
- ordering doesn’t matter beyond “both regions update together”
- you want to avoid `ActionController::Live` complexity

Entity workspace bootstrap in this repo is the canonical example: concatenate multiple section partials and return one `text/html` response.

---

## When SSE is still the right tool

Prefer `text/event-stream` when you need:

- `datastar-patch-signals` (patching signals alongside elements)
- explicit patch modes (`append`, `remove`, etc.) and/or explicit selectors
- ordered “step 1 then step 2” patch semantics
- progressive streaming or long-lived connections

Repo note: `web/AGENTS.md` currently chooses SSE for multi-region updates as a strict convention (it’s a good guardrail), even though Datastar can do multi-region patch sets via `text/html`.
