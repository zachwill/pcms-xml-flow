# The Ferrari Luce Interface: Complete Technical Reference

---

## 0 — Mental Model: The "Phygital Cockpit"

Before any detail, internalize five design patterns that govern every decision in this system:

1. **Tactile hardware, digital state.** Physical *input* controls are almost always momentary — sticks spring back to center, toggles snap to neutral, rotaries click between detents. The controls produce impulses (events). State lives in software. Input hardware never "holds" a position for the system.

2. **Hybrid mechanical-digital instruments.** The most critical *output* instruments combine physical mechanical elements (motor-driven needles, clock hands) with digital OLED faces beneath them. The mechanical layer provides visceral, analog legibility; the digital layer provides mode-colored overlays, numerics, and contextual graphics. This duality is a core design signature — not every display is a screen.

3. **High-contrast digital feedback on OLED black.** Every screen assumes a pure-black background that vanishes into its bezel. Visual elements are sparse, typographically strict, and color-coded by meaning — not decoration.

4. **Strict safety gating.** Actions are validated against preconditions before execution. Invalid inputs are silently ignored or produce a brief warning. The system never errors, never crashes, never enters an ambiguous state.

5. **Layered state machines.** The cockpit runs many concurrent state machines (gear, drive mode, powertrain mode, torque control, launch sequence, multigraph chrono, etc.) that influence each other through well-defined couplings. No module is truly independent.

A key consequence: **every physical input maps to a named event, every event is validated against the current state, and every valid transition produces multi-modal feedback** (visual change + physical sensation + implied audio). And the most important outputs are expressed physically — a needle, a hand — even in a fully electric car.

---

## 1 — Global Design System

### 1.1 Typography

| Role | Name | Style | Usage |
|------|------|-------|-------|
| Heritage Serif | Bodoni-like, high-contrast | ALL CAPS, large weight | Static labels ("Ferrari", "Luce"), gear letters, brand moments |
| Telemetry Mono | Space Mono-like, fixed-width | Tabular numerals, technical | All live data: speed, range, temperature, power, timers, graph axes |

**ASCII strategy:** Heritage = ALL CAPS or bold variants. Telemetry = fixed-width characters, always.

### 1.2 Color Palette

| Name | Hex | Terminal | Semantic Role |
|------|-----|---------|---------------|
| OLED Black | `#000000` | Default | Background — always pure black to merge with bezels |
| Giallo Modena | `#FCD116` | `\033[93m` | Primary active: tachometer arc, Prancing Horse, normal-state highlights, key surge |
| Rosso Corsa | `#FF2800` | `\033[91m` | Limit / performance / warning: redline, Sport mode, Launch Control |
| Verde Signal | `#00FF00` | `\033[92m` | Efficiency: Range mode, battery health, regen indicators |
| Grigio | `#666666` | `\033[90m` | Inactive: disabled elements, ghost values, bezels, faded neighbors |

Colors are *semantic, not decorative.* The mode system (Section 5.3) shifts accent colors globally — layout stays constant, palette shifts.

### 1.3 Motion Rules

| Context | Motion Type | Description |
|---------|-------------|-------------|
| Key dock boot | Yellow surge | Giallo Modena radiates outward from the key dock point across all displays sequentially. |
| Gear changes | Drum scroll | Letters slide through a viewport; intermediate gears pass as ghosts. Never an instant swap. |
| Mode changes | Color migration | Accent color shifts + label updates. Layout is constant. No page transitions. |
| Speed / power | Continuous arc fill + needle | Ring fills/drains smoothly. Mechanical needle sweeps continuously. Regen dips counter-clockwise into a "charge zone." |
| Launch sequence | Dramatic palette override | Displays darken, orange overlay, checklist appears, multigraph auto-switches to 5s chrono, white flash (100ms) on launch. |
| Toggle feedback | Transient HUD | Brief on-screen indicator (slider, icon) appears and fades after ~2s. |

### 1.4 Input Semantics

Physical controls produce discrete events with timing metadata:

| Hardware Type | Events Produced | Duration Matters? |
|---------------|----------------|-------------------|
| Physical key dock | `DOCK`, `UNDOCK` | No — binary insertion/removal |
| Momentary stick (gear) | `TAP`, `HOLD` | Yes — tap < 0.5s vs hold ≥ 0.5s changes meaning |
| Spring toggle (climate) | `UP`, `DOWN` | No — each actuation is one step |
| Rotary detent (Manettino) | `ROTATE_CW`, `ROTATE_CCW` | No — each click is one position |
| Mechanical toggle (right dial) | `TOGGLE` | No — each actuation cycles one mode |
| Paddle (torque) | `PULL` | No — each pull is one torque level step |
| Overhead pull (launch) | `PULL` | No — single deliberate actuation |
| Button (P, multigraph, SOS) | `PRESS`, `LONG_PRESS` | Yes — stopwatch reset requires 2s hold |

---

## 2 — System Architecture

### 2.1 Component Tree

```
PhysicalKeyDock
├── Emits KEY_DOCK → boots entire system
├── Yellow surge animation radiates across all displays
└── Mechanically unlocks shifter

CockpitRoot
├── DriverBinnacle (3-dial, steering-column-fixed)
│   ├── LeftDial (Power — linked to E-Manettino)
│   ├── CenterDial (Speed + Battery — mechanical needle + digital face + torque meter)
│   └── RightDial (Driver performance — 7 modes, toggle-cycled)
├── GearSelectorModule
│   ├── MiniDisplay (drum viewport)
│   └── JoystickInput (momentary + top P button)
├── SteeringWheelControls
│   ├── Manettino (left pod — dynamics rotary, 5 detents)
│   ├── EManettinoPod (right pod — powertrain rotary, 3 positions + driver dial toggle)
│   └── TorqueControlPaddles (column-fixed blades, torque level stepping)
├── CenterBridge
│   ├── ComfortConsole (windows / locks / frunk)
│   └── AuxControls (Park Assist / Lift)
├── OverheadPanel
│   ├── LaunchPull (physical pull mechanism)
│   ├── LightsToggle
│   ├── DefrostToggle
│   └── SOSButton
├── ControlPanel (articulating, shared driver/co-pilot)
│   ├── ModeButtons (3 physical: Climate / Settings / Media + Off)
│   ├── Touchscreen (OLED — deep settings, media, navigation)
│   ├── ClimateControls (physical: temp, fan, seat heat/vent)
│   └── Multigraph (hybrid mechanical-digital round instrument)
│       ├── ModeButton (cycle: Clock / Stopwatch / Compass)
│       └── ActionButton (stopwatch control)
└── RearPassengerDisplay
    ├── Real-time drive data mirror
    └── Rear climate controls
```

### 2.2 State Management Pattern

Use a single authoritative `CarState` object updated through a pure reducer:

```
nextState = reduce(previousState, event, timestamp_ms)
```

All precondition checks (speed lockouts, mode prerequisites, sequence validation) live inside the reducer. UI components are derived views:

```
binnacleTheme       = deriveBinnacleTheme(state)
gearDisplay         = deriveGearDisplay(state)
launchOverlay       = deriveLaunchOverlay(state)
controlPanelLabels  = deriveControlPanelLabels(state)
multigraphMode      = deriveMultigraphMode(state)
```

This guarantees that the UI can never desync from safety logic.

### 2.3 Type Definitions

```ts
// Gear — automatic only. No manual gear ratios (this is an EV).
type Gear = "P" | "R" | "N" | "D";

// Torque — paddles control torque delivery levels, not gears
type TorqueLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
type TorqueMode = "AUTO" | "MANUAL";
type TorqueIndicator = "BELOW" | "OPTIMAL" | "ABOVE";

type DriveMode      = "WET" | "ICE" | "DRY" | "SPORT" | "ESC_OFF";
type PowertrainMode = "RANGE" | "TOUR" | "PERFO";

type DriverDialMode =
  | "G_METER"
  | "VEHICLE_STATUS"
  | "BATTERY"
  | "TRIP"
  | "DYNAMICS"
  | "TIRES";
// Note: source references "seven functional data points" but names six modes.
// A seventh may be an unnamed default/home state. Listed modes are authoritative.

type MultigraphMode = "CLOCK" | "STOPWATCH" | "COMPASS";
// Launch auto-override adds a system-driven "LAUNCH_CHRONO" mode (not user-selectable)

type StopwatchState = "RESET" | "RUNNING" | "PAUSED";
type ControlPanelContext = "OFF" | "CLIMATE" | "SETTINGS" | "MEDIA";
type KeyState       = "ABSENT" | "DOCKED";
type HeadlightMode  = "OFF" | "AUTO" | "HIGH";
type LaunchState    = "IDLE" | "PRE_ARM" | "ARMED" | "STAGING" | "LAUNCH";

// Color mapping (mode → accent color)
const MODE_COLORS: Record<DriveMode, string> = {
  WET:     "#00FF00",
  ICE:     "#00FFFF",
  DRY:     "#FCD116",
  SPORT:   "#FF2800",
  ESC_OFF: "#FF0000"
};

const POWER_COLORS: Record<PowertrainMode, string> = {
  RANGE: "#00FF00",
  TOUR:  "#FCD116",
  PERFO: "#FF2800"
};
```

---

## 3 — Cockpit Spatial Map

