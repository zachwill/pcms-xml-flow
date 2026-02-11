# TODO_UI — Combobox-first UI infrastructure (Rails + Datastar + SSE)

> This doc replaces the previous broad UI roadmap.
> 
> Written as a handoff to **future me**: assume context, skip fluff, keep the bar high.

---

## 0) Decision

If we invest deeply in one Base UI-inspired primitive, it should be **Combobox**.

Reason: this is where interaction quality, accessibility, and edge-case handling compound the most:
- keyboard semantics
- focus semantics
- IME/composition behavior
- touch/mouse timing edge cases
- async loading + cancellation + stale-result handling
- server/client state ownership boundaries

A “good enough” combobox is easy. A **correct** combobox is rare. We want correct.

---

## 1) Ground rules (must remain true)

Pulled from `web/AGENTS.md` + Datastar docs in this repo.

1. **Server HTML, not JSON UI rendering**
   - search results/options are rendered server-side partials.
2. **One interaction, multi-region updates => one SSE response**
   - no client-side stitching.
3. **Datastar runtime only**
   - no Turbo/Stimulus.
4. **Signals for ephemeral UI state only**
   - underscore prefix for local-only signals.
5. **Dedicated fetch elements to avoid cancellation collisions**
   - Datastar cancellation is per element.
6. **Stable IDs are a contract**
   - especially popup/list/active option regions.

---

## 2) Scope (what this effort is / is not)

### In scope
- A reusable Combobox pattern for `web/` with:
  - local signal state machine
  - server-rendered options
  - optional SSE commit path for multi-region effects
  - keyboard + IME + focus discipline

### Out of scope
- Re-creating Base UI React components inside Rails.
- Building a generic frontend component framework.
- Shipping all variants at once (multi-select chips can come later).

---

## 3) Source references worth re-reading before implementation

### Runtime / architecture
- `web/AGENTS.md`
- `web/docs/datastar_sse_playbook.md`
- `reference/datastar/insights.md`
- `reference/datastar/rails.md`

### Base UI internals (prototype reference only)
- `prototypes/salary-book-react/node_modules/@base-ui/react/combobox/root/AriaCombobox.js`
- `.../combobox/input/ComboboxInput.js`
- `.../combobox/item/ComboboxItem.js`
- `.../combobox/popup/ComboboxPopup.js`

### Prototype wrappers for behavior hints
- `prototypes/salary-book-react/src/components/ui/Combobox.tsx`
- `prototypes/salary-book-react/src/components/ui/DrilldownCombobox.tsx`

---

## 4) System design: ownership boundaries

Treat combobox as three loops:

## A) Input loop (client/local)
- Owns:
  - open/closed
  - raw query string
  - active index
  - loading state
  - composition state (IME)
- Implemented via local signals + tiny JS helper.

## B) Search loop (server HTML patch)
- Owns:
  - option set
  - option labels/metadata
  - disabled states
  - ranking/filter semantics
- Response type usually `text/html`, patching only combobox option region.

## C) Commit loop (selection side effects)
- Owns:
  - authoritative selected entity id
  - downstream region changes
- If one region changes: `text/html`.
- If 2+ regions change: one-off `text/event-stream`.

---

## 5) Signal contract (proposed)

Use per-instance prefixes to avoid collisions.

Example instance prefix: `sbplayercb`

Local-only (underscore):
- `$_sbplayercbopen` (bool)
- `$_sbplayercbquery` (string)
- `$_sbplayercbactiveindex` (int)
- `$_sbplayercbloading` (bool)
- `$_sbplayercbcomposing` (bool)
- `$_sbplayercbrequestseq` (int)
- `$_sbplayercbresultscount` (int)

Global (only if needed server-side):
- `$selectedplayerid` (string/int or empty)

Rules:
- Do **not** store full options arrays in signals.
- Do **not** put heavy object payloads in global signals (they serialize on requests).

---

## 6) DOM + patch contract (per instance)

Each instance should have stable ids:
- `#<id>-root`
- `#<id>-input`
- `#<id>-popup`
- `#<id>-list`
- `#<id>-status` (loading/empty/error text)
- `#<id>-loader` (dedicated request element)

Patch policy:
- Search request patches only `#<id>-popup` or `#<id>-list` + `#<id>-status`.
- Selection may patch unrelated regions through SSE if needed.

---

## 7) Endpoint contract (first pass)

Prefer explicit, boring endpoints over clever shared magic.

### Search endpoint
`GET /tools/salary-book/combobox/players/search`

Query params:
- `team` (optional)
- `q` (query)
- `limit`
- `cursor` (future)

Returns:
- `text/html` with the popup/list subtree (or list + status sections by id)

### Commit endpoint (optional)
`GET /tools/salary-book/combobox/players/select`

Params:
- `player_id`
- contextual params (team/year/tool lens)

Returns:
- one-region: `text/html`
- multi-region: `text/event-stream` using `Datastar` concern helpers

---

## 8) Interaction state machine (minimum required)

States:
- `closed_idle`
- `open_idle`
- `open_loading`
- `open_results`
- `open_empty`
- `open_error`
- `committing`

