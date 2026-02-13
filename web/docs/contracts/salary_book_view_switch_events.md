# Contract — Salary Book view switch custom event bus (v1)

Status: implemented (Salary Book + Injuries + Tankathon v1)

Scope: switching the Salary Book main frame view without reloading the page.

## Event contract

Event name:
- `salarybook-switch-view`

Dispatch shape:

```js
el.dispatchEvent(new CustomEvent('salarybook-switch-view', {
  bubbles: true,
  detail: {
    view: 'salary-book', // or 'injuries' | 'tankathon'
    team: 'BOS',         // optional fallback to root active team
    year: '2025'         // optional fallback to page salary year
  }
}))
```

Payload:
- `detail.view` (required): one of `injuries`, `salary-book`, `tankathon`
- `rotation` is present in the UI but currently disabled (no-op)
- `detail.team` (optional): 3-letter NBA team code
- `detail.year` (optional): 4-digit salary year

## Handler contract

Root listener:
- `#salarybook` in `web/app/views/tools/salary_book/show.html.erb`

Root behavior:
1. Normalize/validate `view`
2. Resolve `team` and `year` fallback values
3. If view is unchanged, no-op
4. Update `activeview` signal
5. Fire one request:
   - `GET /tools/salary-book/frame?view=...&team=...&year=...`
6. Update URL via `history.replaceState` (`team`, `year`, `view`)

## Emitters (current)

- Command bar view radios (`show.html.erb`)
