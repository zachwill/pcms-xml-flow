# Dense UI Principles (Windmill)

Dense UI is a **reading order**, not a layout style. The goal is to sequence information so users move from **"what world am I in?" → "what's wrong?" → "what do I do?"** without friction.

This document pulls together the core principles plus Windmill-specific patterns distilled from `f/ripcity/AGENTS.md` and the original notes below.

---

## The Sequence

Every dense interface follows this path:

```
ORIENT → NARROW → INVESTIGATE → ACT
```

| Stage | What It Does | Windmill Pattern |
|-------|--------------|------------------|
| **Orient** | 3-5 KPIs to establish context | Header cards with totals, averages, counts |
| **Narrow** | Filters, segments to focus attention | Summary cards, segmented leader lists |
| **Investigate** | Segmented data tables with context | Main table with sticky headers, percentile color |
| **Act** | Detail panels, expandable views | Trait badges, comp cards, detail panels |

Design for two modes:

- **Scanning**: "What's on fire?" — Orient must work in 5 seconds (segment headers, color encoding, KPIs)
- **Investigating**: "Why is this happening?" — Narrow through Act without friction

Summary by default, detail on click. No page transitions — investigation without losing place.

---

## Choose Layout by What Matters

| When... | Use... |
|---------|--------|
| Entities are comparable, job is to triage/monitor | **Table** |
| Position and adjacency matter | **Spatial** (floor plan, map, topology) |
| Sequence and simultaneity matter | **Temporal** (timeline, Gantt, calendar) |
| Connections are the insight | **Relational** (graph, network diagram) |
| User is constructing something | **Canvas** (grid editor, drag-and-drop) |

The rest of the principles apply regardless of layout.

---

## Segment by Decision Structure

Segment by how users actually sort things when deciding what to do next (not alphabetically or by DB schema).

Examples:

- Critical / Elevated / Stable / New
- Action Required / Watch List / Performing / Under Evaluation
- Blocked / At Risk / On Track / Complete

The segments **are** the summary. Users should know the shape of their problem from segment headers + counts before examining any individual item.

Different roles may need different segmentations of the same data — organize around the user's mental model, not the domain structure.

---

## Every Number Needs a Neighbor

A number alone ("82%") forces users to ask "is this good?" — that question breaks flow.

Provide one or more neighbors:

- **Percentiles**: "82% (25th %ile)"
- **Baselines**: group average, benchmark, target
- **Deltas**: "+5% YoY" or "vs. plan: -12%"
- **Color encoding**: maps to operational meaning

### Percentile Color Encoding

Use a consistent scale across scripts. Some scripts use 0–1 decimal percentiles, others use 0–100 integer percentiles. Adjust thresholds accordingly.

```typescript
// 0–1 decimal percentiles
const getPctlColor = (pctl: number | null, reverse = false) => {
  if (pctl === null || pctl === undefined) return 'text-slate-400';
  const p = reverse ? (1 - Number(pctl)) : Number(pctl);
  if (p >= 0.90) return 'text-emerald-700 font-bold';
  if (p >= 0.75) return 'text-emerald-600 font-semibold';
  if (p >= 0.60) return 'text-emerald-600';
  if (p >= 0.40) return 'text-slate-600';
  if (p >= 0.25) return 'text-amber-600';
  return 'text-rose-600 font-medium';
};

// 0–100 integer percentiles
const getPctlColor = (pctl: number | null) => {
  if (pctl === null || pctl === undefined) return 'text-slate-400';
  if (pctl >= 90) return 'text-emerald-700 font-bold';
  if (pctl >= 75) return 'text-emerald-600 font-semibold';
  if (pctl >= 60) return 'text-emerald-500';
  if (pctl >= 40) return 'text-slate-600';
  if (pctl >= 25) return 'text-amber-600';
  return 'text-rose-600 font-medium';
};
```

---

## Detail on Demand

When users click to investigate, where detail appears matters.

**Windmill constraint (static Tailwind HTML):** modals and side panels are not available in the plain HTML renderer. The only reliable interaction pattern is **inline expansion** (or separate pages/scripts). Design dense UIs accordingly.

