I'm attaching a video of a UI. Act as a **UX interaction analyst** (mechanics + state), not a designer.

Your job: extract the **interaction patterns, state machines, and information flow** from what is directly observable in the video.

## What to Ignore (unless it encodes state)
Do **not** give opinions about visual quality.

Generally ignore:
- Colors, fonts, shadows, gradients
- “Modern/clean/premium” judgments
- Component/library commentary

Exception (important): you **may** mention visual properties **only when they function as state signifiers or data encodings**, e.g.
- gray vs blue bars meaning *total vs subset*
- a mask/dim region meaning *out-of-selection*
- an animation pattern meaning *opening vs closing* state

## What I Care About
- Trigger → result mechanics (click/hover/scroll/drag/keyboard)
- States/modes and transitions between them
- Persistence rules (does it “lock” or is it transient?)
- Cancellation rules (what ends the state? mouse leave, escape, click outside, timeouts)
- Replacement rules (does A replace B instantly? does it close then open? can multiple be open?)
- Compound interactions (can filters combine? intersection/union? precedence?)
- Spatial rules (fixed/sticky/scroll; anchoring; overlay layering)
- Context propagation (what updates elsewhere when something changes here?)
- Progressive disclosure (what’s hidden until intent is expressed?)
- Quantitative encoding rules (parts-to-whole, totals context, axis re-scaling)

## Required Output (Markdown)

### 0. Scope Notes (Required)
- What is clearly shown in the clip
- What is **not shown** (but might exist)
- If anything is uncertain, label it explicitly as **(uncertain)** or **(implied, not observed)**

---

### 1. Interaction Inventory (Required)
A table of **every distinct interaction** you observe.

Include columns:
- **Target / Region** (what the user interacts with)
- **Action** (hover enter/hover exit/click/drag/scroll/etc.)
- **Trigger Surface** (row text? icon? chart body? brush handle? empty space?)
- **Persistence** (transient / sticky / locked)
- **Cancel / Exit Condition** (mouse leave, click outside, escape, etc.)
- **Observed Result** (what changes + where)
- **Notes** (e.g., “replaces existing overlay”, “no click-to-lock observed”)

Be exhaustive.

---

### 2. State Machine(s) (Required)
Describe the modes/states the UI can be in and transitions between them.

Provide:
1) **ASCII state machine** (required) using:
```
STATE_A --[user action]--> STATE_B
```

2) If helpful, a **Mermaid diagram** (optional).

When relevant, model:
- opening / open / swapping / closing (for overlays)
- idle / filtered / compound-filtered / updating-during-drag (for dashboards)

---

### 3. Spatial Layout Rules (Required)
Document the spatial UI model:
- What scrolls vs what is fixed/sticky
- Z-index / layering (base content vs interaction targets vs overlays)
- Anchoring rules (e.g., “overlay centered to icon X, offset below”)
- Any masking/dimming rules (what gets dimmed and why)

---

### 4. Context Propagation (Required)
Explain how state changes propagate across regions:
- Immediate vs lazy (hover preview vs click commit)
- Bidirectional vs unidirectional updates
- Replace vs merge behaviors

If this is a “coordinated multiple views” dashboard, explicitly state:
- which view acts as an anchor/driver (if any)
- whether updates are continuous during drag (frame-by-frame) or only on release

---

### 5. Progressive Disclosure (Required)
Explain the hierarchy of reveal:
- What is visible by default
- What appears only on hover/focus
- What requires click/commit/navigation

If the UI discloses **correlations** (not hidden UI), say so.

---

### 6. Quantitative / Visual Encoding Rules (Required when charts exist)
Only include what is observable:
- Parts-to-whole encodings (e.g., bar-within-a-bar)
- Total-context rules (what does the “total” represent? global total vs filtered total)
- Axis scale behavior (fixed vs re-normalized)

---

### 7. Key UX Patterns (Required)
Name the patterns you observe (e.g., master-detail, hovercards, faceted filtering, brushing & linking, dynamic queries, command palette).
For each: 1–3 sentences describing how it manifests here.

## Do NOT
- Suggest improvements
- Recommend frameworks/tech
- Invent interactions not directly visible
- Describe visual styling unless it encodes state (see exception above)

## Bar for Completion
If you see 15 distinct targets, document all 15. If an interaction is absent (e.g., no click-to-lock), explicitly note the absence as an observation.