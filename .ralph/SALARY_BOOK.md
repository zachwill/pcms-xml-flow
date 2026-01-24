# Salary Book Tasks

Build the NBA Salary Book from `web/specs/01-salary-book.md`.

A scroll-driven front-office tool where scroll position drives context.
Demonstrates how Base UI components map to complex, in-depth specifications.

**All code lives in the `web/` directory.** Paths like `src/features/SalaryBook/` mean `web/src/features/SalaryBook/`.

**Data Source:** Real data from PostgreSQL (`pcms` schema). See `web/docs/bun-postgres.md` for Bun SQL usage.

Key tables:
- `pcms.teams` — all 30 NBA teams (filter `league_lk = 'NBA' AND is_active = true`); has team_code, team_name, team_nickname, conference_name, division_name
- `pcms.salary_book_warehouse` — player salaries, options, agents; columns include player_id, player_name, team_code, age, agent_id, agent_name, cap_2025..cap_2030, option_2025..option_2030, is_two_way, is_no_trade, is_trade_bonus, etc.
- `pcms.team_salary_warehouse` — team totals per salary_year (2025-2030); cap_total, tax_total, salary_cap_amount, tax_level_amount, room_under_tax, is_taxpayer, is_repeater_taxpayer, etc.
- `pcms.draft_picks_warehouse` — draft picks per team/year/round; has team_code, draft_year, draft_round, asset_type (OWN/TO/HAS/OTHER), raw_fragment (human-readable pick description)
- `pcms.agents` — agent info (agent_id, agency_id, agency_name, full_name)

---

## Phase 1: Foundation

### Data Layer (Real PostgreSQL Data)
- [x] Create `src/features/SalaryBook/data/types.ts` with interfaces: SalaryBookPlayer, Team, TeamSalary, DraftPick, Agent
- [x] Create `src/features/SalaryBook/data/index.ts` barrel export

### API Routes (Fetch from PostgreSQL)
- [x] Create `src/api/routes/salary-book.ts` with RouteRegistry for salary book endpoints
- [x] Add `GET /api/salary-book/teams` — fetch NBA teams from pcms.teams (league_lk='NBA', is_active=true)
- [x] Add `GET /api/salary-book/players?team=:teamCode` — fetch from pcms.salary_book_warehouse
- [x] Add `GET /api/salary-book/team-salary?team=:teamCode` — fetch from pcms.team_salary_warehouse for years 2025-2030
- [x] Add `GET /api/salary-book/picks?team=:teamCode` — fetch from pcms.draft_picks_warehouse (asset_type, raw_fragment per year/round)
- [x] Add `GET /api/salary-book/agent/:agentId` — fetch agent from pcms.agents + clients from salary_book_warehouse
- [x] Merge salary-book router into server.ts

### Hooks
- [x] Create `src/features/SalaryBook/hooks/useScrollSpy.ts` — tracks which team section header is currently sticky (active team)
- [x] Create `src/features/SalaryBook/hooks/useSidebarStack.ts` — manages entity navigation stack (push/pop/back behavior)
- [x] Create `src/features/SalaryBook/hooks/useFilterState.ts` — manages filter toggles state (Display, Financials, Contracts groups)
- [x] Create `src/features/SalaryBook/hooks/index.ts` barrel export
- [x] Export useFilterState from hooks barrel after creation

---

## Phase 1.5: Data Fetching Hooks

- [x] Create `src/features/SalaryBook/hooks/useTeams.ts` — fetch teams from API, memoize
- [x] Create `src/features/SalaryBook/hooks/usePlayers.ts` — fetch players for a team code
- [x] Create `src/features/SalaryBook/hooks/useTeamSalary.ts` — fetch team salary totals
- [x] Create `src/features/SalaryBook/hooks/usePicks.ts` — fetch draft picks for a team
- [x] Create `src/features/SalaryBook/hooks/useAgent.ts` — fetch agent detail + clients
- [x] Export all data hooks from `src/features/SalaryBook/hooks/index.ts`

---

## Phase 2: Layout Skeleton

