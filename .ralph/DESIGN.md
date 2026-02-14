# Design Evolution Backlog (`web/`)

North star:
- Entity index pages are explorer workbenches (fast scan, dense rows, low-friction pivots).
- Entity detail pages are decision dossiers (what changed, why it matters, what to do next).
- Canonical Datastar patch boundaries remain stable: `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`.
- Salary Book is read-only reference quality except explicit Tankathon allow-list work.

Rubric (1-5):
1) Scan speed
2) Information hierarchy
3) Interaction predictability
4) Density/readability balance
5) Navigation/pivots

Guardrails:
- Default: do **not** modify Salary Book files.
- Allowed exception only: `web/app/views/tools/salary_book/_maincanvas_tankathon_frame.html.erb`.
- Do not modify Salary Book controllers/helpers/tests.

Execution mode:
- Current priority is **entity detail page elevation**.
- INDEX and TOOL work continues in parallel where high leverage.
- ENTITY work is explicitly approved in this queue.

Supervisor override: ENTITY
[ENTITY-OVERRIDE]

Backlog hygiene policy (active-only):
- Keep only active unchecked tasks (`- [ ] ...`) in this file.
- Archive completed-task detail to git history (commit diffs/messages), not long in-file history.
- Optional: keep at most one short audit note for recent housekeeping.

Audit note (2026-02-14):
- Completed `[P3] [PROCESS] design backlog hygiene` (archived from checklist to keep this file active-only).
- What changed (files): `.ralph/DESIGN.md` (removed historical completed blocks; retained policy + one audit note), `agents/design.ts` (added active-only guard against completed task blocks; updated worker/supervisor/generate prompts to require active-only backlog hygiene).
- Why this improves the flow: keeps loop startup context small and current, lowers token overhead, and reduces drift from stale completed-task narratives.
- Rubric (before → after): Scan speed 3 → 5; Information hierarchy 4 → 5; Interaction predictability 4 → 5; Density/readability 3 → 5; Navigation/pivots 3 → 4.
- Follow-up tasks discovered: consider mirroring active-only hygiene guardrails across other backlog files if they begin accumulating long completed histories.

---

_No active tasks. Run the design backlog generation flow to seed the next queue._
