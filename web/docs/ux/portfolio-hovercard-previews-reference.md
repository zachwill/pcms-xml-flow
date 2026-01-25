# Portfolio Page (Social Hovercards + Feed Filters) — UX Reference Analysis

> A portfolio homepage where hovering social icons summons **rich preview cards** that animate in/out and **replace each other** on hover, revealing platform-specific “proof” (stats, activity, media) without navigation.

## Why This Reference Exists

- Documents **ephemeral master→detail overlays** triggered by hover (preview without route change).
- Captures an **overlay priority / replace-on-hover** model, including a distinct **swap transition**.
- Records **motion as state signaling** (animate-in vs animate-out; different entry/exit behavior).
- Records **platform mimicry**: the preview card content/layout signals the linked platform context.
- Notes progressive disclosure from **glanceable identity → proof snapshot → deep dive (external)**.

---

## 1. Interaction & Visual-Physics Inventory (Trigger → Result)

> Notes:
> - Some feed-filter interactions are described as implicit / not activated in the clip; these are labeled.
> - Visual properties are only documented when they serve as **state signifiers** (e.g., animation behavior indicating open/close/swap), not as aesthetic commentary.

| Trigger | Action | Observed interaction logic (incl. motion/state signifiers) |
| :--- | :--- | :--- |
| Social icon | Hover (enter) | Preview card animates in as a scale-up from the icon/anchor point using a spring/overshoot curve (described as “spring-loaded scale”). |
| Social icon | Hover (exit) / mouse leave | Preview card animates out faster than it animates in (described as “rapid decay”: “enter with personality, exit with urgency”). |
| Hover moves from Social A → Social B | Hover (switch) | Existing preview is replaced by the next preview without returning to base first (described as a “mode switch” / swap transition rather than a fresh open). |
| Twitter link | Hover state change | Preview card adopts Twitter-like UI conventions (e.g., follow/verified affordances), acting as a portal-like snapshot of that platform. |
| GitHub link | Hover state change | Preview card renders a contribution heatmap (static link → data visualization snapshot). |
| LinkedIn link | Hover state change | Preview card contains an autoplaying video/GIF, escalating the preview from static info to rich media. |
| Preview card internal elements (e.g., Follow button) | Hover | Secondary hover targets inside the card show local hover affordance; no main-page state change described. |
| Viewport | Scroll | Standard document scroll; header/pinned region moves out of frame, and spacing functions as a section boundary between bio/pinned and feed. |
| Feed filters (Articles, Code, etc.) | Hover | Visual highlight affordance check. |
| Feed filters (Articles, Code, etc.) | Click (implied) | Intended to filter the list below by facet (not activated in clip; described as implied). |

---

## 2. State Machine: Hovercard States + Motion States

### Pattern
Hover previews behave as a **single overlay slot** controlled by hover anchors. States are defined not only by which preview is active, but by whether the card is **opening**, **open**, **swapping**, or **closing**.

### State Machine (as described)

```
IDLE
  --[Hover Start on Social_X]--> ANIMATING_IN_X

ANIMATING_IN_X
  --[Spring settle]--> OPEN_X

OPEN_X
  --[Hover Social_Y]--> SWAP_X_TO_Y

SWAP_X_TO_Y
  --[Replace/Morph]--> OPEN_Y

OPEN_X
  --[Hover Exit / Mouse Leave social area]--> ANIMATING_OUT_X

ANIMATING_OUT_X
  --[Fast fade/scale down]--> IDLE
```

### Key Insight
The analysis highlights `SWAP_X_TO_Y` as critical: switching targets feels like changing modes in-place (replace) rather than closing one interaction and starting another.

---

## 3. Spatial Layout Rules (Layers + Anchoring)

### Layering (as described)
1. **Base layer:** document flow (bio, pinned projects, feed)
2. **Interaction layer:** hover targets (social icons; filter facets)
3. **Overlay layer:** preview cards rendered above the base flow

### Anchoring rules (as described)
- Preview card is anchored to the social icon row:
  - horizontally centered relative to the trigger icon
  - vertically offset below the icon row to avoid covering the icons

Expressed as rules (as provided in analysis):
- `Card_Center_X = Icon_Center_X`
- `Card_Top_Y = Icon_Bottom_Y + Padding`

### Scroll behavior (as described)
- Header/social row are flow-based (move out of viewport during scroll).
- Filter bar is described as not sticky in the observed view.

---

## 4. Context Propagation: Data + Identity

### Hover-driven propagation (as described)
- Hovering a social icon immediately drives the overlay into a platform-specific preview state (no click-to-commit required).

### Platform mimicry (as described)
- Context is communicated not only through data (stats/graphs/media) but through platform-recognizable UI conventions inside the card.

### Non-propagation from overlay internals (as described)
- Hovering elements inside the preview card (e.g., a Follow button) is described as local affordance; it does not change the main page state.

---

## 5. Progressive Disclosure: Glance → Proof → Deep Dive

### Pattern (as described)
1. **Glanceable layer:** name/title + social icons (who/where)
2. **Proof layer (hover):** hovercards reveal platform-relevant proof (followers, activity visualization, speaking/pro presence)
3. **Deep dive (click):** external profile (not shown; described as implied)

### Key Insight
The payoff is described as high relative to the interaction cost: hover yields dense evidence without navigation.

---

## 6. Key UX Patterns

- **Rich link previews:** hovercards replace tooltips with full-fidelity preview cards.
- **Ephemeral master-detail:** icons act as masters; hovercard is a temporary detail view.
- **Faceted navigation (implied):** filter bar scopes feed content without refresh.
- **Motion-as-feedback:** distinct animate-in vs animate-out behaviors signal open vs dismiss urgency.

---

## References

- Source: Gemini UX analyses of a portfolio page clip focusing on social icon hover previews and feed filtering.
- Related: `web/prompts/DOCS.md`, `web/docs/ux/AGENTS.md`