- [x] Create `src/features/SalaryBook/SalaryBook.tsx` — main layout with fixed TopCommandBar, MainCanvas (~70%), Sidebar (~30%)
  - Fixed TopCommandBar at viewport top (highest z-index)
  - Flex layout: MainCanvas takes remaining space left, Sidebar fixed 30% width right
  - MainCanvas has single vertical scroll, Sidebar has independent scroll
- [x] Create `src/features/SalaryBook/index.tsx` barrel export (exports SalaryBook component + hooks + types)
- [x] Add SalaryBookContext provider for shared state (activeTeam, sidebarStack, filters) — implemented in SalaryBook.tsx

### BLOCKING — Do Next
- [x] **Add `/salary-book` route to `src/client.tsx`** — REQUIRED to access feature in browser

---

## Phase 3: TopCommandBar ← CURRENT FOCUS

### Team Selector Grid
- [x] Create `src/features/SalaryBook/components/TopCommandBar/TeamSelectorGrid.tsx` — 2 conferences, 3 rows × 5 teams each, alphabetically sorted
  - Use `useTeams()` hook to fetch team data
  - Use `useSalaryBookContext()` for activeTeam, loadedTeams, scrollToTeam
  - Grid layout: CSS Grid with `grid-template-columns: repeat(5, 1fr)` per conference
- [x] Add visual states: active (scroll-spy), loaded, unloaded
  - Active: filled background (primary color) + ring highlight
  - Loaded: subtle dot indicator (top-right corner)
  - Unloaded: muted/dimmed text with opacity
- [x] Add click → jump to team, Shift+click → toggle loaded, Alt+click → isolate
  - Regular click: `scrollToTeam(teamCode)` + ensure in loadedTeams
  - Shift+click: toggle team in/out of loadedTeams without scrolling
  - Alt+click: set loadedTeams to only this team, then scroll to it

### Barrel & Composition ← **DO NEXT** (unblocks TopCommandBar in UI)
- [x] Create `src/features/SalaryBook/components/TopCommandBar/index.ts` barrel export — exports TeamSelectorGrid
- [x] Create `src/features/SalaryBook/components/TopCommandBar/TopCommandBar.tsx` — composes Grid (filters placeholder for now)
- [x] Wire TopCommandBar into SalaryBook.tsx — replace placeholder with real component

### Filter Toggles (can parallel with MainCanvas work)
- [x] Create `src/features/SalaryBook/components/TopCommandBar/FilterToggles.tsx` — 3 groups: Display, Financials, Contracts
  - Use checkbox groups from design system or native inputs
  - Three columns layout matching spec
- [x] Wire filters to useFilterState hook from context
- [x] Add FilterToggles to TopCommandBar.tsx composition

---

## Phase 4: MainCanvas

### Team Section Container
- [x] Create `src/features/SalaryBook/components/MainCanvas/TeamSection.tsx` — wrapper for one team's salary book
  - Accepts `teamCode` prop
  - Uses `usePlayers(teamCode)`, `useTeamSalary(teamCode)`, `usePicks(teamCode)` for data
  - Composes TeamHeader, TableHeader, PlayerRows, DraftAssetsRow, TotalsFooter
- [x] Add scroll-spy ref registration (IntersectionObserver target) — already wired via registerSection

### Sticky Headers (Critical)
- [x] Create `src/features/SalaryBook/components/MainCanvas/TeamHeader.tsx` — team name, logo placeholder, mini-totals
  - Shows team code/name + current year salary summary
  - Background must be opaque (no content bleed-through)
- [x] Create `src/features/SalaryBook/components/MainCanvas/TableHeader.tsx` — two-row header (category groups + column labels)
  - Row 1: PLAYER INFO | CONTRACT YEARS | MANAGEMENT (category band)
  - Row 2: Name | Pos | Exp | 24-25 | 25-26 | 26-27 | 27-28 | 28-29 | Agent | Agency
- [x] Implement iOS Contacts-style sticky behavior: team header + table header as ONE sticky group
  - Single sticky container wrapping both headers
  - `position: sticky; top: 0` on the combined unit
- [x] Ensure opaque backgrounds, proper z-index layering (z-20), smooth push transition

