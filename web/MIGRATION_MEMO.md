# Rails + Datastar rewrite plan for `web/` (Salary Book)

This doc is a **migration memo**, not an implementation checklist.

Goal: capture the mental models + key steps for turning the current **Bun + React** Salary Book into a **Rails + Datastar** app while preserving the core UX invariants.

If you’re starting cold, read first:

- `web/specs/00-ui-philosophy.md` (invariants)
- `web/specs/01-salary-book.md` (full interaction model)
- `web/AGENTS.md` (current folder map + conventions)
- `prototypes/salary-book-react/HANDOFF.md` (React prototype file map)
- Datastar conventions: `reference/datastar/insights.md`, `reference/datastar/rails.md`, `reference/datastar/basecamp.md`

---

## 0) What exists today (so we don’t lose the plot)

### Architecture

```
Postgres (pcms.* warehouses + fn_*)
  -> Bun API (/api/salary-book/*)  [prototypes/salary-book-react/src/api/routes/salary-book.ts]
    -> SWR hooks                  [prototypes/salary-book-react/src/features/SalaryBook/hooks/*]
      -> React UI                 [prototypes/salary-book-react/src/features/SalaryBook/components/*]
```

### UX invariants you must preserve

From `web/specs/00-ui-philosophy.md`:

- **Rows are the product**: dense sheet first.
- **Scroll position IS state**: `activeTeam` drives context.
- **Sidebar is intelligence**: base = team context; overlay = entity detail.
- **Navigation is shallow**: one overlay at a time; click replaces; Back returns to current viewport team.
- **Filters are lenses**: they must not change navigation state.

### The irreducible client-side JS

Even with Datastar, this UI is not “no JS”. There are three hard client problems React currently owns:

1) **Scroll spy** (`activeTeam`, fade thresholds, scrollToTeam)
   - `prototypes/salary-book-react/src/features/SalaryBook/shell/useScrollSpy.ts`
2) **Sticky + horizontal scroll sync** (table header + body scrollers)
   - `prototypes/salary-book-react/src/features/SalaryBook/components/MainCanvas/SalaryTable.tsx`
3) **WAAPI transitions** (safe-to-unmount sidebar overlay transitions)
   - `prototypes/salary-book-react/src/lib/animate.ts`
   - `prototypes/salary-book-react/src/features/SalaryBook/shell/useSidebarTransition.ts`

A Rails + Datastar rewrite should treat these as a **small JS runtime** that stays, while React state/data fetching goes away.

---

## 1) The target mental model (Rails + Datastar)

### Basecamp-ish stance

- **Rails renders HTML** as the primary contract.
- **Datastar patches HTML** (and occasionally signals).
- **Signals are for ephemeral UI state**, not business data.

### Replace this…

- SWR hooks + JSON endpoints + component-level fetch

### …with this

- Rails controllers that return:
  - `text/html` fragments with stable IDs (default)
  - `application/json` only for true signal-only updates
  - `text/event-stream` only when streaming is required

### Patch boundaries are everything

Prefer big, stable regions (Datastar “in morph we trust”):

- `#commandbar`
- `#maincanvas`
- `#teamsection-<TEAM>` (per-team boundary)
- `#rightpanel-base`
- `#rightpanel-overlay`
- `#flash`

If a patch boundary is stable, the UI stays sane.

### Rails defaults you should decide on early

- **Turbo/Hotwire:** a new Rails app ships with `turbo-rails` by default.
  - If Datastar is the runtime, either remove Turbo entirely, or keep Turbo *only* for normal page navigation and make sure it doesn’t intercept Datastar backend actions.
- **CSP:** Datastar evaluates expressions using the `Function` constructor.
  - Rails CSP must allow **`'unsafe-eval'`** or Datastar expressions won’t run.
  - See: `reference/datastar/insights.md`.

---

## 2) Proposed Rails page skeleton (single page, server-rendered)

Render a single route initially:

- `GET /tools/salary-book` (tool root)

Layout (mirror `ThreePaneFrame`):

- Fixed header (command bar)
- Main scroll container
- Right panel

Important: keep the IDs stable so Datastar can patch without custom diffing.

Suggested DOM shape:

```html
<body>
  <div id="flash"></div>

  <header id="commandbar">…</header>

  <div id="viewport">
    <main id="maincanvas">…team sections…</main>

    <aside id="rightpanel">
      <div id="rightpanel-base">…team context or system values…</div>
      <div id="rightpanel-overlay"></div>
    </aside>
  </div>
</body>
```

Port the styling primitives from `prototypes/salary-book-react/src/index.html`:

- the CSS variables (`--background`, `--border`, …)
- the `[data-faded] [data-header-content]` fade rule
- any dialog/sheet animation CSS you still want