Preferred options in Windmill scripts:

- **Inline expansion**: preserves position, limits depth — good for quick checks
- **Jump links / anchors**: keep the user in the same page while revealing detail
- **Separate scripts or routes**: for complex workflows that require dedicated space

If you reference modals/side panels, note that they require a full app context outside the static HTML renderer.

---

## Reduce Re-checking

Ensure users can trust the data:

- **Freshness**: "Data as of Nov 15, 2:00 PM"
- **Definitions**: tooltips, methodology expanders
- **Shareable URLs**: encode filter state

---

## Windmill Layout Patterns

### Header Block (Orient)

Always include:

- **Title** with season/date context
- **3-4 KPI cards** with large numeric values and small labels
- **Optional legend** for color encoding

```typescript
<div class="kpi-grid">
  <div class="kpi-card">
    <div class="kpi-value">${value}</div>
    <div class="kpi-label">Label</div>
  </div>
</div>
```

### Summary Cards (Narrow)

Show top/bottom performers before the full table:

- Leader cards with medal emojis (🥇🥈🥉) or rank badges
- Highlight the primary team/entity with an accent
- Cap lists at 3-4 items

```typescript
<div class="leader-card bg-white rounded border border-slate-300 shadow-sm p-4">
  <h3 class="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-3">
    🎯 Most Challenges / Game
  </h3>
  ${topItems.map(r => `
    <div class="flex items-center justify-between py-1">
      <span class="text-base">${getMedalEmoji(r.rank)}</span>
      <span class="font-bold ${r.team === 'POR' ? 'text-indigo-700' : ''}">${r.team}</span>
      <span class="font-mono font-bold tabular-nums">${r.value}</span>
    </div>
  `).join('')}
</div>
```

### Table Design (Investigate)

- **Super headers**: group related columns
- **Sub headers**: individual column labels
- **Sticky headers**: `position: sticky; top: 0; z-index: 20;`
- **Alternating rows**: `bg-white` / `bg-slate-50`
- **Entity highlighting**: accent the primary team/entity

```typescript
<thead class="sticky top-0 z-20 shadow-sm">
  <tr>
    <th class="th-super text-center" colspan="5">Bio & Profile</th>
    <th class="th-super text-center" colspan="4">Volume</th>
  </tr>
  <tr>
    <th class="th-sub text-center border-r border-slate-300">Age</th>
    <th class="th-sub text-center border-r border-slate-100">HT</th>
  </tr>
</thead>
```

### Comp Cards (Narrow + Act)

Use compact cards for comparisons:

- Rank badge, distance score
- Trait badges for standout percentiles
- Match profile for similarity context

```typescript
<div class="bg-white rounded border border-slate-300 p-3">
  <div class="flex justify-between items-start mb-2">
    <span class="bg-indigo-600 text-white text-[10px] font-bold px-1.5 py-0.5 rounded">#${rank}</span>
    <div class="flex gap-1">
      ${badges.map(b => `<span class="text-[9px] font-bold px-1 rounded-sm border ${b.c}">${b.l}</span>`).join('')}
    </div>
  </div>
  <div class="font-bold text-slate-900 text-sm truncate">${player}</div>
  <div class="text-[10px] text-slate-500 font-mono">${season} · ${team}</div>
</div>
```

---

## Review Heuristics

1. Can I answer "what's the shape of the problem?" in 5 seconds?
2. Can I tell if each number is good or bad?
3. Can I go from summary to detail without losing my place?
4. Do I trust this data?

If any answer is no, the interface has work to do.

---

## Reference Implementations (Inside This Repo)

- `f/ripcity/AGENTS.md` (dense UI guide + patterns)
- `f/ripcity/ncaa_comps.ts` (comp cards, trait badges)
- `f/ripcity/gleague_comps.ts` (comp cards, trait badges)
- `f/ripcity/challenges_for_jacob.ts` (leader cards, medal emojis)
- `f/ripcity/sean_epm_rankings.ts` (bar cells, percentile coloring)

These scripts provide minimal reproducible examples for the patterns described above.
