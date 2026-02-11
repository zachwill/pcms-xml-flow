# Salary Book "Apps Can Take Over" Refactor Audit

**Scope:** `web/` (Rails + Datastar implementation)

**Status:** Audit/planning only (no implementation in this doc)

---

## Goal

Support a Salary Book command bar where some filters are actually **Apps** that can:

1. take over `#maincanvas`
2. take over sidebar base (`#rightpanel-base`) and optionally overlay behavior
3. replace app-specific knobs/filters
4. optionally disable or ignore team buttons

This doc captures what is currently coupled and what likely needs to change.

---

## Executive summary

This is feasible without a full rewrite, but there is one major assumption to unwind:

- Salary Book is currently hardwired as a **single app mode** ("Salaries") across controller, SSE, view composition, and URL state.

So this is a **moderate refactor** of orchestration/state/partials, not a DB math rewrite.

---

## What is currently coupled (and why it matters)

## 1) App selector is placeholder-only today

- File: `web/app/views/tools/salary_book/show.html.erb`
- "Apps" radios exist (`Injuries`, `Salaries`, `Tankathon`), but only Salaries is active.
- No `activeapp` signal and no `app` server param are wired.

**Impact:** UI suggests multi-app, runtime is single-app.

---

## 2) Team switching SSE is salary-specific

- Team buttons always call:
  - `/tools/salary-book/sse/switch-team?team=...&year=...`
- File: `web/app/controllers/tools/salary_book_sse_controller.rb`
  - `switch_team` always renders:
    - `tools/salary_book/maincanvas_team_frame`
    - `tools/salary_book/sidebar_team`

**Impact:** if another app owns main/sidebar, current switch endpoint is wrong by design.

---

## 3) Initial load always preloads salary payload

- File: `web/app/controllers/tools/salary_book_controller.rb#show`
- Always fetches players + cap holds + exceptions + dead money + picks + team summaries.

**Impact:** non-salary app modes would over-fetch and over-render salary data.

---

## 4) Command bar knobs are salary-specific + inline

- File: `web/app/views/tools/salary_book/show.html.erb`
- Current filter/knob groups are all salary-lens controls.

**Impact:** app-specific controls cannot cleanly swap in/out yet.

---

## 5) URL state only tracks `team` + `year`

- Team click updates URL with `?team=...&year=...`.
- No `app` in URL.

**Impact:** app selection cannot be deep-linked/restored, and history can drift.

---

## 6) Hidden sidebar loader assumes salary cap-tab workflow

- File: `web/app/views/tools/salary_book/show.html.erb`
- `#salarybook-sidebar-loader` auto-fetches `/sidebar/team/cap` based on `selectedseason`.

**Impact:** this background behavior should only run for salary app.

---

## 7) Some signals are dead or partially wired

Defined in root `data-signals`, but not functionally used end-to-end:

- `sidebarview`
- `overlaytype`
- `overlayid`
- `displaycashvscap`
- `displayctg`

**Impact:** signal namespace is already crowded; app-state additions should clean this up, not add more drift.

---

## 8) Commandbar JS rebinding risk after morphs

- File: `web/app/javascript/shared/commandbar_navigation.js`
- Initializes on `DOMContentLoaded`/`pageshow`, not explicitly on Datastar morphs.

**Impact:** if app switches patch `#commandbar`, listeners can go stale unless re-init/delegation strategy is added.

---

## Recommended target architecture

## A) Treat App selection as navigation-level state

Per current interaction guidance, if app switch changes main surface/sidebar ownership, this is not a simple display lens.

Use explicit app state:

- URL: `?app=salaries|injuries|tankathon` (or equivalent keys)
- Datastar signal: `activeapp`
- Server: `params[:app]` normalized/canonicalized

---

## B) Add an app registry (single source of truth)

Create a server-side registry describing per-app capabilities, e.g.:

- supports team buttons?
- supports team switch SSE?
- commandbar controls partial
- main canvas partial
- sidebar base partial
- should overlay be preserved/cleared on app switch?

This avoids hardcoded `if app == ...` branching scattered across views/controllers.

---

## C) Keep canonical patch boundaries stable

Continue to patch by existing IDs:

- `#commandbar`
- `#maincanvas`
- `#rightpanel-base`
- `#rightpanel-overlay`
- `#flash`

If app switch updates 2+ regions, return one SSE response with ordered patches.

---

## D) Separate app switch from team switch

- **Team switch** should be valid only when active app supports it.
- **App switch** should have a dedicated path/handler that can patch commandbar + main + sidebar in one response.

Possible approach:

