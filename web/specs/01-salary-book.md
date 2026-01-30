# NBA Salary Book — Interface Specification

> Updated Jan 2026 to reflect actual implementation state.

## Core Thesis

A scroll-driven front-office tool where **scroll position drives context**. The main view is a continuous scroll of team salary tables; a contextual sidebar responds to both viewport position and explicit entity selection.

### Three Pillars

1. **Rows are the product** — The salary table is the primary surface: dense, scannable, spreadsheet-like with thoughtful UX affordances (sticky headers, grouping, badges, tooltips)
2. **Context follows the user** — The system always knows which team you're "in" based on scroll position; the sidebar reflects this automatically
3. **Navigation is intentionally shallow** — Clicking entities swaps the detail view; Back returns to team context in one step

### The Job To Be Done

Enable a front office user to **scan multi-team cap sheets quickly**, then **drill into any entity** (player/agent/pick/team) without losing their place.

---

## Architecture

### Data Flow

```
PostgreSQL (pcms.* warehouses)
        │
        ▼
   Bun API routes (/api/salary-book/*)
        │
        ▼
   SWR hooks (cached, deduped)
        │
        ▼
   React components
```

The web app is a **thin consumer** of Postgres warehouse tables. API routes map nearly 1:1 to database queries. The real logic lives in SQL (migrations, refresh functions, warehouse tables).

### Key Hooks

| Hook | Purpose | Cache Strategy |
|------|---------|----------------|
| `useTeams` | All NBA teams | Global, revalidate on focus |
| `usePlayers(teamCode)` | Players for a team | Per-team cache |
| `useTeamSalary(teamCode)` | Team totals by year | Per-team cache |
| `usePicks(teamCode)` | Draft picks | Per-team cache |
| `useCapHolds(teamCode)` | Cap holds | Per-team cache |
| `useExceptions(teamCode)` | Trade/salary exceptions | Per-team cache |
| `useDeadMoney(teamCode)` | Waiver/dead money | Per-team cache |
| `usePlayer(playerId)` | Single player detail | Per-player cache |
| `useAgent(agentId)` | Agent + clients | Per-agent cache |
| `usePickDetail(params)` | Single pick detail | Per-pick cache |

All hooks use SWR with global config: `revalidateOnFocus: false`, `dedupingInterval: 5000`.

---