Transitions:
- Focus input => open
- Input change (non-composing) => loading => results/empty/error
- Arrow keys => move active index
- Enter => commit active option
- Escape => close (and optionally clear query depending on variant)
- Blur/outside press => close with deterministic focus behavior

IME rule:
- while composing (`compositionstart`..`compositionend`), suppress search dispatch and keep list stable.

---

## 9) Keyboard/a11y contract (non-negotiable)

Input/trigger semantics:
- `role="combobox"`
- `aria-expanded`
- `aria-controls=<list-id>`
- `aria-activedescendant=<option-id>` when active option exists
- `aria-autocomplete="list"` (or configured mode)

List semantics:
- `role="listbox"`
- option rows `role="option"`
- `aria-selected` on selected option

Keyboard behavior:
- ArrowDown/ArrowUp: move active option (with bounds)
- Home/End: move cursor in input unless in explicit list-nav mode
- Enter: commit active option; no-op if none active (or close per variant)
- Escape: close popup; second Escape can clear query if configured
- Tab: close and continue focus traversal

Screen reader behavior must be verified with VoiceOver minimum.

---

## 10) Request cancellation + stale response strategy

Key gotcha: Datastar cancellation is per element.

Pattern:
- Use a dedicated hidden loader element (`#<id>-loader`) for search requests.
- Keep commit requests on separate element path when possible.

Stale response guard:
- Increment `$_<id>requestseq` before dispatch.
- Include seq in query.
- Server echoes seq into response markup attribute.
- Apply/morph only when echoed seq matches current seq (or allow latest-wins by endpoint discipline).

Debounce:
- Start at 100–150ms for query input.
- Revisit based on observed DB latency.

---

## 11) Server query + ranking contract

Server must own ranking/filter semantics.

Baseline matching behavior:
1. exact prefix matches
2. token prefix matches
3. infix contains matches
4. deterministic tie-break (name asc or domain-specific relevance)

Must document per endpoint:
- max limit
- sort key
- optional context weighting (active team, current roster, etc.)

Never ship “all options then filter client-side” for large domains.

---

## 12) Error and empty states

Empty state should be explicit in list region:
- “No players found”

Error state should be explicit and non-destructive:
- keep query
- show retry affordance
- preserve keyboard focus in input

Do not silently collapse popup on error.

---

## 13) Styling/density guidance for this repo

Given product posture in `web/AGENTS.md`:
- dense rows over cards
- tabular numbers where applicable
- yellow hover conventions where relevant
- maintain dark mode variants

Combobox option rows should be information-dense and scannable (name + team/meta).

---

## 14) Implementation plan (phased)

## Phase 1 — One concrete production instance
Target: salary-book player search/selection where current Select is limiting.

Deliverables:
- controller endpoint for search (HTML)
- optional commit endpoint (SSE)
- ERB partials for popup/list/row/status
- minimal JS helper in `web/app/javascript/shared/combobox.js`
- one integrated usage in Salary Book view

## Phase 2 — Hardening
- IME validation
- outside-click/focus edge cases
- stale-response guard
- request cancellation verification
- profiling and limit tuning

## Phase 3 — Reuse extraction
- shared partial conventions in `web/app/views/shared/combobox/`
- optional helper module for id/signal naming
- second instance in another tool/entity page

## Phase 4 — Advanced variants (optional)
- grouped results
- inline create flow (Drilldown style)
- multi-select chips variant
- virtualization (only if actually needed)

---

## 15) Testing matrix

### Unit-ish (Ruby/request)
- search endpoint ranking/order
- limit behavior
- empty/error response structure

### Browser integration (manual + script)
- keyboard matrix (Arrow/Enter/Escape/Tab/Home/End)
- IME composition flow
- rapid typing with cancellation
- selection commits with SSE multi-region patch order

### Accessibility
- role/aria attributes present and updated
- active descendant updates correctly
- screen reader announces option changes reasonably

### Regression checks
- no cross-cancellation with unrelated heavy fetches
- no business logic moved into JS
- no Turbo/Stimulus introduced

---

## 16) Definition of done (for v1 combobox)

- Works with keyboard-only navigation.
- Handles IME without flicker/jank.
- Uses server-rendered options (no client template rendering).
- Uses correct response type by patch count (HTML vs SSE).
- Avoids request cancellation collisions via dedicated loader element.
- Keeps local-only UI state in underscore signals.
- Has documented endpoint + signal + patch contracts.
- Ships with one real Salary Book flow, not a sandbox-only component.

---

## 17) Immediate next actions

1. Pick exact first surface in Salary Book (player picker with highest UX pain).
2. Create endpoint stubs + partial skeletons.
3. Implement local signal/loader wiring and HTML search patching.
4. Add commit path with SSE only if selection updates 2+ regions.
5. Write a short `web/docs/contracts/combobox_player_search.md` after implementation.

---

## 18) Final note to future me

Don’t chase “component abstraction elegance” first.

Ship one **behaviorally correct** combobox in the real app, prove the contract,
then extract shared structure.

The value is not visual chrome — it’s trust in interaction correctness under real usage.
