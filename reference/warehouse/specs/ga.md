# GA (Team/Playground variant) — stub

**Source:** `reference/warehouse/ga.json`

`GA` is another **Team/Playground-style Salary Book** view.

- Canonical spec: [`team.md`](team.md) (same core layout/outputs)
- Shared formula patterns (especially roster fill + proration): [`patterns.md`](patterns.md)

**Only notable nuance:** GA uses an explicit **anchor date cell** (in the export snapshot `F1` is a literal date, not `TODAY()`), which makes it a convenient sheet for “set a date → see prorated fill-to-12/14 charges” analysis.