```
┌──────────────── OVERHEAD PANEL (HEADLINER) ───────────────────┐
│                                                                │
│   [LAUNCH PULL]    [LIGHTS]    [DEFROST]    [SOS]             │
│                                                                │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────── DASHBOARD ──────────────────────────┐
│                                                                │
│  ┌──────────┬────────────────┬──────────┐                     │
│  │  LEFT    │    CENTER      │  RIGHT   │    CONTROL PANEL    │
│  │  DIAL    │    DIAL        │  DIAL    │    (articulating)   │
│  │  Power   │  Speed+Battery │  Driver  │   ┌──────────────┐ │
│  │  (E-Man  │  Mech. needle  │  Perf.   │   │ [C] [S] [M]  │ │
│  │  linked) │  + torque mtr  │  7 modes │   │  Touchscreen  │ │
│  └──────────┴────────────────┴──────────┘   │  Climate Ctrls│ │
│     DRIVER BINNACLE (moves with steering)   │              ○│ │
│                                              │  Multigraph  │ │
│                                              └──────────────┘ │
├───────────────────────────────────────────────────────────────┤
│                                                                │
│  STEERING WHEEL                                                │
│  ├─ Left pod:  Manettino (red rotary, 5 detents)              │
│  ├─ Right pod: E-Manettino (silver rotary, 3 positions)       │
│  │             + Driver Dial Toggle (mechanical, cycles modes) │
│  └─ Behind:    Torque paddle blades (+/−), fixed to column    │
│                                                                │
├──────────────────────── CENTER CONSOLE ────────────────────────┤
│                                                                │
│  ┌──────────────┐ ┌───┐                                       │
│  │ Gear Display  │ │ ● │ Joystick (momentary)                 │
│  └──────────────┘ └───┘ (locked until key docked)             │
│                                                                │
│   ◈ KEY DOCK ◈  (physical key receptacle)                     │
│                                                                │
│  ┌─────┐ ┌─────┐  (●)     (●)                                │
│  │ ╲╱  │ │ ╲╱  │  Frunk   Door                               │
│  └─────┘ └─────┘  Release  Lock                              │
│  Drv Win  Pas Win                                             │
│                                                                │
│  [PARK ASSIST]   [LIFT]                                       │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

**Note on Park Assist and Lift placement:** The authoritative source does not explicitly locate these controls. They are placed on the center console as the most ergonomically logical position for driver-operated vehicle controls. This may require verification against final production layout.

---

## 4 — Canonical State Object

```json
{
  "time_ms": 0,

  "system": {
    "key_state": "ABSENT"
  },

  "vehicle": {
    "speed_kmh": 0.0,
    "max_speed_kmh": 320,
    "speed_unit": "km/h"
  },

  "drivetrain": {
    "current_gear": "P",
    "drive_mode": "DRY",
    "powertrain_mode": "TOUR",
    "gear_animation_state": "IDLE",
    "gear_scroll_progress": 0.0,
    "torque": {
      "mode": "AUTO",
      "current_level": 4,
      "optimal_indicator": "OPTIMAL",
      "regen_contribution_kw": 0.0
    }
  },

  "power": {
    "battery_soc_pct": 78,
    "battery_kwh": 62.4,
    "battery_temp_c": 42.0,
    "current_power_kw": 0.0,
    "max_power_available_kw": 500,
    "range_remaining_km": 408,
    "is_regenerating": false,
    "regen_kw": 0.0
  },

  "launch": {
    "state": "IDLE",
    "checklist": {
      "battery_temp_ok": true,
      "traction_mode_ok": true,
      "power_potential_pct": 100
    },
    "staging": {
      "brake_pressure_pct": 0,
      "throttle_position_pct": 0
    },
    "results": {
      "timer_ms": 0,
      "distance_m": 0,
      "zero_to_100_ms": null
    }
  },

  "climate": {
    "driver_temp_c": 21.0,
    "passenger_temp_c": 21.0,
    "is_synced": false,
    "fan_level": "MED",
    "driver_seat_heat": 0,
    "passenger_seat_heat": 0
  },

  "windows": {
    "driver_pct": 100,
    "passenger_pct": 100,
    "door_ajar": false
  },

  "binnacle": {
    "moves_with_steering": true,
    "left_dial": {
      "type": "POWER",
      "linked_to": "powertrain_mode",
      "launch_override_active": false
    },
    "center_dial": {
      "type": "SPEED_AND_BATTERY",
      "has_mechanical_needle": true,
      "torque_meter_visible": true
    },
    "right_dial": {
      "type": "DRIVER",
      "current_mode": "G_METER",
      "available_modes": [
        "G_METER", "VEHICLE_STATUS", "BATTERY",
        "TRIP", "DYNAMICS", "TIRES"
      ]
    },
    "brightness_pct": 80
  },

  "control_panel": {
    "context": "CLIMATE",
    "articulates": true,
    "multigraph": {
      "mode": "CLOCK",
      "has_mechanical_hands": true,
      "stopwatch_state": "RESET",
      "stopwatch_value_ms": 0,
      "compass_heading_deg": 330,
      "launch_override_active": false
    }
  },

  "overhead": {
    "launch_pull_available": true,
    "headlight_mode": "AUTO",
    "defrost_active": false,
    "sos_triggered": false
  },

  "systems": {
    "is_frunk_open": false,
    "is_lift_active": false,
    "is_park_assist_active": false,
    "door_lock_state": "LOCKED"
  }
}
```

**Battery display thresholds** (rendered on the center dial's digital face):

| SOC Range | Color | Animation |
|-----------|-------|-----------|
| 100% – 30% | Verde Signal | Steady |
| 29% – 15% | Giallo Modena | Steady |
| Below 15% | Rosso Corsa | Blink (0.5s interval) |

---

## 5 — Module Specifications

---

### Module 1: Physical Key Dock

The root state of the entire system. The interface begins with a physical key before the car awakens.

**Hardware**: A precision-machined physical key that docks into a receptacle on the center console. The key represents the driver's persistent, personal connection to their Ferrari Luce.

**Boot Sequence**:
1. Key is inserted into dock
2. Key locks into place with mechanical confirmation
3. Giallo Modena "surges" from the key outward across all displays — a radiant boot animation
4. Displays initialize sequentially (binnacle → control panel → multigraph)
5. Shifter mechanically unlocks — ready to drive

**State Machine**

```
KEY_ABSENT
    │
    │  Shifter mechanically locked
    │  Displays dark or minimal ambient state
    │  All modules inactive
    │
    └─ [KEY_DOCK] ─→ KEY_DOCKED
                         │
                         │  Yellow surge animation radiates from console
                         │  Displays initialize sequentially
                         │  Shifter mechanically unlocks
                         │  All modules become active
                         │
                         ├─ [KEY_UNDOCK] ─→ KEY_ABSENT
                         │                    Shifter locks
                         │                    Displays fade to dark
                         │                    All modules deactivate
                         │
                         └─ System is now live

```

**Note**: A mobile app or digital key may exist as a secondary convenience feature for approach lighting, door handle presentation, and remote functions. But the primary ignition root is the physical key dock.

---

### Module 2: Gear Selector (Center Console)

Replaces the traditional gear stick with a minimalist sculptural interaction. Mechanically locked until the key is docked.

**Hardware**
- **The Stick**: Short, glossy black joystick nub. Momentary — always returns to center after actuation. Mechanically locked (cannot move) when `key_state == "ABSENT"`.
- **Top Button**: Dedicated PARK selector on top of the stick.
- **Mini Display**: Small high-resolution rectangular screen positioned directly left of the stick.

**Display States**

| State | Content |
|-------|---------|
| Key absent | Dark / inactive |
| Idle / Intro | Prancing Horse on Giallo Modena field |
| Active | Selected gear letter in Heritage Serif, bold, glow |
| Transitioning | Drum scroll animation (see below) |

**The Drum Viewport**

Only one gear letter is fully visible at a time. Adjacent gears appear as ghosts above and below:

```
┌─────────┐
│    N    │  ← Grigio, 30% opacity
│─────────│
│    D    │  ← White, Heritage Serif, bold, glow
│─────────│
│         │
└─────────┘
```

**The Drum Scroll Animation**

Gear changes are *never* an instant label swap. The display scrolls like a mechanical drum:

- **P → D**: 'P' slides upward out of frame. 'R' and 'N' scroll past as ghosts (rapid, ~100ms each). 'D' slides in from below and snaps to center with a slight overshoot-settle.
- Use a **linked-list** data structure: each gear node holds references to `previous` and `next` for smooth bidirectional traversal.
- `scroll_progress` (0.0 → 1.0) drives the animation. Intermediate values render the transitioning letters at proportional vertical offsets.

**Input Mapping**

| Physical Action | Duration | Resulting Gear | Precondition |
|----------------|----------|---------------|--------------|
| Top Button Press | Any | PARK | `speed_kmh == 0` |
| Pull Stick Back | Hold ≥ 0.5s | DRIVE | Brake applied |
| Push Stick Forward | Hold ≥ 0.5s | REVERSE | `speed_kmh == 0`, brake applied |
| Push Stick Forward | Tap < 0.5s | NEUTRAL | Currently in D or R |

**State Machine**

```
PARK (P)
    ├─ [JOYSTICK_BACK_HOLD] ─→ DRIVE (D)
    └─ [JOYSTICK_FWD_HOLD, speed==0] ─→ REVERSE (R)

DRIVE (D)
    ├─ [JOYSTICK_FWD_TAP] ─→ NEUTRAL (N)
    ├─ [GEAR_P_PRESS, speed==0] ─→ PARK (P)
    └─ Torque paddles affect torque levels, not gear — see Module 8

