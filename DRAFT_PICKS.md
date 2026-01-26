# Draft Picks Data Documentation

Last updated: 2026-01-16

This document covers NBA draft pick data in PCMS, including the `draft_pick_summaries` extract and strategies for tracking pick ownership and lineage.

---

## Overview

PCMS provides two draft-pick-related extracts:

| Extract | File | Contents |
|---------|------|----------|
| `dp-extract` | `draft_picks.json` | Individual draft picks (DLG/WNBA only — no NBA!) |
| `dps-extract` | `draft_pick_summaries.json` | Per-team-per-year summaries with ownership descriptions |

**Key insight:** NBA draft picks are NOT in `draft_picks.json`. The only source of NBA draft pick ownership data is `draft_pick_summaries.json`.

---

## Draft Pick Summaries (`dps-extract`)

### Source Data

```bash
# 450 total records (30 teams × 15 years)
jq 'length' draft_pick_summaries.json
# 450

# Year range: 2018-2032
jq '[.[].draft_year] | unique | sort' draft_pick_summaries.json
# [2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030, 2031, 2032]

# Future picks (2026+): 210 records
jq '[.[] | select(.draft_year >= 2026)] | length' draft_pick_summaries.json
# 210
```

### Record Structure

```json
{
  "team_id": 1610612737,
  "draft_year": 2027,
  "first_round": "To SAS(58) | May have MIL(202) (via NOP(8)); may have NOP(202)",
  "second_round": "To POR(285) (via MEM(160) via BOS(113))",
  "active_flg": true,
  "create_date": "2025-08-18T17:36:11.883-04:00",
  "last_change_date": "2025-08-18T17:36:12.087-04:00",
  "record_change_date": "2025-08-18T17:36:12.087-04:00"
}
```

### Text Field Format

The `first_round` and `second_round` fields contain human-readable descriptions with embedded reference IDs.

#### Ownership Patterns

| Pattern | Meaning | Example |
|---------|---------|---------|
| `Own` | Team owns their own pick | `"Own"` |
| `To TEAM(N)` | Pick traded away to TEAM | `"To SAS(58)"` |
| `Has TEAM(N)` | Team acquired pick from TEAM | `"Has HOU(81)"` |
| `(via TEAM(N))` | Pick was routed through TEAM | `"(via LAC(78))"` |
| `May have TEAM(N)` | Conditional ownership | `"May have MIL(202)"` |
| `or to TEAM(N)` | Alternative destination | `"or to MIA(124)"` |
| `\|` | Separates multiple picks/scenarios | `"Own \| Has DAL(70)"` |
| `;` | Separates conditional branches | `"may have NOP(89); may have POR(89)"` |

#### Reference Numbers (Endnotes)

The numbers in parentheses like `(58)`, `(81)`, `(202)` are **internal PCMS reference IDs**.

**What we know:**
- 325 unique reference numbers in the data (ranging from 1 to ~370)
- They serve as "endnotes" pointing to the trade/transaction that moved the pick
- Multiple entries can share the same reference (same trade affected multiple picks)
- The `(via TEAM(N))` chains show pick provenance through multiple trades

**What we DON'T have:**
- The reference/endnote lookup table is NOT in the PCMS extract
- We cannot resolve `(58)` to a specific `trade_id` or `transaction_id`
- These are opaque correlation markers for external consumers

**Investigation results:**
- `trade_id` values range from 327 to 20,253,014 — don't match
- `transaction_id` small values (58, 81) are ancient 1986-1990 transactions — don't match
- `draft_pick_id` values are for DLG/WNBA picks only — don't match
- No "endnotes" table exists in the extract

#### Complex Examples

```
# ATL's 2027 first round pick situation:
"To SAS(58) | May have MIL(202) (via NOP(8)); may have NOP(202)"

Interpretation:
- ATL's own 1st: Traded to SAS (trade ref 58)
- ATL may get MIL's 1st (trade ref 202), which came via NOP (trade ref 8)
- ATL may get NOP's 1st (trade ref 202) — same trade, different outcome
```

```
# OKC's 2027 second round pick:
"Own or to MIA(124) | May have HOU(47) (via UTA(30) via OKC(19) via DET(10)) or to MIA(124)"

Interpretation:
- OKC owns their 2nd OR it goes to MIA (trade ref 124)
- OKC may get HOU's 2nd (ref 47), which went DET→OKC→UTA→current (refs 10,19,30)
- That pick could also go to MIA (ref 124)
```

---

## Proposed Database Schema

### Table 1: `pcms.draft_pick_summaries` (Raw Data)

Store the PCMS data as-is, preserving the original text descriptions.

