# Blueprints

Design documents for the Excel cap workbook.

---

## The guiding light

We are building Excel workbooks for NBA salary cap analysts. Three pillars:

1. **Correct data** — We shove authoritative data from Postgres into Excel (`DATA_*` sheets). The data layer is solid and trustworthy.

2. **Modern Excel** — We use XlsxWriter to generate workbooks with modern Excel features: `FILTER`, `XLOOKUP`, `LET`, `LAMBDA`, dynamic arrays. No legacy hacks.

3. **Dense, beautiful, reactive UI** — We build UI sheets that are information-dense yet visually clean. Inputs drive the view. Change something → everything reacts.

**That's it.** Anything that doesn't serve these three pillars is wrong.

---

## Documents

| File | Purpose |
|------|---------|
| `excel-cap-book-blueprint.md` | Design vision, principles, what we're building |
| `mental-models-and-design-principles.md` | Foundational thinking: trust, density, reactivity |
| `data-contract.md` | DATA_ sheet specifications (Postgres → Excel) |
| `specs/` | Legacy sheet notes. For PLAYGROUND, the source of truth is `excel/UI.md`. |

---

## Quick links

- PLAYGROUND spec (authoritative): `excel/UI.md`
- XlsxWriter patterns: `excel/XLSXWRITER.md`
- Folder context: `excel/AGENTS.md`
- Progress tracking: `.ralph/EXCEL.md`