REVERSE (R)
    ├─ [JOYSTICK_FWD_TAP] ─→ NEUTRAL (N)
    ├─ [GEAR_P_PRESS, speed==0] ─→ PARK (P)
    └─ Entering R triggers REAR_CAMERA_REQUESTED event

NEUTRAL (N)
    ├─ [JOYSTICK_BACK_HOLD] ─→ DRIVE (D)
    └─ [GEAR_P_PRESS] ─→ PARK (P)
```

**Safety rules**: Reject `P` and `R` when `speed_kmh > 5`. Ignore the input silently — no error state.

---

### Module 3: Steering Wheel — Manettino (Left Pod)

Controls the vehicle's dynamic stability character.

**Hardware**: Solid red anodized rotary switch. 5 firm detent positions. Each `ROTATE_CW` or `ROTATE_CCW` moves exactly one position.

**States (Clockwise)**

| Position | Name | Stability | Throttle | Accent Color |
|----------|------|-----------|----------|-------------|
| 1 | WET | Maximum TC | Dampened | Verde |
| 2 | ICE | High TC | Dampened | Cyan |
| 3 | DRY | Balanced | Linear | Giallo |
| 4 | SPORT | Reduced TC | Sharp | Rosso |
| 5 | ESC OFF | TC Disabled | Direct | Rosso (persistent warning) |

**Cross-effects**: Changing the Manettino updates the binnacle accent color and modifies Launch Control eligibility (Launch requires SPORT or ESC_OFF).

**Feedback**: Binnacle highlight migrates to match the current position. A brief mode label appears on the binnacle for ~2s, then fades.

---

### Module 4: Steering Wheel — E-Manettino Pod (Right Pod)

The right steering pod houses two separate controls: the E-Manettino rotary and the Driver Dial toggle.

#### 4A: E-Manettino (Powertrain Rotary)

Controls the powertrain's energy strategy.

**Hardware**: Silver rotary knob with center push-button. 3 positions with smooth detents.

**States**

| Position | UI Color | Power Cap | Cooling | Left Dial Display |
|----------|----------|-----------|---------|-------------------|
| RANGE | Verde Signal | Limited | Eco | Regen zone prominent, limited power arc |
| TOUR | Giallo Modena | Standard | Standard | Balanced power/regen display |
| PERFO | Rosso Corsa | Maximum kW | Maximum | Power zone expanded, full scale |

**Cross-effects**: Changes `powertrain_mode` in state. This affects:
- Left dial (Power Dial) — color and scale
- Center dial ring color
- Control panel "POWER: {mode}" label
- `max_power_available_kw` value
- Range estimate calculation

#### 4B: Driver Dial Toggle (Mode Cycler)

Cycles the right binnacle dial through its seven data modes.

**Hardware**: Mechanical toggle co-located with the E-Manettino on the right steering pod. Each actuation cycles one mode forward.

**Modes cycled**: G_METER → VEHICLE_STATUS → BATTERY → TRIP → DYNAMICS → TIRES → G_METER

---

### Module 5: Driver Binnacle (3-Dial, Steering-Column-Fixed)

A fully analog-digital hybrid instrument cluster arranged as three circular dials. The entire binnacle is **fixed to the steering column and moves with the steering wheel**, ensuring the driver's view of instrumentation is always optimal regardless of steering angle.

**Layout**

```
┌──────────────────┬──────────────────────────┬──────────────────┐
│    LEFT DIAL     │      CENTER DIAL         │    RIGHT DIAL    │
│                  │                          │                  │
│   POWER DIAL     │   SPEED + BATTERY        │   DRIVER DIAL    │
│   (E-Manettino   │   (Mechanical needle     │   (7 data modes, │
│    linked)       │    + digital face)        │    toggle-cycled)│
│                  │                          │                  │
│  Power output &  │  Speed: physical needle  │  Current mode:   │
│  regen display   │  Battery: digital ring   │  G Meter /       │
│                  │  Torque meter above      │  Vehicle Status / │
│  RANGE: green    │                          │  Battery / Trip / │
│  TOUR: yellow    │                          │  Dynamics / Tires │
│  PERFO: red      │                          │                  │
└──────────────────┴──────────────────────────┴──────────────────┘
```

#### Left Dial — Power Dial

Directly connected to the E-Manettino mode. Shows available power output and regenerative braking.

```
        . - - - .
     /   ◜████◝   \      ← Power arc: fills with current kW output
    |    316 kW     |     ← Numeric: Telemetry Mono
    |    ─ ─ ─ ─    |     ← Regen zone below baseline (Verde)
     \    PERFO    /      ← Current E-Manettino mode label
        ' - - - '
```

**Mode-color mapping** (inherited from E-Manettino):

| E-Manettino | Dial Color | Power Cap | Regen Display |
|-------------|-----------|-----------|---------------|
| RANGE | Verde Signal | Limited | Regen zone prominent |
| TOUR | Giallo Modena | Standard | Balanced |
| PERFO | Rosso Corsa | Maximum kW | Power zone expanded |

**Regen visualization**: When regenerating, the arc extends into a dedicated "charge zone" segment below the baseline, colored Verde Signal. The regen contribution in kW is shown numerically.

**Launch override**: During Launch Mode, this dial transitions to orange and expands its scale to display the boosted power delivery envelope. See Module 10.

#### Center Dial — Speed + Battery (Hybrid Mechanical-Digital)

The centerpiece of the binnacle. Combines a **physical mechanical needle** driven by a motor with a **digital OLED face** beneath it. Both speed and battery — the two most critical data points — are shown on this single dial.

```
              [|||]              ← Torque meter (small, above dial)
        . - - - - - .
     /   ◜███████◝    \        ← Digital ring fill (mode-colored)
    |     ↗             |
    |      125           |       ← Mechanical needle (physical!) + digital speed
    |      km/h          |       ← Unit: Small, Grigio
    |   [████  ] 78%     |       ← Battery SOC indicator (digital)
     \                 /
        ' - - - - - '
```

**Mechanical needle**: Physical aluminium needle, motor-driven. Provides a visceral, analog speed reading. Sweeps continuously and smoothly.

**Digital layer beneath needle**:
- Ring fill: Mode-colored sector arc, fills clockwise proportional to `speed_kmh / max_speed_kmh`
- Speed numeral: Large, white, Telemetry Mono (redundant with needle for precision)
- Battery SOC: Digital bar or arc segment with color thresholds (see Section 4)
- Ghost tick marks at 0 and max positions

**Ring color logic** (derived from current modes):

```ts
function getRingColor(driveMode: DriveMode, powertrainMode: PowertrainMode): string {
  if (driveMode === "SPORT" || driveMode === "ESC_OFF") return ROSSO_CORSA;
  if (powertrainMode === "PERFO") return ROSSO_CORSA;
  if (powertrainMode === "RANGE") return VERDE_SIGNAL;
  return GIALLO_MODENA;
}
```

**Torque meter**: A small indicator positioned **above** the central dial. Shows the current torque delivery level and indicates the **optimal moment to increase** — a coaching instrument for the paddle-based torque control system (Module 8). In `AUTO` torque mode, the meter displays passively. In `MANUAL` torque mode, it becomes an active coaching display.

**Battery thresholds** (rendered digitally on the center dial):

| SOC Range | Color | Animation |
|-----------|-------|-----------|
| 100% – 30% | Verde Signal | Steady |
| 29% – 15% | Giallo Modena | Steady |
| Below 15% | Rosso Corsa | Blink (0.5s interval) |

#### Right Dial — Driver Performance Dial

A multi-mode instrument cycled via the **mechanical toggle on the right steering pod** (co-located with the E-Manettino rotary — see Module 4B).

**Modes**:

| Mode | Content | Use Case |
|------|---------|----------|
| G Meter | Lateral/longitudinal g-force crosshair | Track driving, cornering feedback |
| Vehicle Status | System health overview | Pre-drive check, diagnostics |
| Battery | Detailed battery info (temp, cell balance, charge rate) | Range planning, charging |
| Trip | Trip distance, time, efficiency | Journey tracking |
| Dynamics | Suspension, stability, traction detail | Tuning feedback |
| Tires | Tire pressure, temperature per wheel | Safety, track prep |

**Note**: The authoritative source references "seven functional data points" but names six modes. A seventh may represent a default/home view or an unnamed mode. The six listed modes are confirmed.

#### Theme Override (Launch Control)

When `launch.state` is ARMED or beyond, the binnacle enters a dramatic override:
- Background darkens further
- All text shifts to Rosso Corsa / orange
- Left dial (Power) transitions to orange with expanded scale
- Checklist and staging bars overlay the center dial
- Normal speed ring is suppressed
- Right dial continues displaying its current mode (non-critical, not suppressed)

---

### Module 6: Control Panel (Articulating, Shared)

A self-contained articulating panel with an aluminium bracket that forms both a handle and a palm rest. Can be **physically pivoted** by either driver or co-pilot to angle toward themselves. Made from premium materials: aluminium, leather, Alcantara, glass.

Contains four sub-components: mode buttons, a touchscreen, physical climate controls, and a multigraph instrument.

#### 6A: Mode Buttons (Physical)

Three physical buttons that set the touchscreen context, plus an Off state:

| Button | Screen Context | Content |
|--------|---------------|---------|
| Off | Dark | Touchscreen inactive |
| Climate | Climate detail view | Zone control, scheduling, detailed settings |
| Settings | Vehicle settings | Personalization, system configuration |
| Media | Media & navigation | Audio, source selection, route planning, maps |

#### 6B: Touchscreen (OLED)

High-resolution custom-shaped OLED, laminated to coverglass. Used for **low-frequency, configuration-depth** tasks:
- Deeper climate settings (zone control, scheduling)
- Media playback and source selection
- Navigation maps and route planning
- Vehicle settings and personalization

**Design principle**: The touchscreen handles secondary, configuration-depth interactions. High-frequency adjustments (temperature, fan speed, seat heat) are always physical controls — never buried in a touchscreen menu.

When in CLIMATE context, the touchscreen may display:
- Current drive mode in its accent color
- Current speed (large, white, Telemetry Mono)
- Powertrain mode and live kW consumption
- Rolling telemetry graphs (speed vs. time, power/regen vs. time)

**Telemetry graph specification** (when displayed):
- X-axis: Time (rolling 30s window, right edge = now)
- Y-axis: Value (km/h or kW)
- Line: Thin, antialiased, colored by current mode accent
- Grid: Subtle at 25% opacity
- New data point pushed every 100ms

#### 6C: Climate Controls (Physical)

Physical controls for immediate climate needs — accessible without looking at a screen:

| Control | Type | Action |
|---------|------|--------|
| Cabin temperature | Adjustment control | Increase / decrease in 0.5°C steps |
| Fan speed | Stepped control | LO → MED → HI |
| Seat heating | Stepped control | 0 → 1 → 2 → 3 (wraps) |
| Seat ventilation | Stepped control | Off / On levels |

**UX rule**: Each physical climate input produces a transient HUD overlay on the touchscreen that fades after ~2 seconds. The overlay shows the current value (e.g., "21.0°C", "FAN: HI", seat icon with heat waves).

#### 6D: Multigraph (Hybrid Mechanical-Digital Round Instrument)

A small circular instrument attached to the control panel. Combines **physical mechanical hands** driven by motors with a **digital OLED face** beneath them. This is not a screen — it is a hybrid instrument.

**Buttons**:
- **Mode Button (side)**: Cycles mode: CLOCK → STOPWATCH → COMPASS → CLOCK
- **Action Button (top)**: Contextual action (primarily controls stopwatch)

**Three Modes**:

| Mode | Mechanical Hands | Digital Face | Description |
|------|-----------------|-------------|-------------|
| CLOCK | Hour + minute + seconds hands (physical) | Minimal face markings | Analog watch. Seconds hand sweeps smoothly (no tick). |
| STOPWATCH | Single chrono hand (physical, 60s sweep) | 60-second scale | 60-second stopwatch. One full revolution = 60 seconds. |
| COMPASS | Pointer hand (physical, points north) | Heading degrees + cardinal direction | Navigational compass. |

**ASCII Renderings**

```
   CLOCK              STOPWATCH           COMPASS
  .------.           .------.           .------.
 / 12     \         /  60    \         / 330°   \