```sql
CREATE TABLE pcms.draft_pick_summaries (
  draft_year integer NOT NULL,
  team_id integer NOT NULL,
  team_code text,                      -- Denormalized for convenience
  first_round text,                    -- Raw description with endnote refs
  second_round text,                   -- Raw description with endnote refs
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  record_changed_at timestamptz,
  ingested_at timestamptz DEFAULT now(),
  PRIMARY KEY (draft_year, team_id)
);

CREATE INDEX idx_draft_pick_summaries_team_code ON pcms.draft_pick_summaries(team_code);
CREATE INDEX idx_draft_pick_summaries_draft_year ON pcms.draft_pick_summaries(draft_year);
```

### Table 2: `pcms.draft_pick_ownership` (Enriched/Parsed Data)

A normalized table for structured queries on pick ownership. Can be populated by:
1. Parsing the summary text programmatically
2. Manual curation/verification
3. External data sources

```sql
CREATE TABLE pcms.draft_pick_ownership (
  id serial PRIMARY KEY,
  draft_year integer NOT NULL,
  round integer NOT NULL,              -- 1 or 2
  original_team_id integer NOT NULL,   -- Team whose pick this originally was
  original_team_code text,
  current_team_id integer,             -- Team that currently owns/controls it
  current_team_code text,
  ownership_status text NOT NULL,      -- 'owns', 'traded', 'conditional', 'swap_rights'
  destination_team_id integer,         -- If traded, who owns it now
  destination_team_code text,
  is_conditional boolean DEFAULT false,
  condition_description text,          -- Human-readable condition
  protection_description text,         -- e.g., "top-10 protected"
  swap_rights_team_id integer,         -- Team with swap rights (if any)
  swap_rights_team_code text,
  provenance_chain jsonb,              -- Array of {team_code, endnote_ref} showing path
  endnote_refs integer[],              -- All PCMS endnote references involved
  source text DEFAULT 'parsed',        -- 'parsed', 'manual', 'external'
  confidence text DEFAULT 'high',      -- 'high', 'medium', 'low' for parsed data
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (draft_year, round, original_team_id)
);

CREATE INDEX idx_draft_pick_ownership_year ON pcms.draft_pick_ownership(draft_year);
CREATE INDEX idx_draft_pick_ownership_current_team ON pcms.draft_pick_ownership(current_team_id);
CREATE INDEX idx_draft_pick_ownership_status ON pcms.draft_pick_ownership(ownership_status);

COMMENT ON TABLE pcms.draft_pick_ownership IS 'Normalized draft pick ownership data, parsed from summaries or manually curated';
COMMENT ON COLUMN pcms.draft_pick_ownership.provenance_chain IS 'JSON array showing how pick moved, e.g., [{"team":"DET","ref":10},{"team":"OKC","ref":19}]';
COMMENT ON COLUMN pcms.draft_pick_ownership.endnote_refs IS 'PCMS internal reference IDs from the summary text';
```

### Table 3: `pcms.draft_pick_endnotes` (Reference Mapping - Optional)

If we ever get access to the endnote reference table, or want to manually document known mappings:

```sql
CREATE TABLE pcms.draft_pick_endnotes (
  endnote_ref integer PRIMARY KEY,
  trade_id integer,                    -- If we can map to pcms.trades
  transaction_id integer,              -- If we can map to pcms.transactions
  trade_date date,
  description text,                    -- Human-readable description of the trade
  teams_involved text[],               -- Array of team codes
  source text DEFAULT 'manual',        -- 'manual', 'inferred', 'official'
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE pcms.draft_pick_endnotes IS 'Mapping of PCMS endnote references to trades (manually curated or inferred)';
```

---

## Parsing Strategy

### Regex Patterns for Text Extraction

```typescript
// Extract all endnote references
const endnotePattern = /\((\d+)\)/g;
// "To SAS(58)" → [58]

// Extract "To TEAM(N)" patterns
const tradedToPattern = /To ([A-Z]{3})\((\d+)\)/g;
// "To SAS(58)" → [{team: "SAS", ref: 58}]

// Extract "Has TEAM(N)" patterns  
const hasPattern = /Has ([A-Z]{3})\((\d+)\)/g;
// "Has HOU(81)" → [{team: "HOU", ref: 81}]

// Extract "via TEAM(N)" chains
const viaPattern = /via ([A-Z]{3})\((\d+)\)/g;
// "(via LAC(78) via BOS(9))" → [{team: "LAC", ref: 78}, {team: "BOS", ref: 9}]

// Extract "May have TEAM(N)" conditionals
const mayHavePattern = /[Mm]ay have ([A-Z]{3})\((\d+)\)/g;
// "May have MIL(202)" → [{team: "MIL", ref: 202, conditional: true}]

// Detect if team owns their pick
const ownsPattern = /^Own(?:\s|$|\|)/;
// "Own | Has DAL(70)" → true
```

### Parsing Complexity Levels

