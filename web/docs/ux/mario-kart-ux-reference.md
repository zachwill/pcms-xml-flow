# Mario Kart ("Lit" vs "Sux") — UX Reference Analysis

> A side-by-side comparison of the same kart racer where the “Lit” version is described as a **high-fidelity reactive surface** (more intermediate states + more frequent feedback), while the “Sux” version is described as a **trigger system / static container** (shallower state + fewer signifiers).

## Why This Reference Exists

- Captures how **interaction density** (number of meaningful intermediate states) changes the moment-to-moment experience.
- Captures how **feedback frequency** (how continuously state is signaled) makes inputs legible without relying on HUD attention.
- Records differences in **spatial rules** (surface-relative “down”, camera behavior, and what geometry counts as drivable).
- Documents progressive disclosure in **charge / reveal** mechanics (drift tiers; item roll → reveal).

---

## 1. Core Contrast: Reactive System vs Trigger System (As Described)

### Pattern
The “Lit” version is described as keeping the player in a constant feedback dialogue with the physics/world state. The “Sux” version is described as collapsing interactions into fewer binary/triggered outcomes.

### Observed Consequence (as described)
- **Lit:** Track + kart respond continuously to subtle inputs and surface changes (camber/elevation/anti-gravity strips), producing more moment-to-moment state updates.
- **Sux:** Track is described as functionally flatter; verticality and transitions are more often binary (e.g., ground vs airborne), producing fewer meaningful intermediate updates.

### Key Insight
Many “feel” differences can be described mechanically as: **more intermediate states + more frequent state signifiers**.

---

## 2. Interaction Inventory (Trigger → State Change)

| Target / Trigger | Action | Observed state change (Left — “Good / Lit”) | Observed state change (Right — “Bad / Sux”) |
| :--- | :--- | :--- | :--- |
| Track surface | Continuous | **Surface participation:** kart reacts to camber, elevation, and anti-gravity strips. | **Surface passivity:** kart motion described as closer to a flat plane; verticality is more visual-only. |
| Drift trigger | Hold L/R + steer | **Multi-stage accumulation:** sparks progress through tiers (Blue → Orange → Pink) functioning as a progress indicator for stored boost energy. | **Binary / reduced stage:** single spark type or limited progression; lower feedback frequency. |
| Jump / ramp | Exit surface | **Active stunt state:** timing-dependent stunt; success yields a post-land boost state. | **Passive transition:** simplified airborne handling; resolution described as more automatic. |
| Collision (wall) | Intersect mesh | **Elastic deflection:** momentum described as redirected based on collision angle. | **Momentum kill:** near-instant stop or rigid slide with less energy transfer. |
| Item box | Collision | **Slot machine loop:** HUD item slot enters a rolling state before settling on an active item. | **More immediate assignment:** shorter roll/anticipation loop. |

---

## 3. State Machines: “Feel” as Intermediate States

### 3.1 Drift — “Lit” (as described)

```
IDLE
  --[Accelerate]--> DRIVING

DRIVING
  --[Hop]--> MOMENTUM_SHIFT
MOMENTUM_SHIFT
  --[Hold Direction]--> DRIFT_LV1 (Blue)
DRIFT_LV1
  --[Continue Hold]--> DRIFT_LV2 (Orange)
DRIFT_LV2
  --[Continue Hold]--> DRIFT_LV3 (Pink)

DRIFT_LVx
  --[Release]--> TURBO_BOOST (magnitude proportional to level)
```

#### Key Insight
The drift system is described as a ladder of intermediate “charging” states, with continuous signifiers that let the player decide when to cash out.

### 3.2 Drift — “Sux” (as described)

```
IDLE
  --[Accelerate]--> DRIVING

DRIVING
  --[Direction]--> DRIFT_LV1
DRIFT_LV1
  --[Release]--> SMALL_BOOST
```

#### Key Insight
The drift loop is described as shallower (fewer intermediate states), reducing both granularity and the amount of readable in-the-moment feedback.

### 3.3 Baseline Kart State Machine (from the earlier analysis)

```
IDLE
  --[Accelerate]--> DRIVING

DRIVING
  --[Hop + Direction]--> DRIFT_STAGE_1
DRIFT_STAGE_1
  --[Hold Direction]--> DRIFT_STAGE_2
DRIFT_STAGE_2
  --[Release]--> TURBO_BOOST

DRIVING
  --[Collision with Hazard]--> STUN_STATE
STUN_STATE
  --[Timer Expire]--> DRIVING

DRIVING
  --[Edge Departure]--> AIRBORNE_STATE
AIRBORNE_STATE
  --[Input: Shake/Button]--> STUNT_ANIMATION
STUNT_ANIMATION
  --[Touchdown]--> LANDING_BOOST
```

#### Key Insight
Across both analyses, the “Lit” version is described as having additional intermediate states (notably an extra drift tier), while the “Sux” version is described as capping earlier.

---

## 4. Spatial Layout Rules (World as Spatial UI)

### Camera anchoring (as described)
- **Lit:** camera is described as context-aware; it tilts/rotates to match the surface-relative “down” vector during anti-gravity. The world orientation changes around the player.
- **Sux:** camera is described as fixed-horizon; follows position but resists Z-axis rotation.

### Layering / drivable geometry (as described)
- **Lit:** the “primary layer” (track) has variable depth; can become wall/ceiling (drivable).
- **Sux:** the “primary layer” is described as a strictly horizontal ribbon.

### Key Insight
Camera orientation rules and “what counts as drivable” define the effective interaction layer more than the raw visuals do.

---

## 5. Context Propagation (World State → Player Understanding)

### Mechanisms (as described)
- **Immediate feedback (“proprioception”):** rapid feedback is described as occurring on surface change (e.g., visual screen shake; rumble is mentioned in the analysis).
- **Spatial signifiers:** anti-gravity state is described as signified by a wheel/vehicle visual change (e.g., “blue wheels”).
- **Rule signaling via signifiers:** the analysis states that anti-gravity can change collision outcomes (e.g., bumping others yields a boost rather than a penalty).
- **Lazy disclosure via commitment phase:** item identity is disclosed only after the roll state completes.

### Key Insight
State signifiers are not only status indicators; they can also communicate that the underlying rule set has changed.

---

## 6. Progressive Disclosure

### Observations (as described)
- **Item reveal:** item status is hidden until randomization completes (rolling → reveal).
- **Risk/reward visualization:** spark color discloses an unseen “power” variable (boost tier) without showing a numeric meter.
- **Mechanic discovery via environment:** environmental cues can disclose optional paths/shortcuts (e.g., dirt patches requiring a mushroom); the “Sux” version is described as making these more binary or walled-off.

### Key Insight
Progressive disclosure here is implemented as: *commit to an action → receive a staged reveal of what you earned/unlocked*.

---

## 7. Key UX Patterns (as described)

- **Continuous feedback loop:** the “Lit” version is described as producing frame-by-frame feedback via effects like sparks, wind streaks, and FOV manipulation.
- **“Juice” pattern:** high-frequency responses to low-frequency inputs (a simple turn produces multiple concurrent cues).
- **Master-detail navigation:** minimap (global state) + near-field view (immediate hazards). The “Lit” version is described as ensuring these views do not contradict the underlying physics logic.

---

## References

- Source: Two Gemini analyses of a side-by-side video showing a “good (Lit)” vs “bad (Sux)” version of the same Mario Kart gameplay.
- Related: `web/prompts/DOCS.md`, `web/docs/ux/AGENTS.md`