|9   |  3  |       | 0  ●  30|       |   NW     |
|    |     |       |         |       |   ▲ N    |
 \  6    /         \ 15   45/         \        /
  '------'          '------'           '------'
```

**Stopwatch State Machine** (normal, non-launch mode):

```
RESET (00.00, hand at 0)
    │
    └─ [ACTION_PRESS] ─→ RUNNING (hand sweeps 60s scale)
                              │
                              ├─ [ACTION_PRESS] ─→ PAUSED (hand stops)
                              │                        │
                              │                        ├─ [ACTION_PRESS] ─→ RUNNING (resume)
                              │                        │
                              │                        └─ [ACTION_LONG_PRESS ≥ 2s] ─→ RESET
                              │                             (hand returns to 0)
                              │
                              └─ [MODE_PRESS] ─→ Mode cycles, but stopwatch
                                                  continues running in background
```

**Critical**: Pressing the mode button while STOPWATCH is RUNNING cycles the *display mode* but does NOT stop the timer. The stopwatch continues counting in state even when not visible. Returning to STOPWATCH mode reveals the running time and the hand at its current position.

**Launch Mode Auto-Override**:

When Launch Mode activates (`launch.state` enters ARMED or beyond), the multigraph **automatically** transitions — regardless of its current mode — to a dedicated **5-second Launch Mode stopwatch**. This is system-driven, not user-initiated.

```
NORMAL_MODE (Clock / Stopwatch / Compass)
    │
    │  User cycles via mode button
    │
    └─ [launch.state enters ARMED] ─→ LAUNCH_CHRONO_OVERRIDE
                                            │
                                            │  Digital face switches to 5-second scale
                                            │  Mechanical hand positions at 0
                                            │  Normal stopwatch state preserved in background
                                            │
                                            ├─ [launch.state enters LAUNCH] ─→ Hand sweeps 5s scale
                                            │                                   Timer counts in ms
                                            │
                                            └─ [launch.state returns to IDLE] ─→ NORMAL_MODE
                                                 Returns to whatever mode was active before
                                                 If stopwatch was running, it's still running
```

---

### Module 7: Comfort Console (Center Bridge)

Located on the center console below the gear selector. Contains high-frequency utility controls for windows, frunk, and door locks.

**Hardware Layout**

```
┌─────────────────────────────────────────┐
│  ┌─────┐  ┌─────┐   (●)       (●)      │
│  │ ╲╱  │  │ ╲╱  │   🧳         🔒      │
│  └─────┘  └─────┘                       │
│  Driver    Passenger  Frunk     Door     │
│  Window    Window     Release   Lock     │
│                                         │
│  [PARK ASSIST]    [LIFT]                │
└─────────────────────────────────────────┘
```

**Window Toggles**: Two curved rectangular switches with concave surfaces.
- Pull up → Close window (increase `window_pct`)
- Push down → Open window (decrease `window_pct`)

**Window Auto-Drop Logic**:

```ts
function onDoorStateChange(door_ajar: boolean, state: CarState): CarState {
  if (door_ajar) {
    // Drop windows slightly to clear frameless door seal
    return { ...state, windows: {
      ...state.windows,
      driver_pct: Math.min(state.windows.driver_pct, 95),
      door_ajar: true
    }};
  } else {
    // Door closed — restore previous position
    return { ...state, windows: {
      ...state.windows,
      driver_pct: state.windows._saved_driver_pct,
      door_ajar: false
    }};
  }
}
```

**Frunk Release**:

```
FRUNK_CLOSED
    │
    └─ [FRUNK_PRESS] ─→ Check speed
                            │
                            ├─ [speed_kmh > 0] ─→ Ignored (safety lockout)
                            │
                            └─ [speed_kmh == 0] ─→ FRUNK_OPEN
                                                       │
                                                       └─ [Physical close + FRUNK_PRESS] ─→ FRUNK_CLOSED
```

**Door Lock**: Toggles `door_lock_state` between LOCKED and UNLOCKED. Produces a transient lock/unlock icon on the binnacle.

**Park Assist Toggle**: Activates proximity sensors and 360° camera mosaic. OFF / ON.

**Lift System State Machine**:

```
LIFT_INACTIVE
    │
    └─ [LIFT_TOGGLE] ─→ Check speed
                            │
                            ├─ [speed_kmh > 40] ─→ Rejected
                            │                       Brief warning on binnacle: "Speed too high"
                            │
                            └─ [speed_kmh ≤ 40] ─→ LIFT_ACTIVE
                                                       │
                                                       │ Binnacle shows "Vehicle Raising" animation
                                                       │ Suspension physically raises
                                                       │
                                                       ├─ [speed_kmh > 40] ─→ Auto-lower → LIFT_INACTIVE
                                                       │   (System forces deactivation for safety)
                                                       │
                                                       └─ [LIFT_TOGGLE] ─→ LIFT_INACTIVE
                                                            Suspension lowers
```

---

### Module 8: Torque Control Paddles

Two tall, vertical metallic blades precision-machined from 100% recycled aluminium with anodised finish. Fixed to the steering column — they do **not** rotate with the wheel. A magnetic mechanism provides clear, deliberate, and satisfying feedback on each pull.

**Fundamental framing**: This is an EV. There are no multi-ratio gears. The paddles control **torque delivery levels** for progressive, manual acceleration management, combined with regenerative braking recovery on lift-off.

**Hardware**:
- Right Paddle (+): Increase torque level
- Left Paddle (−): Decrease torque level / increase regen

**Torque Meter Interaction**: The torque meter positioned above the central dial (see Module 5) shows the current torque level and indicates the **optimal moment to increase**. When the meter shows the driver is in the optimal band, pulling the right paddle steps up to the next torque level for smooth, progressive acceleration. This is a coaching instrument — the driver learns to build speed progressively rather than relying on binary throttle input.

**State Machine**:

```
AUTO_TORQUE (default)
    │
    │  System manages torque delivery automatically
    │  Torque meter shows current level passively
    │  Gear display shows "D"
    │
    └─ [PADDLE_UP or PADDLE_DOWN] ─→ MANUAL_TORQUE
                                          │
                                          │ Driver now controls torque stepping
                                          │ Torque meter becomes active coaching display
                                          │   (shows BELOW / OPTIMAL / ABOVE indicator)
                                          │
                                          ├─ [PADDLE_UP] ─→ Increase torque level
                                          │                  (capped at level 8)
                                          │
                                          ├─ [PADDLE_DOWN] ─→ Decrease torque level /
                                          │                    increase regen
                                          │                    (floored at level 1)
                                          │
                                          ├─ [Timeout + steady throttle] ─→ AUTO_TORQUE
                                          │     Torque meter returns to passive display
                                          │
                                          └─ [TORQUE_MODE_TOGGLE] ─→ PERMANENT_MANUAL
                                                                          │
                                                                          │ No auto-revert
                                                                          │ Torque meter stays active
                                                                          │
                                                                          └─ [TORQUE_MODE_TOGGLE] ─→ AUTO_TORQUE