### Player Row (Double-Row Design) — CRITICAL
- [x] Create `src/features/SalaryBook/components/MainCanvas/PlayerRow.tsx` — primary row + metadata row as one unit
  - Wrap both sub-rows in a single container for hover state
- [x] Primary row: name (prominent), salary per year (monospace), agent name (clickable)
  - Use `tabular-nums` and `font-mono` for salary figures
  - Agent name has onClick that pushes AgentEntity to sidebar (stopPropagation)
- [x] Metadata row: position chip, experience, age, guarantee structure, option flags, bird rights
  - Lower contrast (text-muted-foreground)
  - Option flags: PO, TO, ETO badges per year
- [x] Hover highlights both rows; click opens player in sidebar; agent click opens agent (stopPropagation)
  - Container `group` class, hover styles on both rows
  - onClick on container → push PlayerEntity

### Supplementary Rows
- [x] Create `src/features/SalaryBook/components/MainCanvas/DraftAssetsRow.tsx` — pick pills aligned under year columns
  - Pills show origin team + round (e.g., "LAL 1")
  - Each pill clickable → push PickEntity
  - Visibility controlled by filters.display.draftPicks
- [x] Create `src/features/SalaryBook/components/MainCanvas/TotalsFooter.tsx` — totals, cap space, tax line per year
  - Non-sticky, at bottom of each team section
  - Shows totals, cap space (green if positive, red if negative), tax line

### Table & Horizontal Scroll
- [x] Create `src/features/SalaryBook/components/MainCanvas/SalaryTable.tsx` — composes headers + player rows + assets + footer
  - Outer container with `overflow-x: auto`
  - Inner table/grid layout
- [x] Implement sticky left columns (Player Info) during horizontal scroll
  - `position: sticky; left: 0` on left columns
  - Must work across both sub-rows of PlayerRow
- [x] Add visual separator (shadow) at sticky edge
  - Box-shadow or border on sticky column edge

### Barrel & Composition
- [x] Create `src/features/SalaryBook/components/MainCanvas/index.ts` barrel export
- [x] Extract MainCanvas component from SalaryBook.tsx to `src/features/SalaryBook/components/MainCanvas/MainCanvas.tsx`
  - Move MainCanvas function component to its own file
  - Export from MainCanvas/index.ts barrel
- [x] Replace TeamSectionPlaceholder in SalaryBook.tsx with real TeamSection components

---

## Phase 5: Sidebar

### Panel Container
- [x] Create `src/features/SalaryBook/components/Sidebar/SidebarPanel.tsx` — handles stack state, renders current view
  - Uses `useSalaryBookContext()` for sidebarMode, currentEntity, activeTeam, popEntity
  - Conditionally renders entity detail or team context
- [x] Implement Back button that returns to CURRENT viewport team (not origin)
  - Calls `popEntity()` which pops stack; scroll-spy determines new team context

### Default Mode (Team Context)
- [x] Create `src/features/SalaryBook/components/Sidebar/TeamContext.tsx` — shows active team from scroll-spy
  - Uses `useTeamSalary(activeTeam)` for financial data
  - Uses `getTeam(activeTeam)` for team info
- [x] Add Cap Outlook tab: total salary, cap space, tax apron, luxury tax bill
  - Pull from team_salary_warehouse data (cap_total, cap_space, room_under_tax)
- [x] Add Team Stats tab placeholder (future phase)

### Entity Detail Views
- [x] Create `src/features/SalaryBook/components/Sidebar/PlayerDetail.tsx` — photo placeholder, contract breakdown, year-by-year, AI insights placeholder
  - Uses player data from sidebar stack entity
  - Shows contract year-by-year with guarantee info
  - Could fetch fresh via `/api/salary-book/player/:playerId` if needed
- [x] Create `src/features/SalaryBook/components/Sidebar/AgentDetail.tsx` — agency info, client list with player links
  - Uses `useAgent(agentId)` hook
  - Lists clients, each clickable to push PlayerEntity
