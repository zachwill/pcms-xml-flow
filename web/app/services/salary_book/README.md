# Salary Book service map

This folder keeps `SalaryBookController` orchestration-only.

## Why this exists

Future coding agents should be able to change behavior without hunting through one giant controller.

These service objects are **request-state builders**. They return plain hashes that controllers assign to ivars or pass into partials.

## Action → service mapping

| Controller action | Service(s) | Notes |
|---|---|---|
| `SalaryBookController#show` | `WorkspaceState` | Boot payload for full page render. |
| `SalaryBookController#frame` | `FrameState` | Patchable `#salarybook-team-frame` payload for view switches. |
| `SalaryBookController#sidebar_team` / `#sidebar_team_cap` / `#sidebar_team_draft` / `#sidebar_team_rights` | `TeamSidebarState` | Base + tab payloads. |
| `SalaryBookController#combobox_players_search` | `ComboboxPlayersState` | Param normalization + popup locals. |
| `SalaryBookController#sidebar_pick` | `SidebarPickState` | Pick overlay hydration. |
| `SalaryBookSwitchController#switch_team` | `FrameState`, `TeamSidebarState` | Reuses same frame/sidebar logic as non-switch endpoints. |

## Stability contracts

- `FrameState#build` and `#fallback` return:
  - `partial:` String
  - `locals:` Hash
- `WorkspaceState#build` and `#fallback` return ivar-ready keys consumed by `salary_book/show.html.erb`.
- `TeamSidebarState#build` returns locals consumed by `salary_book/_sidebar_team.html.erb`.

## Extension guidelines

1. **Add SQL to `SalaryBookQueries` first** (explicit I/O boundary).
2. Add/extend a focused service in this folder.
3. Keep controller changes to orchestration only.
4. Keep Datastar patch IDs stable (`#maincanvas`, `#rightpanel-base`, etc.).

## Anti-patterns to avoid

- Putting DB calls back into views/helpers.
- Re-adding branching payload assembly directly in controllers.
- Duplicating frame logic between `salary_book` and `salary_book_switch` controllers.