## Layout Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       TOP COMMAND BAR (Fixed, ~130px)                   │
│  ┌───────────────────────────────┐  ┌─────────────────────────────────┐ │
│  │   Team Selector Grid          │  │   Filter Toggles                │ │
│  │   (Nav + Scroll-spy status)   │  │   (Display / Financials / etc)  │ │
│  └───────────────────────────────┘  └─────────────────────────────────┘ │
├─────────────────────────────────────────────┬───────────────────────────┤
│                                             │                           │
│      MAIN CANVAS (~70%)                     │    SIDEBAR (~30%)         │
│      Single vertical scroll                 │    Independent scroll     │
│                                             │    min-w-[320px]          │
│                                             │    max-w-[480px]          │
│                                             │                           │
│  ┌───────────────────────────────────────┐  │  ┌─────────────────────┐  │
│  │ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │  │  │                     │  │
│  │ ┃ TEAM HEADER (sticky, with KPIs)   ┃ │  │  │  DEFAULT MODE:      │  │
│  │ ┃ ┌───────────────────────────────┐ ┃ │  │  │  Team context from  │  │
│  │ ┃ │ Table Header (column labels)  │ ┃ │  │  │  scroll position    │  │
│  │ ┃ └───────────────────────────────┘ ┃ │  │  │                     │  │
│  │ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │  │  │  ─────────────────  │  │
│  │   │ Player Row (double-height)    │   │  │  │                     │  │
│  │   │ Player Row                    │   │  │  │  ENTITY MODE:       │  │
│  │   │ ...                           │   │  │  │  Pushed detail view │  │
│  │   │ Cap Holds Section             │   │  │  │  with [Back] button │  │
│  │   │ Exceptions Section            │   │  │  │                     │  │
│  │   │ Dead Money Section            │   │  │  │                     │  │
│  │   │ Draft Assets Row              │   │  │  │                     │  │
│  │   │ Totals Footer                 │   │  │  │                     │  │
│  │   └───────────────────────────────┘   │  │  └─────────────────────┘  │
│  │                                       │  │                           │
│  │  ┌────────────────────────────────┐   │  │                           │
│  │  │ TEAM B HEADER (pushes A off)   │   │  │                           │
│  └──┴────────────────────────────────┴───┘  │                           │
└─────────────────────────────────────────────┴───────────────────────────┘
```

**Key constraint:** One primary vertical scroll for all teams in the main canvas.

---

## 1. Top Command Bar

Fixed position, ~130px height, sits above everything.

### 1.1 Team Selector Grid

**Purpose:** Navigate to teams + see current scroll position at a glance

**Layout:** Two conference blocks (Eastern/Western), teams arranged in a grid, sorted alphabetically within each conference.

**Visual States:**

| State | Visual Treatment | Meaning |
|-------|------------------|---------|
| **Active** | Strong highlight (filled background) | Currently in viewport (scroll-spy) |
| **Inactive** | Standard styling | Team loaded but not active |

**Interactions:**

| Action | Result |
|--------|--------|
| **Click** | Smooth scroll to team section |

### 1.2 Filter Toggles

**Purpose:** Shape table content without changing navigation state

Three filter groups control visibility/display:

```
┌──────────────────────────────────────────────────────────────┐
│  Display           │  Financials        │  Contracts         │
│  ☐ Cap Holds       │  ☑ Tax/Aprons      │  ☑ Options         │
│  ☑ Exceptions      │  ☐ Cash vs Cap     │  ☑ Incentives      │
│  ☑ Draft Picks     │  ☐ Luxury Tax      │  ☑ Two-Way         │
│  ☐ Dead Money      │                    │                    │
└──────────────────────────────────────────────────────────────┘
```

**Default State:**
- Display: Cap Holds OFF, Exceptions ON, Draft Picks ON, Dead Money OFF
- Financials: Tax/Aprons ON, Cash vs Cap OFF, Luxury Tax OFF
- Contracts: Options ON, Incentives ON, Two-Way ON

**Behavior:**
- Filters affect which sections/rows appear and which badges are displayed
- Filters do **NOT** change sidebar state or navigation
- Toggling a filter preserves scroll position (scrolls back to current active team after re-render)

---

## 2. Main Canvas — Team Sections

Each team renders as a **section** containing:
1. Team Header (sticky) with KPI cards
2. Table Header (sticky, attached to team header)
3. Player Rows (double-height)
4. Cap Holds Section (toggle-controlled)
5. Exceptions Section (toggle-controlled)
6. Dead Money Section (toggle-controlled)
7. Draft Assets Row (toggle-controlled)
8. Totals Footer

### 2.1 Team Header

**Components:**
- Team logo (from NBA CDN, fallback to 3-letter code)
- Team name (clickable to push Team entity)
- Conference label
- **KPI Cards:** Room under Tax, Room under First Apron, Room under Second Apron, Roster count

KPI cards are compact (w-24 = 96px), using color to indicate positive (green) vs negative (red) room.

### 2.2 Section Header Sticky Behavior (iOS Contacts Pattern)

Team header + table header behave as **one sticky group**. When the next team arrives, it pushes the previous header off.

**Critical Requirements:**
- Headers have opaque backgrounds (no content bleed-through)
- No phantom spacing when headers become sticky
- Smooth push transition between teams

### 2.3 Table Structure

**Column Layout:**
- **Sticky left:** Player name/info (w-52 = 208px)
- **Scrollable center:** 5-year salary horizon (2025–2029), each column 96px
- **Scrollable right:** Total column, Agent column

Horizontal scroll syncs between header and body.

### 2.4 Double-Row Player Design

Each player occupies **two visual rows** that behave as one unit:

**Row A (Primary):** Name, salary per year (monospace), total
**Row B (Metadata):** Position chip, experience, age, guarantee badges, option badges, bird rights, free agency type

**Salary Cell Styling (color-coded):**

| Condition | Background | Text Style |
|-----------|------------|------------|
| Fully Guaranteed | None (default) | Normal |
| Non-Guaranteed | Yellow tint | Yellow text |
| Player Option | Blue tint | Blue text |
| Team Option | Purple tint | Purple text |
| Early Termination Option | Orange tint | Orange text |

**Additional indicators (via tooltips):**
- Trade Kicker (with percentage if applicable)
- 15% Trade Bonus (for rookie scale contracts)
- Poison Pill provisions
- No-Trade Clause
- Consent Required

**Interaction:**
- Hover highlights BOTH rows as one unit
- Click anywhere → opens Player entity in sidebar
- Click agent name → opens Agent entity (stopPropagation)

### 2.5 Cap Holds Section

Displays cap holds from `pcms.cap_holds_warehouse`. Each hold shows:
- Name (player name or hold type)
- Cap amount for current year
- Type badge (Bird, Early Bird, 1st Round, etc.)

Toggle-controlled via "Cap Holds" filter.

### 2.6 Exceptions Section

Displays trade exceptions and salary exceptions from `pcms.exceptions_warehouse`. Each shows:
- Exception type
- Amount
- Expiration date

Toggle-controlled via "Exceptions" filter.

### 2.7 Dead Money Section

Displays waived player amounts from `pcms.dead_money_warehouse`. Each shows:
- Player name
- Amount(s) by year

Toggle-controlled via "Dead Money" filter.

### 2.8 Draft Assets Row

Pick pills aligned under corresponding year columns. Each pill shows:
- Origin team + round (e.g., "LAL 1" = Lakers 1st round pick)
- Clickable → opens Pick entity in sidebar

Toggle-controlled via "Draft Picks" filter.

### 2.9 Totals Footer

Non-sticky footer at section bottom showing:
- Total salary by year
- Cap space by year
- Tax line status (over/under)

---

## 3. Scroll-Spy System

The scroll-spy is the heart of the app. It implements a **Silk-inspired progress-driven model** where scroll position is the primary state driver.

### Core Concept: Scroll Position IS State

Unlike traditional approaches where scroll events trigger state updates, we treat scroll position as the source of truth:

```tsx
const {
  activeTeam,       // Which team's header is sticky
  sectionProgress,  // 0→1 through that section
  scrollState,      // idle | scrolling | settling
} = useShellContext();
```

Components subscribe to these values and react directly — no intermediate event handling.

### Definition: "Active Team"

The team whose section header is currently in the sticky position, OR (if no header is stuck) whose section top is closest to the viewport top.

### Scroll-Spy Outputs

| Output | Type | Description |
|--------|------|-------------|
| `activeTeam` | `string \| null` | Team code of the currently active section |
| `sectionProgress` | `number` | 0 when section just became active, 1 when next section takes over |
| `scrollState` | `"idle" \| "scrolling" \| "settling"` | Current scroll lifecycle state |

### How `sectionProgress` Works

Progress is calculated based on the scroll position relative to section boundaries:

```
Section A (active)     Section B (next)
┌──────────────────┐   ┌──────────────────┐
│ ▲ threshold line │   │                  │
│ ║                │   │                  │
│ ║ progress=0.3   │   │                  │
│ ║ (30% through)  │   │                  │
│ ▼                │   │                  │
└──────────────────┘   └──────────────────┘
```

- **progress = 0**: Section A's top just crossed the threshold (just became active)
- **progress = 1**: Section B's top is about to cross the threshold (handoff imminent)
- **Last section**: Progress based on scroll distance to container bottom

### Scroll Lifecycle States

| State | Meaning | Duration |
|-------|---------|----------|
| `idle` | User is not scrolling | Indefinite |
| `scrolling` | Scroll events are firing | While scrolling |
| `settling` | Scroll stopped, waiting for momentum/snap | ~150ms after last event |

**Use cases:**
- Suppress expensive updates during `scrolling`
- Trigger final animations on transition to `idle`
- Wait for scroll snap during `settling`

### Behaviors

| Scenario | Behavior |
|----------|----------|
| **Scroll updates** | `activeTeam` and `sectionProgress` update in real-time via RAF |
| **Top bar** | Active team highlighted in selector grid |
| **Sidebar (default mode)** | Shows active team's context |
| **Sidebar (entity mode)** | Does NOT change — overlay stays until dismissed |
| **Programmatic scroll** | Scroll-spy locked until scroll completes (prevents flicker) |
| **Filter toggle** | Scroll position preserved — scrolls back to same team after re-render |

### Progress-Driven Animations

Use `sectionProgress` for scroll-linked effects:

```tsx
import { applyProgressStyles } from "@/lib/animate";