(You can keep Tailwind initially via CDN like the prototype, then later move to `tailwindcss-rails`.)

---

## 3) Signals: the minimum viable signal map

Keep the repo’s Datastar conventions:

- **flatcase** for global signal keys
- `_` prefix for local-only (DOM refs, big objects, abort controllers)

Suggested starting signals:

### “App chrome” signals

- `sidebarview`: `teamview | systemvalues`
- `overlaytype`: `player | agent | pick | trade | buyout | none`
- `overlayid`: string/number payload (playerId, agentId, etc.)

### Filters (lenses)

Mirror `prototypes/salary-book-react/src/state/filters/types.ts`:

- `displaycapholds`
- `displayexceptions`
- `displaydraftpicks`
- `displaydeadmoney`
- `financialstaxaprons`
- `financialscashvscap`
- `financialsluxurytax`
- `contractsoptions`
- `contractsincentives`
- `contractstwoway`

### Scroll context (local; driven by JS)

- `activeteam` (global is OK; it’s not secret, and it’s useful to send to server)
- `_scrollstate` (local; `idle|scrolling|settling`)

If you later need trade/buyout state, add signals intentionally (don’t dump giant objects by default).

---

## 4) How to replace SWR hooks (data fetching strategy)

### Key shift

React/SWR fetches lots of small JSON payloads.

Rails should instead:

- render **server-side** for the initial view
- return **HTML fragments** for updates
- query Postgres directly (no Bun API in the end state)

### Source of truth stays Postgres

Keep the existing “Postgres is the product” posture (from `web/AGENTS.md`).

Do not re-implement cap/trade rules in Ruby.

Instead, call the same primitives the Bun API calls today:

- `pcms.salary_book_warehouse`
- `pcms.team_salary_warehouse`
- `pcms.draft_pick_summary_assets`
- `pcms.*_warehouse` for holds/exceptions/dead money/rights
- `pcms.fn_tpe_trade_math`, `pcms.fn_trade_salary_range`, `pcms.fn_buyout_scenario`, …

### Porting trick

Use `prototypes/salary-book-react/src/api/routes/salary-book.ts` as the authoritative list of:

- query shapes
- normalization expectations
- weird edge cases (missing `public.nba_players`, etc.)

Port the SQL first; then port the UI.

---

## 5) Route design (HTML-first endpoints)

Think in **UI regions**, not “REST JSON resources”.

### Team sections

- `GET /tools/salary-book/teams/:teamcode/section`
  - returns `<section id="teamsection-BOS">…</section>`

### Right panel base

- `GET /tools/salary-book/sidebar/team?team=BOS&tab=cap`
  - returns `<div id="rightpanel-base">…</div>`

### Right panel overlay entities

- `GET /tools/salary-book/sidebar/player/:id`
- `GET /tools/salary-book/sidebar/agent/:id`
- `GET /tools/salary-book/sidebar/pick?team=BOS&year=2028&round=1`
- `GET /tools/salary-book/sidebar/trade`
- `GET /tools/salary-book/sidebar/buyout`

Each returns `<div id="rightpanel-overlay">…</div>`.

### Computation endpoints (still HTML)

- `POST /tools/salary-book/trade/evaluate` → patch just the “results” module inside the trade overlay
- `POST /tools/salary-book/buyout/scenario` → patch results module
- `POST /tools/salary-book/buyout/setoff` → patch setoff module

(These can return HTML or JSON merge-patch signals; default to HTML unless you have a strong reason.)

---

## 6) Hooking the client runtime into Datastar (the important glue)

### 6.1 Scroll spy → Datastar

You will still run a JS scroll spy (the current `useScrollSpy` logic, rewritten without React).

Instead of setting React state, it should:

- set `data-faded` attributes on sections (same as today)
- dispatch a bubbling `CustomEvent` when the active team changes

Example event payload:

- event name: `salarybook-activeteam`
- detail: `{ team: 'BOS' }`

Then Datastar can listen:

```html
<div
  id="rightpanel"
  data-on:salarybook-activeteam="$activeteam = evt.detail.team"
  data-on-signal-patch="@get('/tools/salary-book/sidebar/team?team=' + $activeteam)"
  data-on-signal-patch-filter="{ include: /^activeteam$/ }"
></div>
```

This matches the “custom event bus” pattern in `reference/datastar/insights.md`.

### 6.2 Registering team sections after morph

When a team section is patched in, the scroll spy must register its element.

Simplest: put a `data-init` on the section root:

```html
<section
  id="teamsection-BOS"
  data-team="BOS"
  data-init="window.salaryBook.registerSection('BOS', el)"
>
```

Datastar will run `data-init` whenever that element is created/patched.

### 6.3 Horizontal scroll sync

Same idea: keep a tiny JS helper and call it from `data-init` inside each section.

