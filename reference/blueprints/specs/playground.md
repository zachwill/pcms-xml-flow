# PLAYGROUND Sheet Spec (Legacy)

**Important:** This file is no longer the authoritative PLAYGROUND UI specification.

- **SOURCE OF TRUTH:** `excel/UI.md`
- This file remains as a *principles / background* document.
- If anything here conflicts with `excel/UI.md`, follow **`excel/UI.md`**.

---

## Why this exists

Historically, coding agents would read this spec and “shortcut” the product into an MVP (roster + a couple totals).

The current direction is explicitly:
- **Dense** (terminal-like)
- **Reactive** (inputs drive the view)
- **Multi-year** (base year + 5)
- **Sean-complete** (fills, thresholds, picks, exceptions, etc.)

All details now live in `excel/UI.md`.

---

## Still useful notes

- Prefer modern Excel formulas: `FILTER`, `SORTBY`, `XLOOKUP`, `LET`, `LAMBDA`.
- Data sources are the embedded `DATA_*` tables.
- Avoid legacy helper columns unless they materially improve performance/readability.
