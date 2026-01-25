# Cross-Filtering Data Dashboard (hamilton.mp4) — UX Reference Analysis

> A coordinated-multiple-views (CMV) dashboard where a **time brush** defines the active data universe and **row-hover cross-filters** provide transient, high-frequency linked updates across all charts.

## Why This Reference Exists

- Documents **brushing + linking** as a primary “data interrogation” interaction loop.
- Captures a **compound filter model** where a persistent brush and a transient hover intersect.
- Records a **foreground/background (subset within context)** visualization rule that preserves scale awareness during filtering.
- Notes **continuous (frame-by-frame) updates** during brush movement (dynamic queries).

---

## 1. Interaction & Visual-Physics Inventory (Trigger → Result)

| Trigger area | Action | Observed interaction logic (incl. state signifiers) |
| :--- | :--- | :--- |
| Categorical lists (e.g., Neighborhood, Responsible Agency) | Hover row text | Cross-filter is triggered by hovering the list row/text itself (not by hovering bars in charts in this clip). Hover injects the category as a transient global filter affecting all other charts. |
| Categorical lists | Hover exit (mouse leaves row) | Hover filter is strictly transient (no lock). As soon as the mouse leaves the row, the blue subset bars vanish and views return to the non-hover state for the current context. |
| Time series chart (anchor chart, top-left) | Click-drag empty space | Creates a brush selection window (time range). |
| Time series brush | Drag body | Pans the entire selected time window horizontally (moves range). |
| Time series brush | Drag left/right edges | Resizes brush duration via distinct handles/edges. |
| Time series brush | Any drag/move | Uses a masking metaphor: selected range remains bright/white while unselected regions are dimmed/gray. |
| Linked bar/list charts | Passive update (linked) | Uses a bar-within-a-bar encoding: gray background bar represents the current context total; blue foreground bar represents the active selection/subset. |

---

## 2. State Machine: The “Current Query Set” Loop

### Pattern
The UI behaves like a visual query generator. The visible state corresponds to a current query set, composed of:
- a persistent time constraint (brush)
- a transient categorical constraint (hover)

### State Machine (hover + brush)

```mermaid
graph TD
    ALL_DATA --[Create Brush]--> TIME_FILTERED
    TIME_FILTERED --[Resize/Move Brush]--> TIME_FILTERED_UPDATING
    TIME_FILTERED_UPDATING --[Release Mouse]--> TIME_FILTERED

    TIME_FILTERED --[Hover Category Row]--> COMPOUND_FILTER (TIME ∩ CATEGORY)
    COMPOUND_FILTER --[Mouse Leave Row]--> TIME_FILTERED

    COMPOUND_FILTER --[Move/Resize Brush]--> COMPOUND_UPDATING
    COMPOUND_UPDATING --[Release Mouse]--> COMPOUND_FILTER
```

### Key Insight
Compound state is produced by **intersection**: the time brush defines the base universe; hover refines within that universe. The hover constraint is transient and cancels immediately on mouse leave.

---

## 3. Spatial Layout & Information Architecture

### Pattern
A grid of charts (“coordinated multiple views”) shares one underlying data model. Each view provides a different slice, and all views listen to the current query state.

### Dimensional segmentation (as observed in the clip)
- **Top left:** temporal dimension (“When”) via time series + brush.
- **Top middle:** spatial/nominal dimension (“Where” — neighborhoods).
- **Bottom left:** nominal dimension (“Who” — agencies).
- **Bottom middle:** nominal dimension (“What” — request details).
- **Right column:** quantitative metadata (e.g., status/latitude).

### Anchor chart
The time series chart is the only chart shown supporting brushing in the clip, making it the primary driver of the rest of the dashboard.

---

## 4. Context Propagation: Foreground/Background Encoding + Scale Management

### Pattern
The dashboard preserves context while filtering by keeping a stable “total” reference bar behind the active selection.

### Hierarchy of totals (as observed)
- **Time brush updates the gray bars**: the gray background bars represent the **time-filtered total** (the current context), not a constant all-time global total.
- **Hover updates the blue bars**: hovering a category filters the blue foreground bars *within* the current gray-bar context.

Expressed as a hierarchy:

```
RAW DATA
  -> TIME BRUSH (defines current context)
      -> GRAY BAR (context total)
          -> HOVER CATEGORY (transient refinement)
              -> BLUE BAR (active selection)
```

### Axes/scales (as observed)
Row-chart x-axis scales appear to re-normalize to the maximum of the current view (time-filtered context), so bars continue to utilize available horizontal space after the brush changes.

### Key Insight
The gray bars provide a denominator that survives transient filtering, while still reflecting the current time context. This keeps parts-to-whole reasoning available without requiring numeric reading.

---

## 5. Progressive Disclosure

### Pattern
UI controls are not hidden; instead, interaction progressively discloses **relationships/correlations**.

### Observations
- All views are visible simultaneously; progressive disclosure is applied to correlations, not menus.
- Hover reveals how distributions shift across dimensions (e.g., which agencies are implicated by a hovered neighborhood) while preserving time context.

---

## 6. Key UX Patterns

1. **Brushing and linking**
   - Brushing: define a subset via time-range selection.
   - Linking: all other views update to reflect that subset.
2. **Dynamic queries / continuous feedback**
   - Linked views update continuously during brush movement (frame-by-frame), producing a “dancing” effect.
3. **Relative visualization (bar-within-a-bar)**
   - Foreground subset displayed within a background context total.
4. **Transient cross-filter hover**
   - Category filters are invoked by hover only (no click-to-lock observed in the clip).

---

## 7. “Feel” (As Observed/Described)

- Described as **fluid precision**: low interaction friction, continuous updates, and minimal easing.
- Motion appears as fast, near-linear interpolation (bars grow/shrink in close correlation with brush pixel movement).
- The persistent gray context bars are described as reducing loss of scale/context during filtering (mitigating change blindness).

---

## References

- Source: Observational notes derived from close analysis of `hamilton.mp4`.
- Related: `web/prompts/DOCS.md`, `web/docs/ux/AGENTS.md`