```

**Display note**: During manual torque mode, the torque meter above the center dial highlights the current level and the optimal band. The gear mini-display continues showing "D" — torque levels are not rendered on the gear display (they are a throttle modulation, not a gear change).

---

### Module 9: Overhead Control Panel

Located in the headliner above the driver and front passenger. Houses controls that are either safety-critical (requiring deliberate, non-accidental actuation) or infrequently adjusted.

**Layout**:

```
┌──────────── OVERHEAD PANEL (HEADLINER) ──────────────┐
│                                                       │
│   [LAUNCH PULL]   [LIGHTS]   [DEFROST]   [SOS]      │
│                                                       │
└───────────────────────────────────────────────────────┘
```

**Controls**:

| Control | Type | States / Behavior |
|---------|------|-------------------|
| Launch Pull | Physical pull mechanism | Initiates Launch Mode sequence (see Module 10). Deliberate overhead reach required — hard to trigger accidentally. |
| Lights | Toggle | OFF → AUTO → HIGH (cycles). AUTO is default after key dock. |
| Defrost | Toggle | OFF / ON. Activates front and/or rear defroster. |
| SOS | Momentary | Emergency beacon / call trigger. Requires confirmation in production. |

**Design rationale**: Placing Launch in the overhead panel (not on the center console) ensures it requires a deliberate, committed physical gesture — an overhead reach and pull. This is a safety-conscious ergonomic choice for a feature that unlocks maximum acceleration.

---

### Module 10: Launch Control

The most complex state machine in the cockpit. A multi-step gated sequence that unlocks maximum acceleration.

**Hardware Trigger**: A physical pull mechanism in the overhead panel (Module 9).

**Complete State Machine**

```
┌──────────────────────────────────────────────────────────────────┐
│                            IDLE                                   │
│                                                                   │
│  The default state. LAUNCH_PULL is ignored here.                 │
│                                                                   │
│  Active when ANY of:                                             │
│    • speed_kmh > 0                                               │
│    • drive_mode ∉ {SPORT, ESC_OFF}                               │
│                                                                   │
│  Display: Standard binnacle (no launch overlay)                  │
└──────────────────────────────────────────────────────────────────┘
         │
         │  [speed_kmh == 0 AND drive_mode ∈ {SPORT, ESC_OFF}]
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                          PRE_ARM                                  │
│                                                                   │
│  System is eligible. Waiting for driver to pull LAUNCH.          │
│  No visual change yet — driver may not intend to launch.         │
│                                                                   │
│  Transitions:                                                     │
│    • [LAUNCH_PULL] → ARMED                                       │
│    • [speed_kmh > 0] → IDLE                                      │
│    • [drive_mode changes to ineligible] → IDLE                   │
└──────────────────────────────────────────────────────────────────┘
         │
         │  [LAUNCH_PULL]
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                           ARMED                                   │
│                                                                   │
│  Visual Changes (system-driven, automatic):                      │
│    • Binnacle darkens — standard gauges suppressed               │
│    • All text shifts to Rosso Corsa / orange                     │
│    • Left dial (Power): transitions to ORANGE, scale expands     │
│      to show boosted power delivery envelope                     │
│    • Multigraph: auto-overrides to 5-second Launch stopwatch     │
│      (mechanical hand at 0, digital face shows 5s scale)         │
│    • Center dial shows: "BOOST READY"                            │
│    • Checklist overlay appears:                                   │
│                                                                   │
│    ┌──────────────────────────────────────┐                      │
│    │          BOOST READY                 │                      │
│    │                                      │                      │
│    │  BATTERY TEMP    [OK]  /  [⚠ >80°C] │                      │
│    │  TRACTION MODE   [OK]  /  [⚠ WRONG] │                      │
│    │  POWER POTENTIAL  [100%]             │                      │
│    └──────────────────────────────────────┘                      │
│                                                                   │
│  Transitions:                                                     │
│    • [LAUNCH_PULL again] → IDLE (driver cancels)                 │
│    • [speed_kmh > 0] → IDLE (car moved)                          │
│    • [brake_pressure ≥ threshold] → STAGING                      │
│    • [any checklist item fails] → remain ARMED, show warning     │
└──────────────────────────────────────────────────────────────────┘
         │
         │  [Driver presses brake firmly — begins two-foot maneuver]
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                          STAGING                                  │
│                                                                   │
│  The "Two-Foot" Maneuver: Hold brake with left foot,            │
│  floor accelerator with right foot.                              │
│                                                                   │
│  Display:                                                         │
│    ┌──────────────────────────────────────┐                      │
│    │          BOOST READY                 │                      │
│    │                                      │                      │
│    │  BRAKE    [████████████████]  100%   │  ← Must reach 100%  │
│    │  THROTTLE [████████████████]  100%   │  ← Must reach 100%  │
│    └──────────────────────────────────────┘                      │
│                                                                   │
│  Physical feedback:                                               │
│    • Car vibrates (torque building against brakes)               │
│    • Rear suspension "hunches" (squats lower)                    │
│    • Power builds at limiter — audible whine                     │
│                                                                   │
│  Transitions:                                                     │
│    • [Throttle released] → IDLE ← STRICT RESET (not back to     │
│                                    ARMED — full abort required)  │
│    • [Brake released while throttle ≥ 100%] → LAUNCH            │
└──────────────────────────────────────────────────────────────────┘
         │
         │  [Driver releases brake pedal — stored energy unleashes]
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                           LAUNCH                                  │
│                                                                   │
│  Immediate effects:                                               │
│    • Screen flashes WHITE for 100ms                              │
│    • Transitions to "big numbers only" high-contrast mode        │
│    • Brake bar drops to 0% instantly                             │
│    • Multigraph 5s chrono hand begins sweeping                   │
│                                                                   │
│  Display:                                                         │
│    ┌──────────────────────────────────────┐                      │
│    │          L A U N C H                 │  ← Flashing label   │
│    │                                      │                      │
│    │            0.00 s                    │  ← Timer counting up │
│    │            0 M                       │  ← Distance counting │
│    └──────────────────────────────────────┘                      │
│                                                                   │
│  Active tracking:                                                 │
│    • Elapsed time: counting up in ms, displayed as ss.xx         │
│    • Distance: counting up in meters                             │
│    • 0–100 km/h split: captured automatically when crossed       │
│    • Multigraph: mechanical hand sweeping 5s scale in sync       │
│                                                                   │
│  Transitions:                                                     │
│    • [Throttle released] → IDLE                                  │
│    • [Speed stabilizes / driver brakes] → IDLE                   │
│    • Results saved to launch.results before returning to IDLE    │
│    • Multigraph returns to previous mode on IDLE                 │
│    • Left dial (Power) returns to normal mode/color on IDLE      │
└──────────────────────────────────────────────────────────────────┘
```

**Critical implementation rules**:
1. The `LaunchController` is a strict step-by-step validator. Releasing throttle during STAGING resets to IDLE — not ARMED. The entire sequence must restart.
2. The checklist is evaluated continuously during ARMED. If battery temp exceeds 80°C mid-arm, the warning appears but the system does not force-exit — the driver decides.
3. LAUNCH results (`timer_ms`, `distance_m`, `zero_to_100_ms`) persist in state after returning to IDLE so they can be displayed on the control panel touchscreen.
4. The left dial (Power) and multigraph overrides are **system-driven** — they engage automatically on entering ARMED and disengage automatically on returning to IDLE. No user action required.

---

### Module 11: HUD Overlays (Contextual)

Not a dedicated module but a system of conditional overlays triggered by other modules:

| Triggering Condition | Overlay Content |
|---------------------|-----------------|
| `current_gear == "R"` | Rear camera view with dynamic trajectory lines on binnacle |
| `is_park_assist_active` | 360° camera mosaic with proximity-colored zones (green/yellow/red) |
| Navigation active | Turn-by-turn arrows on binnacle right dial (or projected on windshield) |
| `launch.state ∈ {ARMED, STAGING, LAUNCH}` | Launch overlay suppresses normal binnacle content — see Module 10 |

---

### Module 12: Rear Passenger Display

A display panel in the rear cabin that shares real-time drive information with passengers, alongside independent rear climate controls.

**Known elements** (source provides limited detail):
- Real-time drive data mirroring (speed, mode, power)
- Rear climate controls (independent temperature, fan, seat heat for rear occupants)

**Note**: The authoritative source confirms this module exists but provides minimal specification detail. Full interaction design for the rear display requires further documentation.

---

## 6 — Cross-Module Couplings

These dependencies are where "systems thinking" matters. Building modules in isolation will produce a cockpit that doesn't feel integrated.

### 6.1 Key Dock ↔ Everything
Docking the key is the system root. Yellow surge animation radiates outward from the console across all displays. Shifter mechanically unlocks. All displays initialize. Undocking reverses: shifter locks, displays fade. Every other module's `active` state depends on `key_state == "DOCKED"`.

### 6.2 Gear ↔ Camera System
Entering REVERSE emits `REAR_CAMERA_REQUESTED`. Even if the camera subsystem isn't implemented, the event hook must exist so the binnacle knows to show the overlay.

### 6.3 DriveMode / PowertrainMode ↔ Binnacle Theme
`SPORT` / `PERFO` push orange/red accents across the binnacle. `RANGE` pushes green efficiency emphasis. The layout never changes — only colors, labels, and threshold emphasis shift. Implement as:
```ts
const theme = deriveBinnacleTheme(state.drivetrain.drive_mode, state.drivetrain.powertrain_mode);
// theme contains: ringColor, accentColor, leftDialColor, emphasisLabels
```

### 6.4 Launch ↔ Everything
Launch overrides the binnacle theme, adds its own overlay, suppresses "busy" UI elements. The launch pull is silently ignored unless all prerequisites are met. During STAGING and LAUNCH, other non-critical controls (climate, display mode) should still function but their visual feedback is suppressed. Additionally:
- **Launch ↔ Power Dial**: Left dial transitions to orange with expanded power scale (automatic).
- **Launch ↔ Multigraph**: Multigraph auto-overrides to 5-second stopwatch with mechanical hand at 0 (automatic). Returns to previous mode on IDLE.

### 6.5 Speed ↔ Safety Lockouts
A single speed check gates multiple systems:
- `speed > 0`: Frunk press ignored, P gear rejected, R gear rejected
- `speed > 5`: Reverse rejected
- `speed > 40`: Lift auto-deactivates or rejects activation

Centralize this in the reducer — don't scatter speed checks across UI components.

### 6.6 Torque Paddles ↔ Torque Meter ↔ Center Dial
The torque meter above the center dial reflects the current torque level and coaching indicator (BELOW / OPTIMAL / ABOVE). Paddle inputs change the torque level. The meter is passive in AUTO mode and active-coaching in MANUAL mode. The torque level also affects the power drawn from the battery, which is reflected on the left dial.

### 6.7 Stopwatch ↔ Multigraph Mode Cycling
The stopwatch timer runs independently of display mode. Pressing the mode button to cycle away from STOPWATCH does not stop the timer. This means `stopwatch_state` and `stopwatch_value_ms` must be updated by the reducer's time-tick logic regardless of `multigraph.mode`. The mechanical hand position is tracked even when not visible and restored on return.

### 6.8 E-Manettino ↔ Left Dial (Power Dial)
The left dial is "directly connected" to the E-Manettino mode. Changing from RANGE to PERFO shifts the left dial's color from green to red, expands the power arc scale, and reduces the regen zone emphasis. This is a direct, always-active coupling — no lag, no transition delay.

---

## 7 — Complete Event List

Every physical input in the cockpit, named as a dispatchable event:

**Key Dock**
- `KEY_DOCK`, `KEY_UNDOCK`

**Gear Selector**
- `GEAR_P_PRESS` (top button)
- `JOYSTICK_BACK_TAP`, `JOYSTICK_BACK_HOLD`
- `JOYSTICK_FWD_TAP`, `JOYSTICK_FWD_HOLD`

**Steering Wheel — Left Pod (Manettino)**
- `MANETTINO_CW`, `MANETTINO_CCW`

**Steering Wheel — Right Pod (E-Manettino + Driver Dial)**
- `EMANETTINO_CW`, `EMANETTINO_CCW`, `EMANETTINO_PRESS`
- `DRIVER_DIAL_TOGGLE`

**Torque Control Paddles**
- `PADDLE_UP` (increase torque level)
- `PADDLE_DOWN` (decrease torque level / increase regen)
- `TORQUE_MODE_TOGGLE` (switch between auto and permanent manual)

**Comfort Console**
- `WINDOW_DRIVER_UP`, `WINDOW_DRIVER_DOWN`
- `WINDOW_PASS_UP`, `WINDOW_PASS_DOWN`
- `FRUNK_PRESS`, `LOCK_PRESS`
- `DOOR_AJAR_CHANGED(boolean)`
- `PARK_ASSIST_TOGGLE`, `LIFT_TOGGLE`

**Overhead Panel**
- `LAUNCH_PULL`
- `HEADLIGHT_TOGGLE`, `DEFROST_TOGGLE`, `SOS_PRESS`

**Control Panel**
- `CONTROL_PANEL_OFF`, `CONTROL_PANEL_CLIMATE`, `CONTROL_PANEL_SETTINGS`, `CONTROL_PANEL_MEDIA`
- `TOUCHSCREEN_INPUT(context, action)` (generic for deep settings interactions)

**Control Panel — Climate Controls**
- `TEMP_UP`, `TEMP_DOWN`
- `FAN_UP`, `FAN_DOWN`
- `SEAT_HEAT_UP`, `SEAT_HEAT_DOWN`
- `SEAT_VENT_TOGGLE`
- `SYNC_TOGGLE`

**Multigraph**
- `MULTIGRAPH_MODE_CYCLE` (mode button — cycles Clock → Stopwatch → Compass)
- `MULTIGRAPH_ACTION_PRESS` (action button — tap)
- `MULTIGRAPH_ACTION_LONG_PRESS` (action button — hold ≥ 2s)

**Launch Control (Continuous Inputs)**
- `BRAKE_PRESSURE_CHANGED(pct)`, `THROTTLE_CHANGED(pct)`

**System / Continuous**
- `TICK(delta_ms)` — drives stopwatch counting, torque timeout, animation progress
- `SPEED_UPDATED(kmh)` — from vehicle sensors, triggers lockout re-evaluation

---

## 8 — Rendering Contracts

Each display surface has a "must support" contract — the minimum set of visual states an implementation must handle.

### 8.1 Gear Mini-Display

Must render:
- [ ] Dark/inactive state when key is absent
- [ ] Idle logo screen (Prancing Horse on Giallo field)
- [ ] Active gear letter (Heritage Serif, white, bold, glow) for P, R, N, D
- [ ] Drum scroll animation with ghost letters at partial opacity
- [ ] Transition animation between any two valid gear states (P↔R↔N↔D)

### 8.2 Driver Binnacle (3-Dial, Steering-Fixed)

Must render:
- [ ] Three-dial layout simultaneously (never collapses to fewer)
- [ ] **Left dial**: Power arc proportional to current kW, colored by E-Manettino mode
- [ ] **Left dial**: Regen zone below baseline (Verde) when regenerating
- [ ] **Left dial**: Launch override — orange color, expanded power scale
- [ ] **Center dial**: Awareness of mechanical needle (digital layer must not conflict with physical needle position)
- [ ] **Center dial**: Digital ring fill proportional to speed, colored by mode
- [ ] **Center dial**: Battery SOC indicator with color thresholds + blink at <15%
- [ ] **Center dial**: Torque meter above dial showing current level and optimal band
- [ ] **Right dial**: All six confirmed modes (G Meter, Vehicle Status, Battery, Trip, Dynamics, Tires)
- [ ] **Right dial**: Mode transition on DRIVER_DIAL_TOGGLE
- [ ] Full theme recolor when drive_mode or powertrain_mode changes
- [ ] Launch overlay that suppresses normal center content during ARMED/STAGING/LAUNCH

### 8.3 Control Panel Touchscreen

Must render:
- [ ] Four context states: OFF (dark), CLIMATE, SETTINGS, MEDIA
- [ ] In CLIMATE context: mode label (colored), speed (white, large), power info
- [ ] Telemetry graphs: rolling-window line charts (when displayed)
- [ ] Transient HUD overlays for physical climate control feedback (fade after ~2s)
- [ ] Content updates reflecting cross-module state (mode changes, speed changes)

### 8.4 Multigraph (Hybrid Mechanical-Digital)

Must render (digital face layer — mechanical hands are physical):
- [ ] All three modes: CLOCK, STOPWATCH, COMPASS
- [ ] CLOCK: Minimal face markings for analog watch (hands are mechanical)
- [ ] STOPWATCH: 60-second scale face (hand is mechanical, sweeps one revolution per 60s)
- [ ] COMPASS: Heading degrees and cardinal direction (hand is mechanical, points north)
- [ ] Launch auto-override: 5-second scale face (hand sweeps 5s on launch)
- [ ] Return to previous mode after launch override ends
- [ ] Face must coordinate with mechanical hand position (sync digital markings to physical hand)

---

## 9 — Implementation Classes

### PhysicalKeyDock

```
PhysicalKeyDock
├── Properties
│   └── key_state: KeyState
├── Methods
│   ├── handleDock() → void  // triggers boot sequence
│   ├── handleUndock() → void  // triggers shutdown sequence
│   └── isSystemLive() → boolean
├── Events Emitted
│   ├── onKeyDocked() → triggers yellow surge, display init, shifter unlock
│   └── onKeyUndocked() → triggers display fade, shifter lock
└── Invariants
    └── All other modules require key_state == "DOCKED" to be active