Key rule: helpers must be **idempotent** (don’t double-bind listeners on morph).

---

## 7) Filters: prefer client-only show/hide first

A big migration risk is filter toggles triggering large server patches that:

- change heights
- cause scroll jumps
- force scroll restoration hacks

So the recommended order is:

1) Implement filters as **signals only**.
2) Render all optional sections (holds/exceptions/dead money/picks) but hide them with `data-show`.
3) Only later, optimize by lazy-loading optional sections when their filter flips on.

Example:

```html
<label>
  <input type="checkbox" data-bind="displaycapholds">
  Cap Holds
</label>

<div id="teamsection-BOS-capholds" data-show="$displaycapholds">
  …cap holds rows…
</div>
```

This preserves the “filters are lenses” invariant and reduces server traffic.

---

## 8) Sidebar overlay: URLs + progressive enhancement

Don’t make overlays “JS-only”. Give each entity a real URL.

Example pattern for a player row:

```html
<a
  href="/players/123"
  data-on:click__prevent="@get('/tools/salary-book/sidebar/player/123')"
>
  …row…
</a>
```

- With JS: patches `#rightpanel-overlay`.
- Without JS / new tab: loads the canonical page.

This is the most Basecamp-compatible posture.

---

## 9) Animations: reintroduce later, keep the contract simple

Datastar makes DOM updates easy; it does not automatically solve:

- safe-to-unmount exit animations
- crossfades between overlay entities

Recommendation:

- Phase 1: no fancy overlay transitions; just patch content.
- Phase 2: add a small JS “overlay transition manager” that:
  - animates the overlay container in/out
  - prevents morphing conflicts by keeping the patch boundary stable

Use the existing WAAPI helpers as reference:

- `prototypes/salary-book-react/src/lib/animate.ts`
- `prototypes/salary-book-react/src/features/SalaryBook/shell/useSidebarTransition.ts`

---

## 10) Suggested migration phases (pragmatic)

### Phase A — Rails skeleton + styling

- Create Rails app (scaffolded in-place in `web/`; Rails 8.1.2).
- Wire Postgres connection (`POSTGRES_URL`).
- Add Tailwind (CDN first ok; `tailwindcss-rails` later).
- Include Datastar script.
- Render the **three-pane layout** with empty placeholders and stable IDs.

### Phase B — Render one team section server-side

- Hardcode one team (e.g. BOS) to prove the render path.
- Port SQL for:
  - players
  - team salary
  - picks
- Render the section HTML.

### Phase C — Render all teams (or progressive load)

Choose one:

- **Simple:** render all 30 team sections on first paint (compressed HTML).
- **Better:** render placeholders and use Datastar + IntersectionObserver to patch sections as needed.

### Phase D — Right panel base (team context)

- Implement `/tools/salary-book/sidebar/team` returning `#rightpanel-base`.
- Hook scroll spy → `activeteam` signal → patch team context.

### Phase E — Entity overlays

- Player overlay
- Agent overlay
- Pick overlay
- System values base view

### Phase F — Trade + Buyout modes

- Trade overlay: signals for selected teams/players; POST evaluate → patch results.
- Buyout overlay: form signals; POST scenario → patch results.

### Phase G — Performance + caching

- Add fragment caching per-team section keyed by `pcms.team_salary_warehouse.refreshed_at`.
- Consider memoizing common lookups (teams, system values).
- Keep patches large and stable (don’t micro-diff).

---

## 11) “Done” criteria (how you know the rewrite is real)

- The Salary Book is fully usable with:
  - scroll-driven active team
  - filter lenses
  - right panel base (team context) + overlay entities
  - trade + buyout overlays

- Data parity with Sean worksheet evidence (`reference/warehouse/`) surfaces.

- No cap/trade logic duplicated in Ruby.

- The React app can be archived as a reference implementation.

---

## Appendix: File map (React → Rails partials)

Use these as *visual reference* when porting markup:

- Team section wrapper: `prototypes/salary-book-react/src/features/SalaryBook/components/MainCanvas/TeamSection.tsx`
- Sticky header/table: `prototypes/salary-book-react/src/features/SalaryBook/components/MainCanvas/SalaryTable.tsx`
- Player row grammar: `prototypes/salary-book-react/src/features/SalaryBook/components/MainCanvas/PlayerRow.tsx`
- Right panel layering: `prototypes/salary-book-react/src/features/SalaryBook/components/RightPanel/RightPanel.tsx`
- Trade overlay: `prototypes/salary-book-react/src/features/SalaryBook/components/RightPanel/TradeMachineView.tsx`
- Buyout overlay: `prototypes/salary-book-react/src/features/SalaryBook/components/RightPanel/BuyoutCalculatorView.tsx`
- Bun SQL contracts: `prototypes/salary-book-react/src/api/routes/salary-book.ts`
