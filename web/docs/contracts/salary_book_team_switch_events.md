# Contract — Salary Book team switch custom event bus (v1)

Status: implemented

Scope: team switching interactions in Salary Book.

## Event contract

Event name:
- `salarybook-switch-team`

Dispatch shape:

```js
el.dispatchEvent(new CustomEvent('salarybook-switch-team', {
  bubbles: true,
  detail: {
    team: 'BOS',
    year: '2025' // optional
  }
}))
```

Payload:
- `detail.team` (required): 3-letter NBA team code
- `detail.year` (optional): 4-digit salary year string/integer

## Handler contract

Root listener:
- `#salarybook` in `web/app/views/tools/salary_book/show.html.erb`

Root behavior:
1. Normalize/validate `team` (`/^[A-Z]{3}$/`)
2. Resolve `year` (fallback to current page salary year)
3. If team is already active, no-op
4. Update switch-related signals:
   - `activeteam`
   - `seasonlocked`
   - `selectedseason`
   - `sidebarteamloaded`
   - `sidebarcapyearloaded`
   - `sidebardraftloaded`
   - `sidebardraftyearloaded`
   - `sidebarrightsloaded`
5. Resolve active view (`salary-book` / `injuries` / `tankathon`) from root signal state.
6. Fire one request:
   - `GET /tools/salary-book/sse/switch-team?team=...&year=...&view=...`
7. Update URL via `history.replaceState` (`team`, `year`, `view` query params)

## Emitters (current)

- Command bar team grid (`show.html.erb`)
- Player overlay team chip (`_sidebar_player.html.erb`)
- Pick overlay team chips (`_sidebar_pick.html.erb`)

## Overlay behavior

Team switching **does not implicitly clear** `#rightpanel-overlay`.

Overlay close is explicit:
- `GET /tools/salary-book/sidebar/clear`
- or opening another overlay target (`player`, `agent`, `pick`)

## Why this contract exists

- Removes duplicated switch-team side-effect blocks across partials
- Keeps switch semantics consistent as new team-switch affordances are added
- Reduces regression risk when switch logic changes (single handler to update)