```

### GearSelector

```
GearSelector
├── Properties
│   ├── current_gear: Gear  // "P" | "R" | "N" | "D"
│   ├── gear_sequence: LinkedList<GearNode>  // P ↔ R ↔ N ↔ D
│   ├── is_locked: boolean  // true when key_state == "ABSENT"
│   ├── animation_state: "IDLE" | "SCROLLING"
│   └── scroll_progress: float (0.0 – 1.0)
├── Methods
│   ├── handleInput(event, duration_ms) → Gear | null
│   ├── transitionTo(target: Gear) → void  // initiates drum animation
│   ├── renderFrame(delta_ms) → DisplayFrame
│   └── getVisibleGears() → { prev: Gear|null, current: Gear, next: Gear|null }
├── Events Emitted
│   └── onGearChanged(old_gear, new_gear)
└── Invariants
    └── Rejects all input when is_locked == true
    └── Rejects P and R when speed > 0; rejects R when speed > 5
```

### Manettino

```
Manettino
├── Properties
│   ├── position: DriveMode
│   ├── positions: ["WET", "ICE", "DRY", "SPORT", "ESC_OFF"]  // ordered
│   └── color_map: Record<DriveMode, HexColor>
├── Methods
│   ├── rotate(direction: "CW" | "CCW") → DriveMode
│   ├── getActiveColor() → HexColor
│   └── getStabilityMultiplier() → float  // 1.0 for WET → 0.0 for ESC_OFF
├── Events Emitted
│   └── onPositionChanged(old_mode, new_mode)
└── Invariants
    └── Cannot rotate past ends (WET is min, ESC_OFF is max)
