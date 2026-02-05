# Spec 03 — Trade Machine (within Salary Book interaction model)

> Goal: a trade planning surface that matches the UI’s philosophy:
> dense, constraint-first, minimal navigation depth, DB-driven math.

---

## 0) Why this belongs in this repo

This repo’s “product” is Postgres warehouses + trade math primitives (e.g., TPE matching, apron post-trade projections).

The web app should expose that power without re-implementing rules in Ruby/JS.

---

## 1) Core thesis

A trade machine should be:

- **constraint-first** (what blocks the deal is as important as totals)
- **team-aware** (per-team legality simultaneously)
- **shallow navigation** (no multi-step wizards)
- **integrated with the Salary Book** (the cap sheet is the context)

---

## 2) Where the Trade Machine lives (interaction model)

### Option A (recommended): Trade is a sidebar overlay entity

- Add a top-bar button: `Trade`
- Clicking `Trade` pushes a `TRADE` overlay in the sidebar (like PLAYER/PICK).
- Main canvas remains the Salary Book; user keeps scroll context.

Benefits:
- Matches the 2-level sidebar state machine.
- Avoids “new page” navigation.

### Trade overlay behavior

- Overlay is persistent during scrolling.
- Clicking entities while Trade overlay is open should **not** replace it by default.
  - Instead, entities can be “added to trade” when in trade mode (see Inputs).
- Back exits Trade overlay and returns to team context.

---

## 3) Inputs (how users build a trade)

### 3.1 Team selection

Trade needs explicit team legs.

- Primary team defaults to the **active scroll-spy team**.
- Additional teams can be added via:
  - a `+ Team` control in the trade overlay
  - or clicking a team in the top grid while in trade mode (adds as participant, doesn’t scroll)

### 3.2 Adding outgoing / incoming players

When Trade overlay is open:

- Clicking a player row toggles that player in the trade builder for the active team:
  - `Outgoing` if player belongs to that team
  - `Incoming` if player belongs to another participant team

Alternative UX (explicit):
- Small `+` affordance on hover to “Add to trade” so normal click still opens player overlay.

### 3.3 Adding picks and cash

- Picks: click pick pill → `Add to trade` button within pick overlay (or inline `+` on pill hover)
- Cash: numeric input per team: `Cash Sent` / `Cash Received`
  - must support “potential cash” via draft-pick cash fallback (Ops examples)

### 3.4 Selecting the cap year / evaluation moment

Trade legality depends on timing and year.

In v1, require a single selection:

- `Salary Cap Year` (default current)
- `Moment`: `In-season` vs `Post-season` (needed for some apron gating nuances)

---

## 4) Outputs (what the trade machine must show)

### 4.1 Per-team salary matching result

For each team:

- Outgoing aggregate (post-assignment relevant salary)
- Incoming aggregate
- **Best legal pathway** (Standard / Aggregated / Expanded / Room)
- `Max Incoming` under that pathway
- Pass/fail

Also show a short “why” when failing:
- allowance reduced to $0 due to first apron
- pathway gated by second apron
- aggregation restriction triggered

These reasons should come from DB functions returning structured results.

### 4.2 Apron / threshold impact projection

For each team:

- Pre-trade: team salary, tax/apron rooms
- Post-trade: projected apron team salary + rooms
- Whether the trade would trigger or violate apron restrictions

### 4.3 Ops Manual trade-structure validation

Separate from CBA matching:

- Minimum consideration (all trades)
- Additional required consideration (3+ teams)

Return a checklist-style result:
- per team: assigns and receives qualifying consideration
- for 3+ teams: touches 2+ other teams with qualifying additional consideration

### 4.4 Cash transfer accounting warnings

From Ops examples:

- Any cash that *is or could be transferred* counts now.
- Cash fallback attached to picks must be treated as cash on trade date.

Trade output should display:
- `Cash limit remaining this cap year` (if modeled)
- `This trade consumes $X of cash limit immediately`
- `This trade triggers apron restrictions via cash sending`

---

## 5) Data contracts / DB primitives (do not implement math in Ruby/JS)

### 5.1 Existing primitives (in this repo)

This repo already contains trade math functions/views (e.g. TPE math and planners). The web UI should call them via API endpoints.

### 5.2 Proposed function/API shapes

**A) Evaluate trade (single call)**

Input:
- teams involved
- outgoing/incoming player ids per team
- picks ids per team (optional)
- cash per team (optional)
- salary_cap_year
- moment (in-season/post-season)

Output:
- per-team salary matching evaluation:
  - pathway chosen
  - max incoming
  - pass/fail
  - blocking reasons (typed)
- per-team apron projection:
  - post-trade apron team salary
  - hard-cap gating flags
- ops consideration checklist results

**B) Optional: trade plan helper**

If using planner functions:
- return suggested allocation of incoming salary into existing TPEs (expiry-first, best-fit)

### 5.3 Typed “reason codes”

Avoid prose. Return typed flags so UI can render consistently:

- `ALLOWANCE_ZERO_FIRST_APRON`
- `PATH_GATED_FIRST_APRON`
- `PATH_GATED_SECOND_APRON`
- `AGGREGATION_RECENTLY_ACQUIRED_RESTRICTION`
- `AGGREGATION_MINIMUM_TRADED_PLAYER_LIMIT`
- `OPS_MINIMUM_CONSIDERATION_FAIL`
- `OPS_ADDITIONAL_CONSIDERATION_FAIL`
- `OPS_CASH_LIMIT_EXCEEDED`

---

## 6) UI rendering (how to show results in a dense tool)

### 6.1 Trade overlay top summary (always visible)

- Teams involved (chips)
- Cap year / moment selector
- Overall status: `LEGAL` / `ILLEGAL` with count of failing teams

### 6.2 Per-team result rows

Render one compact row per team:

- Team code
- Out / In totals
- Max incoming
- Pathway chip
- Pass/fail icon

Clicking a team row expands that team’s “why” reasons.

### 6.3 Constraint-first expansion

When expanded, show:

- Salary matching reasons (ordered by precedence)
- Apron restriction flags
- Ops checklist failures
- Cash accounting notes

No prose blocks; just structured outputs.

---

## 7) Sequencing / phased build

### Phase 1 (MVP)
- 2-team trades
- Players only (no picks/cash)
- Per-team matching + apron projection

### Phase 2
- Add picks + cash
- Add ops consideration checks

### Phase 3
- Multi-team trades + planner suggestions

---

## 8) Cross-references (rules provenance)

- CBA: traded player exception types, $250k allowance behavior, apron transaction gating
- Ops: minimum consideration + 3+ team additional consideration
- Ops: cash fallback treated as cash now; persists through subsequent trades
