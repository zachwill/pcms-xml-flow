# Contract — Salary Book player command palette (v1)

Status: implemented

Scope: `Cmd/Ctrl + K` player command palette in Salary Book.

Behavioral scope:
- Blank query defaults to the active team's roster.
- Non-blank query searches players by name across `pcms.salary_book_warehouse`.

## Patch + DOM contract

Stable IDs:

- `#sbplayercmdk` (palette root/backdrop)
- `#sbplayercb-input`
- `#sbplayercb-popup`
- `#sbplayercb-list`
- `#sbplayercb-status`

Search requests patch a **single region**: `#sbplayercb-popup` (`text/html`).

## Signal contract

Local-only signals on `#sbplayercmdk`:

- `$_sbplayercmdkopen`
- `$_sbplayercbopen`
- `$_sbplayercbquery`
- `$_sbplayercbactiveindex`
- `$_sbplayercbcomposing`

Global signal dependency:

- `$activeteam` (used as default roster scope for blank queries)

## Endpoint contract

### Search

`GET /tools/salary-book/combobox/players/search`

Params:

- `team` (optional, NBA team code; palette wiring passes current `$activeteam`)
- `q` (query string)
- `limit` (max 50; defaults to 12)
- `seq` (client request sequence echo)

Response:

- `text/html`
- renders `tools/salary_book/_combobox_players_popup`

Ranking (non-blank query):

1. prefix match (`player_name` starts with query)
2. token prefix match (`" <query>"`)
3. infix contains
4. tie-break: `cap_2025 DESC`, then `player_name ASC`, `player_id ASC`

Blank-query behavior:
- with `team`: returns that team's roster (same tie-break ordering)
- without `team`: returns empty set

## Interaction contract (v1)

- `Cmd/Ctrl + K` opens command palette with backdrop and focuses input.
- Opening dispatches a blank-query request (default roster list for `$activeteam`).
- Typing dispatches debounced search (120ms).
- IME composition suppresses mid-composition dispatch.
- First result is auto-selected whenever result set is non-empty.
- ArrowUp/ArrowDown moves active option.
- Enter commits active option (or first option if no explicit active index yet).
- Escape closes palette.
- Backdrop click closes palette.
- Option click closes palette and patches `#rightpanel-overlay` via:
  - `GET /tools/salary-book/sidebar/player/:id`
- Selection does **not** switch active team in v1.

## Cancellation guardrail

Search dispatches directly from palette open/input events (`@get` on the palette/input element).
Datastar cancellation remains per-element, and this flow does not interfere with team switch SSE requests.