| Level | Description | Example |
|-------|-------------|---------|
| Simple | Team owns or single trade | `"Own"`, `"To SAS(58)"` |
| Medium | Multiple acquisitions | `"Own \| Has DAL(70); Has MIN(19)"` |
| Complex | Conditional + chains | `"May have HOU(47) (via UTA(30) via OKC(19))"` |
| Very Complex | Multiple conditionals + alternatives | Full 2027 examples above |

**Recommendation:** Start with simple cases, flag complex ones for manual review.

---

## Data Quality Notes

### What's in the Extract

- ✅ All 30 NBA teams
- ✅ Years 2018-2032 (15 years)
- ✅ Both rounds (1st and 2nd)
- ✅ Historical data (resolved picks)
- ✅ Future picks with current ownership
- ✅ Conditional scenarios

### What's Missing

- ❌ Endnote reference table (can't resolve `(N)` to trades)
- ❌ Protection details (only in text, not structured)
- ❌ Specific conditions for "May have" scenarios
- ❌ NBA picks in `draft_picks.json` (only DLG/WNBA)
- ❌ Historical pick ownership (only current snapshot)

### Caveats

1. **Point-in-time snapshot**: The summaries reflect ownership as of extract date
2. **Conditional picks**: "May have" scenarios depend on outcomes not yet determined
3. **Text parsing is imperfect**: Edge cases and unusual formatting exist
4. **Endnotes are opaque**: We can correlate but not resolve them

---

## Use Cases

### Query Examples (Once Tables Exist)

```sql
-- Which teams have the most future 1st round picks?
SELECT current_team_code, COUNT(*) as picks
FROM pcms.draft_pick_ownership
WHERE draft_year >= 2026 AND round = 1 AND ownership_status = 'owns'
GROUP BY current_team_code
ORDER BY picks DESC;

-- Show all of OKC's draft assets
SELECT draft_year, round, original_team_code, ownership_status, condition_description
FROM pcms.draft_pick_ownership
WHERE current_team_id = 1610612760
ORDER BY draft_year, round;

-- Find picks with swap rights
SELECT *
FROM pcms.draft_pick_ownership
WHERE swap_rights_team_id IS NOT NULL;

-- Search raw summaries for specific team mentions
SELECT team_code, draft_year, first_round, second_round
FROM pcms.draft_pick_summaries
WHERE first_round ILIKE '%LAL%' OR second_round ILIKE '%LAL%';
```

---

## Implementation Plan

### Phase 1: Schema & Raw Data
1. ✅ Run `migrations/archive/004_draft_pick_tables.sql` (creates both tables)
2. Create import script `draft_pick_summaries.inline_script.ts`
3. Add step to `flow.yaml`

### Phase 2: Parse & Enrich
1. Build parser for simple/medium complexity cases
2. Populate `draft_pick_ownership` with parsed data
3. Flag uncertain cases with `confidence = 'low'`

### Phase 3: Manual Curation (Optional)
1. Review flagged/complex cases
2. Create `pcms.draft_pick_endnotes` table if patterns emerge
3. Cross-reference with external sources (e.g., RealGM, Spotrac)

---

## Files Reference

| File | Purpose |
|------|---------|
| `draft_pick_summaries.json` | Clean JSON from lineage step |
| `draft_picks.json` | DLG/WNBA picks only (not NBA) |
| `migrations/archive/004_draft_pick_tables.sql` | Schema for both tables (summaries + ownership) |
| `draft_pick_summaries.inline_script.ts` | Import script for summaries |

---

## Appendix: Sample Data

### Simple Case (2018 ATL)
```json
{
  "team_id": 1610612737,
  "draft_year": 2018,
  "first_round": "Own | Has HOU(81) (via LAC(78)); Has MIN(19)",
  "second_round": "Own"
}
```

### Complex Case (2027 OKC)
```json
{
  "team_id": 1610612760,
  "draft_year": 2027,
  "first_round": "Own or to LAC(152) | May have DEN(53) or to LAC(152); may have LAC(152); may have PHI(16); may have SAS(287) (via SAC(236))",
  "second_round": "Own or to SAS(47) (via UTA(30)) or to MIA(124) (via SAS(47) via UTA(30)) or to NYK(187) or to NYK(188) | May have CHA(287) (via SAC(235) via SAS(59) via ATL(41) via NYK(28)); may have HOU(19) (via DET(10)) or to SAS(47) (via UTA(30)) or to MIA(124) (via SAS(47) via UTA(30)) or to NYK(187) or to NYK(188); ..."
}
```

### All Endnote References
```bash
# Extract unique endnote refs
grep -o '([0-9]\+)' draft_pick_summaries.json | sort -t'(' -k2 -n | uniq
# Returns 325 unique references from (1) to (370)
```