```

### EManettinoPod

```
EManettinoPod
├── EManettino (Powertrain Rotary)
│   ├── Properties
│   │   ├── position: PowertrainMode
│   │   ├── positions: ["RANGE", "TOUR", "PERFO"]
│   │   └── color_map: Record<PowertrainMode, HexColor>
│   ├── Methods
│   │   ├── rotate(direction: "CW" | "CCW") → PowertrainMode
│   │   ├── getActiveColor() → HexColor
│   │   └── getMaxPowerKw() → number
│   ├── Events Emitted
│   │   └── onPositionChanged(old_mode, new_mode)
│   └── Cross-Effects
│       └── Updates left dial color/scale, center ring color, range estimate, control panel labels
│
└── DriverDialToggle (Mode Cycler)
    ├── Properties
    │   ├── current_mode: DriverDialMode
    │   └── modes: ["G_METER","VEHICLE_STATUS","BATTERY","TRIP","DYNAMICS","TIRES"]
    ├── Methods
    │   └── toggle() → DriverDialMode  // advances one position, wraps
    └── Events Emitted
        └── onModeChanged(old_mode, new_mode)
```

### TorqueController

```
TorqueController
├── Properties
│   ├── mode: TorqueMode  // "AUTO" | "MANUAL"
│   ├── current_level: TorqueLevel  // 1–8
│   ├── optimal_indicator: TorqueIndicator  // "BELOW" | "OPTIMAL" | "ABOVE"
│   ├── regen_contribution_kw: number
│   └── timeout_remaining_ms: number  // for auto-revert from temporary manual
├── Methods
│   ├── handlePaddle(direction: "UP" | "DOWN") → TorqueLevel
│   ├── handleModeToggle() → void  // switch to/from permanent manual
│   ├── tick(delta_ms) → void  // decrements timeout, reverts if expired
│   ├── getCurrentLevel() → TorqueLevel
│   └── getOptimalIndicator(speed, power, mode) → TorqueIndicator
├── Events Emitted
│   ├── onTorqueModeChanged(old_mode, new_mode)
│   └── onTorqueLevelChanged(old_level, new_level)
└── Invariants
    └── Temporary manual reverts to AUTO after timeout + steady throttle
    └── Permanent manual never auto-reverts — only explicit toggle
    └── Level capped at 8, floored at 1
```

### LaunchController

```
LaunchController
├── Properties
│   ├── state: LaunchState
│   ├── checklist: { battery_temp_ok, traction_ok, power_pct }
│   ├── staging: { brake_pct, throttle_pct }
│   └── results: { timer_ms, distance_m, zero_to_100_ms }
├── Methods
│   ├── handleLaunchPull() → void
│   ├── updateStaging(brake_pct, throttle_pct) → void
│   ├── tick(delta_ms, current_speed) → void  // updates timer + distance during LAUNCH
│   ├── validatePreconditions(state: CarState) → ChecklistResult
│   └── abort() → void  // forces return to IDLE
├── Events Emitted
│   ├── onStateChanged(old_state, new_state)
│   ├── onChecklistUpdated(checklist)
│   ├── onLaunchComplete(results)
│   ├── onPowerDialOverride(active: boolean)  // signals left dial to go orange
│   └── onMultigraphOverride(active: boolean)  // signals multigraph to 5s chrono
├── Invariants
│   └── Throttle release during STAGING → reset to IDLE (not ARMED)
│   └── LAUNCH_PULL during ARMED → return to IDLE (cancel)
│   └── Any speed > 0 during PRE_ARM or ARMED → return to IDLE
└── Override Management
    └── On entering ARMED: emit onPowerDialOverride(true), onMultigraphOverride(true)
    └── On returning to IDLE: emit onPowerDialOverride(false), onMultigraphOverride(false)
```

### BinnacleRenderer

```
BinnacleRenderer
├── Properties
│   ├── theme: { ringColor, accentColor, leftDialColor, textColor }
│   ├── launch_overlay_active: boolean
│   └── battery_blink_state: boolean
├── Methods
│   ├── deriveTheme(drive_mode, powertrain_mode, launch_state) → Theme
│   ├── renderLeftDial(power_kw, max_power_kw, is_regen, regen_kw, powertrain_mode, launch_override) → void
│   ├── renderCenterDial(speed, max_speed, soc_pct, torque_level, torque_indicator) → void
│   │   // Note: mechanical needle position is motor-driven, not rendered digitally
│   │   // Digital layer renders ring fill, battery, torque meter, numerics
│   ├── renderRightDial(driver_dial_mode, mode_data) → void
│   └── renderLaunchOverlay(launch_state, checklist, staging, results) → void
├── Tick Behavior
│   └── Battery blink toggles every 500ms when soc < 15%
└── Invariants
    └── Three dials always rendered (never collapse)
    └── Launch overlay suppresses normal center content
    └── Left dial color always tracks E-Manettino (unless launch override)
```

### ControlPanel

```
ControlPanel
├── Properties
│   ├── context: ControlPanelContext
│   ├── articulation_angle: float  // physical pivot position
│   └── is_touchscreen_active: boolean
├── Touchscreen
│   ├── Methods
│   │   ├── setContext(context: ControlPanelContext) → void
│   │   ├── render(state, context) → void
│   │   ├── handleTouchInput(context, action) → StateUpdate
│   │   ├── pushSpeedDataPoint(timestamp, kmh) → void
│   │   └── pushPowerDataPoint(timestamp, kw) → void
│   └── Graph Config: 30s rolling window, 100ms sample rate
├── ClimateControls
│   ├── Methods
│   │   └── handleInput(control_id, direction: "UP"|"DOWN") → StateUpdate
│   └── Transient HUD: each input shows overlay for ~2s, then fades
└── Multigraph
    ├── Properties
    │   ├── mode: MultigraphMode  // CLOCK | STOPWATCH | COMPASS
    │   ├── has_mechanical_hands: true  // always
    │   ├── stopwatch_state: StopwatchState
    │   ├── stopwatch_value_ms: number
    │   ├── compass_heading_deg: float
    │   └── launch_override_active: boolean
    ├── Methods
    │   ├── cycleMode() → void  // mode button
    │   ├── handleAction(duration_ms) → void  // action button
    │   ├── tick(delta_ms) → void  // increments stopwatch if RUNNING
    │   ├── enterLaunchOverride() → void  // switch to 5s chrono, preserve previous state
    │   ├── exitLaunchOverride() → void  // return to previous mode
    │   └── renderDigitalFace() → void  // renders face layer; hands are physical
    └── Invariants
        └── Stopwatch ticks in background regardless of visible mode
        └── ACTION_LONG_PRESS (≥2s) resets stopwatch ONLY from PAUSED state
        └── Launch override is system-driven, not user-initiated
        └── Previous mode and stopwatch state preserved through launch override
```

### OverheadPanel

```
OverheadPanel
├── Properties
│   ├── headlight_mode: HeadlightMode
│   ├── defrost_active: boolean
│   └── sos_triggered: boolean
├── Methods
│   ├── handleLaunchPull() → void  // delegates to LaunchController
│   ├── cycleHeadlights() → HeadlightMode  // OFF → AUTO → HIGH
│   ├── toggleDefrost() → boolean
│   └── handleSOS() → void  // requires confirmation
└── Events Emitted
    ├── onHeadlightChanged(mode)
    ├── onDefrostChanged(active)
    └── onSOSTriggered()
