# 10 - Examples in this repo (composition patterns)

These examples show the intended way to build "real components" on top of Silk primitives.

General pattern repeated across examples:

1. Wrap `Sheet.Root` to provide a stable "design system component" name.
2. Set a small set of opinionated defaults:
   - `license="commercial"` (required by API)
   - `nativeEdgeSwipePrevention={true}` for iOS
   - `contentPlacement` + optional `tracks`
   - `swipeOvershoot={false}` for side/page-like interactions
3. Wrap `Sheet.Backdrop`/`Sheet.Content` to attach your classes.
4. Re-export "unchanged" subcomponents for convenience.

## BottomSheet (`src/components/BottomSheet/BottomSheet.tsx`)

Key defaults:
- View: `nativeEdgeSwipePrevention={true}`
- Backdrop: `themeColorDimming="auto"`
- Content: includes `<Sheet.BleedingBackground />`
- Handle: default `action="dismiss"`

Takeaway:
- BottomSheet is mostly styling + a few safety defaults.

## DetachedSheet (`src/components/DetachedSheet/DetachedSheet.tsx`)

Pattern:
- switch between bottom and centered + dual tracks based on viewport size.

Backdrop:
- custom `travelAnimation.opacity` capped at 0.2.

Takeaway:
- use `tracks={["top","bottom"]}` for a "detached floating modal" feel on large screens.

## Sidebar (`src/components/Sidebar/Sidebar.tsx`)

Key defaults:
- Root: `sheetRole="dialog"`
- View: `contentPlacement="left"`, `swipeOvershoot={false}`

Accessibility:
- uses `VisuallyHidden.Root` to mount Title + Dismiss Trigger without visual UI.

Takeaway:
- treat sidebar as a dialog for assistive tech.

## Page (`src/components/Page/Page.tsx`)

Key defaults:
- View: `contentPlacement="right"`, `swipeOvershoot={false}`

Takeaway:
- "page" is just a sheet with side travel and no overshoot.

## Toast (`src/components/Toast/Toast.tsx`)

This example is important because it exercises non-modal overlay behavior.

Key defaults:
- Root: controlled `presented` state + `sheetRole=""` (effectively no dialog role)
- View: `inertOutside={false}`
- View: disables focus stealing and dismissal:
  - `onPresentAutoFocus={{ focus:false }}`
  - `onDismissAutoFocus={{ focus:false }}`
  - `onClickOutside.dismiss=false`
  - `onEscapeKeyDown.dismiss=false`

Interactive content:
- wraps content with `Sheet.SpecialWrapper` to keep pointer interactions sane.

Auto-close logic:
- closes after 5s only when:
  - presented AND travelStatus == "idleInside" AND pointer not over

Takeaway:
- Toast is a "Sheet used as a non-modal animated surface", not a dialog.

## SheetWithKeyboard (`src/components/SheetWithKeyboard/SheetWithKeyboard.tsx`)

Key defaults:
- on small screens: bottom placement
- on large screens: center placement + dual tracks
- `swipeOvershoot={false}`

Special technique:
- in `onTravel`, while progress < 0.999, focuses the View element to dismiss the on-screen keyboard.

Takeaway:
- you can integrate keyboard dismissal with travel events.

## SheetWithStacking (`src/components/SheetWithStacking/SheetWithStacking.tsx`)

Demonstrates:
- `SheetStack.Root` as a parent container.
- each sheet uses `forComponent="closest"`.
- responsive placement (right vs bottom).
- custom `stackingAnimation` on Content (translate + scale + transformOrigin)

Takeaway:
- stacking animations should be tuned for placement axis.

## SheetWithDetent (`src/components/SheetWithDetent/SheetWithDetent.tsx`)

Demonstrates detent-based progressive disclosure with embedded scrolling.

Key defaults:
- View: starts with `detents="66vh"`, switches to `undefined` (full) once last detent reached
- View: `swipeOvershoot={false}`
- Handle: `action` switches from `"step"` to `"dismiss"` when `reachedLastDetent`

Important patterns:
- Uses `onTravelRangeChange` to detect when `range.start === 2` (last detent)
- Uses `onTravel` to dismiss keyboard when `progress < 0.999` by focusing the View element
- Embeds `Scroll.Root` > `Scroll.View` > `Scroll.Content` inside Sheet.Content

Scroll integration:
- `Scroll.View scrollGestureTrap={{ yEnd: true }}` — traps end-of-scroll to prevent sheet swipe
- `Scroll.View scrollGesture={!reachedLastDetent ? false : "auto"}` — disables scroll until expanded
- `Scroll.View safeArea="layout-viewport"` — respects layout viewport bounds
- `Scroll.View onScrollStart={{ dismissKeyboard: true }}` — auto-dismiss keyboard on scroll

Takeaway:
- Detent + scroll integration requires careful state coordination between Sheet and Scroll.

## LongSheet (`src/components/LongSheet/LongSheet.tsx`)

Demonstrates dynamic track switching based on scroll position inside the sheet.

Key defaults:
- View: `contentPlacement="center"`, initial `tracks="bottom"`
- View: custom `enteringAnimationSettings` (spring with high stiffness/damping)
- View: `swipeOvershoot={false}`

Key pattern:
- Content embeds a `Scroll.Root` > `Scroll.View` > `Scroll.Content`
- `onScroll` checks `progress < 0.5` to switch track between `"bottom"` and `"top"`
- When `travelStatus === "idleOutside"`, track resets to `"bottom"`

Takeaway:
- Tracks can be changed dynamically based on internal scroll position for "tall content" scenarios.

## TopSheet (`src/components/TopSheet/TopSheet.tsx`)

A minimal sheet variant that enters from the top.

Key defaults:
- View: `contentPlacement="top"`
- View: `nativeEdgeSwipePrevention={true}`
- Content: includes `Sheet.BleedingBackground`

Takeaway:
- TopSheet is the simplest placement variant — just flip `contentPlacement` to `"top"`.

## PageFromBottom (`src/components/PageFromBottom/PageFromBottom.tsx`)

A full-page overlay that slides up but has **no swipe dismissal**.

Key defaults:
- View: `contentPlacement="bottom"`, `swipe={false}`
- View: `nativeEdgeSwipePrevention={true}`
- Backdrop: `travelAnimation={{ opacity: [0, 0.1] }}` — subtle dim

Content structure:
- Includes a top bar with a `Sheet.Trigger action="dismiss"` close button
- Swipe is disabled, so user must tap the button to dismiss

Takeaway:
- Use `swipe={false}` for page-like overlays where gesture dismissal is undesirable.

## Card (`src/components/Card/Card.tsx`)

A centered modal with scale animation (zoom-in effect).

Key defaults:
- View: `contentPlacement="center"`, `tracks="top"`
- View: custom spring `enteringAnimationSettings` (low stiffness, bouncy feel)
- Content: `travelAnimation={{ scale: [0.8, 1] }}` — scales from 80% to 100%
- Backdrop: uses function syntax `opacity: ({ progress }) => Math.min(0.4 * progress, 0.4)`

Takeaway:
- Center + scale animation creates a classic modal/dialog feel.
- Function syntax for `travelAnimation` allows clamping and custom easing.

## Overall insight from examples

The library is intentionally low-level.

Silk's primitives provide:
- mechanics (travel, swipe, focus, inert)

Your app provides:
- meaning (bottom sheet vs sidebar vs toast)
- visuals (CSS)
- policy decisions (dismissal behavior, roles, overshoot)