// Fade header as section scrolls
applyProgressStyles(headerRef.current, sectionProgress, {
  opacity: (p) => 1 - (p * 0.3),  // 1.0 → 0.7
  transform: (p) => `translateY(${p * -8}px)`,
});
```

Or with the `tween()` helper for CSS calc():

```tsx
import { tween } from "@/lib/animate";

el.style.opacity = tween("1", "0.7", sectionProgress);
// → "calc(1 + (0.7 - 1) * 0.45)" at 45% progress
```

### Implementation

**Hook:** `useScrollSpy` in `src/features/SalaryBook/shell/useScrollSpy.ts`

**Key implementation details:**
- Sections registered via `registerSection(teamCode, element)`
- Sorted by DOM position (not registration order)
- Uses `requestAnimationFrame` for batched updates
- Programmatic scroll via `scrollToTeam(code, behavior)` with auto-unlock

**Configuration:**
```tsx
useScrollSpy({
  topOffset: 0,           // Sticky threshold inside container
  activationOffset: 160,  // Switch sooner for natural feel
  containerRef: canvasRef,
  scrollEndDelay: 100,    // Debounce for scroll end detection
  settleDelay: 50,        // Time in "settling" before "idle"
});
```

---

## 4. Sidebar — Intelligence Panel

### State Machine (2-Level Model)

The sidebar uses a simple **base + overlay** model:

```
LEVEL 0 (BASE)              LEVEL 1 (OVERLAY)
┌──────────────────┐        ┌──────────────────┐
│   TEAM CONTEXT   │        │  ENTITY DETAIL   │
│  (from scroll)   │───────▶│  (one at a time) │
└──────────────────┘  push  └────────┬─────────┘
       ▲                             │
       │            ┌────────────────┘
       │ [Back]     ▼
       └─────────────