- [x] Create `src/features/SalaryBook/components/Sidebar/PickDetail.tsx` — pick metadata, protections, origin/destination, conveyance history
  - Shows pick year, round, origin team, asset type
  - Fetches from new `/api/salary-book/pick` endpoint
  - Displays protections, origin/destination transfer, conveyance history placeholder

### Barrel & Integration
- [x] Create `src/features/SalaryBook/components/Sidebar/index.ts` barrel export
- [x] **CRITICAL: Wire SidebarPanel into SalaryBook.tsx** — replace inline Sidebar function with real SidebarPanel component
  - Remove inline `Sidebar`, `EntityDetailPlaceholder`, `TeamContextPlaceholder` functions from SalaryBook.tsx
  - Import and use `SidebarPanel` from `./components/Sidebar`

---

## Phase 6: Integration

- [x] Wire useScrollSpy to TeamSelectorGrid (highlight active team)
  - TeamSelectorGrid reads `activeTeam` from context and highlights matching pill
- [x] Wire useScrollSpy to SidebarPanel (default mode shows active team)
  - TeamContext component uses `activeTeam` to fetch/display correct team
- [x] Wire useSidebarStack to entity clicks (player row, agent name, pick pill, team name)
  - Each clickable element calls `pushEntity()` with appropriate entity type
- [x] Wire filters to SalaryTable (show/hide rows, columns, tags)
  - Read `filters` from context
  - Conditionally render cap holds, draft picks, dead money rows based on filters
- [x] Implement jump-to-team on TeamSelectorGrid click (smooth scroll + update active)
  - Call `scrollToTeam(teamCode, 'smooth')` from context

---

## Phase 7: Polish

- [ ] Add smooth transitions for sidebar push/pop (slide animation)
- [x] Add hover animations for player rows (both sub-rows highlight together) ✅ already done via `group` class
- [x] Ensure monospace alignment for salary figures across all rows (use tabular-nums font-variant) ✅ done
- [ ] Add loading states for large team lists (skeleton loaders)
- [ ] Test dark mode appearance
- [ ] Verify no scroll-spy flicker during fast scrolling
- [ ] Verify sticky header push transition is smooth (no gaps, no remnants)
- [ ] Audit z-index layering: TopCommandBar > TeamHeader+TableHeader > sticky left columns > table cells
- [ ] Test horizontal scroll: left columns stay aligned across both sub-rows of each player

---

## Components Barrel
- [x] Create `src/features/SalaryBook/components/index.ts` — exports TopCommandBar, MainCanvas, Sidebar
- [x] MainCanvas barrel complete with MainCanvas, TeamSection exports
- [x] Sidebar barrel complete with SidebarPanel, TeamContext, PlayerDetail exports

---

## Supervisor Review Notes

**Last Review:** 2026-01-23 (after 4 commits: 87811a0)

**Progress:**
- Phase 1 & 1.5: ✅ Complete (data layer, API routes, all hooks)
- Phase 2: ✅ Complete (layout skeleton, route added)
- Phase 3: ✅ Complete (TopCommandBar, TeamSelectorGrid, FilterToggles)
- Phase 4: ✅ Complete — MainCanvas extracted, SalaryTable with horizontal scroll done
- Phase 5: 🔶 Mostly Complete — SidebarPanel, TeamContext, PlayerDetail done
  - Missing: AgentDetail.tsx, PickDetail.tsx (have placeholders)
  - **BUG: SidebarPanel not wired into SalaryBook.tsx** — inline Sidebar still used!
- Phase 6: 🔶 Partially Complete — scroll-spy wiring done, filters not applied yet

**Next Priority (in order):**
1. Create AgentDetail.tsx (uses useAgent hook already built)
2. Create PickDetail.tsx
3. Wire filters to hide/show draft picks, cap holds rows

**Quality Notes:**
- ✅ Sticky headers correctly implemented as single unit with opaque background
- ✅ PlayerRow double-row hover works correctly with `group` class
- ✅ useScrollSpy has proper debouncing via requestAnimationFrame
- ✅ Agent click stopPropagation works correctly
- ✅ TeamContext has real data with salary projections chart
- ✅ All barrel exports properly structured
- ✅ SidebarPanel wired into SalaryBook.tsx (replaced inline Sidebar)