- Keep `/sse/switch-team` for team-aware apps (initially Salaries only)
- Add `/sse/switch-app` for app transitions

---

## E) Gate salary-only side effects

Salary-only behavior should run only when `activeapp === 'salaries'`:

- sidebar cap-year loader (`#salarybook-sidebar-loader`)
- salary-specific knobs
- salary-specific SSE fetches
- season hover/lock flows if they are irrelevant in non-salary apps

---

## F) Team buttons: disable policy should be app-driven

For apps that do not use team context:

- render disabled visual state and `aria-disabled="true"`
- avoid firing team switch requests
- optionally preserve selected team in state (for returning to Salaries)

---

## G) URL and history policy

On app switch, preserve relevant params when possible:

- always keep `app`
- keep `team` only if app uses team context
- keep `year` if app uses salary-year concept

Avoid `replaceState` calls that drop unknown params.

---

## Likely file change map

## Existing files likely to change

- `web/app/views/tools/salary_book/show.html.erb`
  - introduce app-aware command bar/main/sidebar composition
  - add `activeapp` signal
  - gate salary-only loader/effects
- `web/app/controllers/tools/salary_book_controller.rb`
  - parse/normalize `app`
  - branch initial payload strategy by app
- `web/app/controllers/tools/salary_book_sse_controller.rb`
  - add app-switch SSE endpoint and/or make `switch_team` app-aware
- `web/config/routes.rb`
  - route(s) for app-switch interactions
- `web/app/javascript/shared/commandbar_navigation.js`
  - ensure rebinding/delegation works after commandbar morphs

## New partials recommended

Under `web/app/views/tools/salary_book/`, likely split into app-specific slices:

- commandbar app controls partial(s)
- maincanvas app partial(s)
- sidebar base app partial(s)

---

## Suggested rollout plan (low-risk sequencing)

## Phase 1 — Introduce app state with no behavioral change

- Add normalized `app` param + `activeapp` signal
- Default to `salaries`
- Keep current rendering behavior unchanged

## Phase 2 — Partialize commandbar and gate salary-only controls

- Move salary filters into salary-only partial
- Keep team grid common (for now), with app-aware disabled policy hooks

## Phase 3 — Add app-switch SSE orchestration

- Add dedicated app-switch action returning ordered multi-region patches
- Patch at least: `#commandbar`, `#maincanvas`, `#rightpanel-base`
- Decide and enforce overlay policy on app switch (clear vs preserve)

## Phase 4 — Make team switch app-aware

- If app supports team context, allow team switch
- If not, no-op/disabled
- Ensure URL sync and history are consistent

## Phase 5 — Land first non-salary app mode

- Implement one real app takeover path (e.g., Injuries placeholder with full-shell ownership)
- Validate orchestration before adding more apps

---

## Risk areas and mitigations

## Risk: stale cross-app signal state

**Mitigation:** explicit reset map on app switch (what signals persist vs reset).

## Risk: request cancellation interactions

Datastar cancellation is per-element; cross-element requests can still overlap in surprising ways.

**Mitigation:** keep heavy interactions on dedicated elements and avoid simultaneous conflicting fetches.

## Risk: commandbar listeners lost after morph

**Mitigation:** idempotent init + explicit re-init after commandbar patch, or event delegation.

## Risk: overlay/base inconsistency during app switches

**Mitigation:** define a strict rule:
- either always clear `#rightpanel-overlay` on app switch,
- or preserve only when app family is compatible.

## Risk: URL/history drift

**Mitigation:** centralized URL builder that merges params and enforces canonical app/team/year policy.

---

## Acceptance criteria for refactor completion

1. App switch can replace commandbar controls + main canvas + sidebar base in one interaction.
2. Team buttons can be app-disabled cleanly (visual + behavioral + accessibility).
3. Salary-only background loaders never fire in non-salary apps.
4. URL deep-links restore correct app context.
5. Switching app/team never leaves stale overlay/base mismatch.
6. Existing Salaries behavior remains unchanged when `app=salaries`.

---

## Open product decisions (needed before implementation)

1. **Overlay policy on app switch:** always clear or conditionally preserve?
2. **Team context persistence:** when app disables teams, do we still remember last active team?
3. **URL semantics:** required params per app (`team`, `year`, etc.)?
4. **App taxonomy:** are Apps first-class navigation destinations or commandbar-local modes?

---

## Net assessment

- **Effort:** Medium
- **Risk:** Medium (state orchestration and patch sequencing), low SQL risk
- **Main refactor theme:** convert single-mode Salary Book shell into app-aware shell orchestration while preserving existing Datastar patch boundaries.