Clicking another entity while in ENTITY MODE → REPLACES overlay
(does not push deeper)
```

**Key behaviors:**
- **Click entity** → pushes entity detail as overlay
- **Click different entity while viewing entity** → replaces current overlay
- **Click Back** → pops overlay, returns to team context (current scroll position)
- **Scroll while entity open** → team context underneath updates silently; Back returns to *new* team

### 4.1 Default Mode (Team Context)

When no entity is selected, sidebar shows the **active team from scroll-spy**:

**Components:**
- Team header (logo, name, conference)
- Tab toggle: **Cap Outlook** / **Team Stats**

**Cap Outlook Tab:**
- Total salary
- Cap space
- Room under thresholds (Tax, First Apron, Second Apron)
- Salary projections bar chart (5-year horizon)
- Two-way player capacity (games remaining based on roster count)

**Team Stats Tab:**
- Placeholder for future phase (record, standings, efficiency)

### 4.2 Entity Mode (Pushed Detail)

**Back Button:** Shows team logo + team code, returns to current viewport team (not where you started).

**Entity Types:**

| Entity | Triggered By | Detail Content |
|--------|--------------|----------------|
| **PLAYER** | Click player row | Contract breakdown by year, guarantee structure, option details, extension eligibility, trade kicker info |
| **TEAM** | Click team name | Same as default view but "pinned" (won't change on scroll) |
| **AGENT** | Click agent name | Agency info, client list grouped by team with salary totals |
| **PICK** | Click draft pick pill | Pick metadata, protections, origin/destination teams |

### 4.3 Back Navigation

**Critical behavior:** Back returns to the *current* viewport team, not where you started.

**Example:**
1. User at Celtics, clicks Jaylen Brown
2. Sidebar shows Jaylen Brown detail
3. User scrolls canvas to Lakers
4. User clicks Back
5. **Result:** Sidebar shows Lakers team context

---

## 5. Interaction Catalog

| Surface | Click Action | Sidebar Result |
|---------|--------------|----------------|
| **Team name** in section header | Push Team entity | Entity mode: team pinned |
| **Player row** (either sub-row) | Push Player entity | Entity mode: player detail |
| **Agent name** | Push Agent entity | Entity mode: agent detail |
| **Draft pick pill** | Push Pick entity | Entity mode: pick detail |
| **Top bar team abbreviation** | Scroll to team | No sidebar change if entity mode |
| **Sidebar Back button** | Pop entity | Returns to current team context |

---

## 6. Performance Considerations

### Memoization

- **`PlayerRow`**: Wrapped in `React.memo()` with custom comparison (checks player ID + key fields + filter toggles)
- **`SalaryTable`**: `filteredPlayers` wrapped in `useMemo()`
- **Click handlers**: Wrapped in `useCallback()` for stable references

### SWR Caching

All data fetching uses SWR with:
- Global deduplication (concurrent requests for same key = single fetch)
- Stale-while-revalidate (cached data renders immediately)
- Per-key caching (switching teams shows cached data while revalidating)

### Future: Virtualization

Current implementation renders all teams into the DOM. For larger datasets, consider:
- `@tanstack/react-virtual` for row virtualization
- Fixed header + virtualized body pattern to preserve sticky behavior

---

## 7. Design System Notes

The UI follows a **Vercel-inspired aesthetic**:

- **Dark mode default** with proper light mode support
- **Monospace accent** for numbers, labels, metadata
- **Information-dense** layouts (tight spacing, small text sizes)
- **Minimal decoration** (no gradients, subtle shadows)
- **Color for semantics only** (guarantee status, option types, positive/negative values)

Typography:
- Sans: Geist Sans (fallback: Inter, system-ui)
- Mono: Geist Mono (for salaries, codes, metadata)

Interactive states:
- `transition-colors duration-100` for color changes
- Border-only focus (not ring)
- Subtle hover backgrounds (`bg-muted/30`)

---

## Summary

| Concept | Description |
|---------|-------------|
| **Scroll Position IS State** | `activeTeam`, `sectionProgress`, `scrollState` drive everything |
| **Progress-Driven Animations** | Use `sectionProgress` (0→1) for scroll-linked effects |
| **2-Level Entity Details** | Click entity pushes overlay; click another replaces it |
| **Smart Back Navigation** | Returns to current viewport team, not origin |
| **iOS-Style Headers** | Team + table header stick together, pushed off by next team |
| **Double-Row Players** | Two rows per player for density without sacrificing info |
| **Filter Toggles** | Shape content without affecting navigation |
| **SWR Data Layer** | All fetches cached/deduped via SWR hooks |
| **Postgres is the Product** | UI is a thin consumer of warehouse tables |