```

---

## 10 — Example State Snapshots (Test Fixtures)

### 10.1 Highway Cruising in RANGE Mode

```json
{
  "time_ms": 3847200,
  "system": { "key_state": "DOCKED" },
  "vehicle": { "speed_kmh": 112.0 },
  "drivetrain": {
    "current_gear": "D",
    "drive_mode": "DRY",
    "powertrain_mode": "RANGE",
    "torque": {
      "mode": "AUTO",
      "current_level": 4,
      "optimal_indicator": "OPTIMAL"
    }
  },
  "power": {
    "battery_soc_pct": 64,
    "current_power_kw": 38.2,
    "range_remaining_km": 312,
    "is_regenerating": false
  },
  "launch": { "state": "IDLE" },
  "binnacle": {
    "left_dial": { "launch_override_active": false },
    "center_dial": { "torque_meter_visible": true },
    "right_dial": { "current_mode": "TRIP" }
  },
  "control_panel": {
    "context": "CLIMATE",
    "multigraph": { "mode": "COMPASS", "stopwatch_state": "RESET" }
  },
  "overhead": { "headlight_mode": "AUTO", "defrost_active": false }
}
```

**Expected binnacle**: Left dial green (RANGE), power arc at ~38 kW. Center dial green-accented ring at ~35% fill, mechanical needle at 112, battery indicator green at 64%. Right dial showing Trip data. Normal layout, no overlays.

### 10.2 Launch Control — Staging (Ready to Launch)

```json
{
  "time_ms": 812345,
  "system": { "key_state": "DOCKED" },
  "vehicle": { "speed_kmh": 0.0 },
  "drivetrain": {
    "current_gear": "D",
    "drive_mode": "SPORT",
    "powertrain_mode": "PERFO",
    "torque": {
      "mode": "AUTO",
      "current_level": 8,
      "optimal_indicator": "ABOVE"
    }
  },
  "power": {
    "battery_soc_pct": 84,
    "battery_temp_c": 58.5,
    "current_power_kw": 0.0,
    "max_power_available_kw": 500
  },
  "launch": {
    "state": "STAGING",
    "checklist": { "battery_temp_ok": true, "traction_mode_ok": true, "power_potential_pct": 100 },
    "staging": { "brake_pressure_pct": 100, "throttle_position_pct": 100 }
  },
  "binnacle": {
    "left_dial": { "launch_override_active": true },
    "center_dial": { "torque_meter_visible": true },
    "right_dial": { "current_mode": "G_METER" }
  },
  "control_panel": {
    "context": "CLIMATE",
    "multigraph": {
      "mode": "CLOCK",
      "launch_override_active": true,
      "stopwatch_state": "RESET",
      "stopwatch_value_ms": 0
    }
  },
  "overhead": { "headlight_mode": "AUTO" }
}
```

**Expected binnacle**: Dark override, orange text, "BOOST READY", both bars at 100%. Left dial orange with expanded power scale. Car is vibrating, rear squatting. **Expected multigraph**: Auto-overridden to 5-second launch chrono (regardless of previous CLOCK mode). Mechanical hand at 0, digital face showing 5s scale. Next action: release brake to launch.

### 10.3 Manual Torque Stepping in Sport Mode

```json
{
  "time_ms": 2100000,
  "system": { "key_state": "DOCKED" },
  "vehicle": { "speed_kmh": 87.0 },
  "drivetrain": {
    "current_gear": "D",
    "drive_mode": "SPORT",
    "powertrain_mode": "TOUR",
    "torque": {
      "mode": "MANUAL",
      "current_level": 5,
      "optimal_indicator": "OPTIMAL",
      "regen_contribution_kw": 12.3
    }
  },
  "power": {
    "battery_soc_pct": 71,
    "current_power_kw": 185.0,
    "is_regenerating": false
  },
  "launch": { "state": "IDLE" },
  "binnacle": {
    "left_dial": { "launch_override_active": false },
    "center_dial": { "torque_meter_visible": true },
    "right_dial": { "current_mode": "DYNAMICS" }
  },
  "control_panel": {
    "context": "SETTINGS",
    "multigraph": { "mode": "STOPWATCH", "stopwatch_state": "RUNNING", "stopwatch_value_ms": 14502 }
  }
}
```

**Expected binnacle**: Left dial Giallo (TOUR) showing 185 kW power output. Center dial Rosso-accented ring (SPORT overrides TOUR for ring color), mechanical needle at 87, torque meter active-coaching showing level 5 in OPTIMAL band. Right dial showing Dynamics data. Gear display shows "D" (torque levels are not shown on the gear mini-display). **Expected multigraph**: Stopwatch running, mechanical hand sweeping 60s scale, digital readout showing 14.50s.

---

## 11 — Transferable Design Principles

These principles extend beyond the Ferrari Luce to any complex interactive system:

### 11.1 State Machine Discipline
Every control maps to a finite state machine. There are no ambiguous states — the system always knows exactly where it is and what transitions are valid. If you can't draw the state diagram, you don't understand the interaction.

### 11.2 Precondition-First Design
Build validators before actions. The Lift system checks speed before raising. Launch Control validates a checklist before staging. The Frunk button does nothing at speed — it doesn't throw an error, it doesn't show a modal, it simply does nothing.

### 11.3 Temporal Input Handling
Duration matters. A tap on the gear joystick means NEUTRAL; a hold means DRIVE. Input handlers must track press duration and distinguish between `TAP` and `HOLD` as fundamentally different events.

### 11.4 Semantic Color (Not Decorative)
The palette carries meaning everywhere it appears:
- Yellow = Normal / Active / Standard
- Green = Efficiency / OK / Healthy
- Red = Performance / Warning / Limit
- Grey = Inactive / Disabled / Ghost

If a UI element changes color, its *meaning* has changed.

### 11.5 Animation as Communication
The gear drum scroll isn't decorative — it communicates that gears exist in a sequence and that the system is transitioning through intermediate states. The yellow surge from the key dock communicates that the car is coming alive from a specific physical origin point. Every animation should answer the question: "What is the system doing right now?"

### 11.6 Hybrid Mechanical-Digital as Trust Signal
The most critical readings — speed, time, direction — are expressed through **physical mechanical elements** (needle, hands) even in a fully digital car. Mechanical movement is instinctively trusted. It cannot lag, cannot glitch, cannot freeze while the software reboots. The digital layer adds richness (color, mode overlays, numerics) but the mechanical layer provides the anchor of confidence. When designing high-stakes instruments, consider what deserves physical expression.

### 11.7 Graceful Rejection
Invalid inputs are silently ignored or produce a brief, non-blocking warning. The system never enters an error state, never shows a modal dialog, never requires the user to "dismiss" something before continuing. Design for the driver who just hit the wrong button at 200 km/h.

### 11.8 Multi-Modal Feedback
Every valid input produces feedback across multiple channels simultaneously:
- **Visual**: Screen updates, color shifts, animations
- **Physical**: Haptic vibration, suspension changes, control resistance, mechanical needle/hand movement
- **Audio**: (Implied) confirmation tones, motor note modulation

No input should feel "silent."

### 11.9 Nested State Machines
Complex interactions emerge from layered state machines. Launch Control has an outer machine (IDLE → ARMED → STAGING → LAUNCH) and inner machines (checklist items, brake/throttle percentages, multigraph override, power dial override). The reducer handles all layers coherently because they share one state tree.

### 11.10 System-Driven Overrides
Some transitions are not user-initiated — they are system-driven responses to state changes. Launch Mode auto-overriding the multigraph and power dial is an example. The user didn't ask for the multigraph to switch; the system determined it was contextually necessary. Design for automatic transitions that serve the moment, with clean restoration of previous state when the triggering condition ends.

---

## 12 — Implementation Non-Negotiables

An acceptance checklist. If these behaviors are absent, the implementation does not match the cockpit:

- [ ] **Physical key dock as system root**: Docking the key triggers yellow surge boot animation, display initialization, and mechanical shifter unlock. Undocking reverses everything. All modules depend on key state.
- [ ] **Momentary hardware semantics**: Sticks return to center. Toggles snap back. The UI must not depend on a control "staying" in position.
- [ ] **Drum scroll gear animation**: Gear changes between P, R, N, and D are never instant label swaps. Intermediate gears scroll past as ghosts.
- [ ] **Mechanical needle on center dial**: The center dial has a physical, motor-driven needle for speed. The digital layer must be designed to coexist with (not conflict with) the physical needle.
- [ ] **Mechanical hands on multigraph**: The multigraph clock, stopwatch, and compass modes use physical motor-driven hands on a digital OLED face. This is a hybrid instrument, not a screen.
- [ ] **Multigraph auto-override during Launch**: Entering ARMED auto-switches the multigraph to a 5-second Launch stopwatch. Returning to IDLE restores the previous mode. This is system-driven.
- [ ] **Torque control via paddles, not gear ratios**: This is an EV. Paddles step through torque delivery levels (1–8), not gear numbers. The torque meter above the center dial coaches optimal stepping.
- [ ] **Launch gating with strict reset**: The full IDLE → PRE_ARM → ARMED → STAGING → LAUNCH sequence must be validated step by step. Throttle release during STAGING resets to IDLE, not ARMED. Launch trigger is an overhead pull, not a console button.
- [ ] **Power dial (left) linked to E-Manettino**: Color and scale always track the powertrain mode (RANGE=green, TOUR=yellow, PERFO=red). Launch overrides to orange with expanded scale.
- [ ] **Safety lockouts tied to speed**: Frunk at 0 only. Lift deactivates above 40. P/R gear rejected while moving. Centralized in the reducer.
- [ ] **Theme as mode-derived color, not layout swap**: Changing from TOUR to SPORT recolors accents. It does not change the screen layout.
- [ ] **Stopwatch runs in background**: Timer keeps counting when multigraph mode is cycled away from STOPWATCH. Long-press reset only works from PAUSED.
- [ ] **Control panel articulates**: The control panel can be physically pivoted between driver and co-pilot.
- [ ] **Overhead panel houses launch + lights + defrost + SOS**: These controls are in the headliner, not on the center console.
- [ ] **Right dial cycles 7 modes via dedicated toggle**: The mechanical toggle on the right steering pod (separate from E-Manettino rotary) cycles the right binnacle dial through its data modes.
- [ ] **Binnacle moves with steering wheel**: The entire instrument cluster is fixed to the steering column and rotates with the wheel.
- [ ] **Cross-module event propagation**: Entering R triggers camera overlay. Mode changes propagate to binnacle theme AND control panel labels. Launch suppresses binnacle, overrides power dial and multigraph. Key dock/undock activates/deactivates everything. These are not optional integrations.
