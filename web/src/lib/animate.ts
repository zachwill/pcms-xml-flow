/**
 * WAAPI Animation Utilities
 *
 * Helpers for Web Animations API that persist final styles.
 * Pattern stolen from Silk: commitStyles() + cancel() on finish.
 *
 * @see web/reference/silkhq/05-animations-and-recipes.md
 */

/**
 * Animate an element using WAAPI with automatic style persistence.
 *
 * Solves the common WAAPI annoyance: styles revert after animation ends
 * unless you set fill: "forwards", but then the animation holds a reference.
 *
 * This helper:
 * 1. Runs the animation with fill: "forwards"
 * 2. On finish, commits final styles as inline styles
 * 3. Cancels the animation (releases resources)
 *
 * @example
 * ```tsx
 * // Fade in
 * animate(el, [{ opacity: 0 }, { opacity: 1 }], { duration: 200 });
 *
 * // Slide + fade with easing
 * animate(
 *   el,
 *   [
 *     { transform: "translateX(-20px)", opacity: 0 },
 *     { transform: "translateX(0)", opacity: 1 }
 *   ],
 *   { duration: 300, easing: "ease-out" }
 * );
 *
 * // Await completion for sequencing
 * await animate(el, keyframes, { duration: 200 });
 * setSafeToUnmount(true);
 * ```
 */
export function animate(
  el: HTMLElement | null,
  keyframes: Keyframe[],
  options?: KeyframeAnimationOptions
): Promise<Animation | null> {
  if (!el) return Promise.resolve(null);

  const anim = el.animate(keyframes, {
    ...options,
    fill: "forwards",
  });

  return new Promise((resolve) => {
    anim.onfinish = () => {
      try {
        anim.commitStyles();
      } catch {
        // commitStyles can throw if element is disconnected
      }
      anim.cancel();
      resolve(anim);
    };

    anim.oncancel = () => {
      resolve(null);
    };
  });
}

/**
 * Synchronous version of animate() that returns the Animation object directly.
 * Use when you don't need to await completion.
 */
export function animateSync(
  el: HTMLElement | null,
  keyframes: Keyframe[],
  options?: KeyframeAnimationOptions
): Animation | null {
  if (!el) return null;

  const anim = el.animate(keyframes, {
    ...options,
    fill: "forwards",
  });

  anim.onfinish = () => {
    try {
      anim.commitStyles();
    } catch {
      // commitStyles can throw if element is disconnected
    }
    anim.cancel();
  };

  return anim;
}

/**
 * Generate a CSS calc() expression for interpolating between two values.
 *
 * Useful for progress-driven styles (scroll-linked, transition-linked).
 *
 * @example
 * ```tsx
 * // In a scroll handler or animation frame
 * el.style.opacity = tween("0", "1", progress);
 * el.style.transform = `translateY(${tween("20px", "0px", progress)})`;
 * ```
 */
export function tween(start: string, end: string, progress: number): string {
  return `calc(${start} + (${end} - ${start}) * ${progress})`;
}

/**
 * Apply progress-driven styles to an element.
 *
 * Values can be:
 * - `[start, end]` tuple: interpolated via calc()
 * - `(progress) => value` function: called with current progress
 * - static string/number: applied directly
 *
 * @example
 * ```tsx
 * applyProgressStyles(el, scrollProgress, {
 *   opacity: [0, 1],
 *   transform: (p) => `translateY(${(1 - p) * 20}px)`,
 *   pointerEvents: p > 0.5 ? "auto" : "none",
 * });
 * ```
 */
export function applyProgressStyles(
  el: HTMLElement | null,
  progress: number,
  declarations: Record<
    string,
    | [string, string]
    | ((progress: number) => string | number)
    | string
    | number
  >
): void {
  if (!el) return;

  for (const [prop, value] of Object.entries(declarations)) {
    let computed: string | number;

    if (Array.isArray(value)) {
      const [start, end] = value;
      computed = tween(start, end, progress);
    } else if (typeof value === "function") {
      computed = value(progress);
    } else {
      computed = value;
    }

    // TypeScript doesn't love arbitrary style property access
    (el.style as unknown as Record<string, unknown>)[prop] = computed;
  }
}

/**
 * Common easing curves for animations.
 *
 * These match common UI patterns:
 * - `ease-out`: decelerating (good for entrances)
 * - `ease-in`: accelerating (good for exits)
 * - `ease-in-out`: smooth both ends (good for state changes)
 */
export const easings = {
  // Standard CSS easings
  linear: "linear",
  ease: "ease",
  easeIn: "ease-in",
  easeOut: "ease-out",
  easeInOut: "ease-in-out",

  // Custom curves for UI work
  // Slightly snappier than default ease-out
  snappy: "cubic-bezier(0.2, 0, 0, 1)",
  // Gentle deceleration
  gentle: "cubic-bezier(0.4, 0, 0.2, 1)",
  // Quick start, slow finish (good for overlays)
  overlay: "cubic-bezier(0.32, 0.72, 0, 1)",
} as const;

/**
 * Common durations in milliseconds.
 */
export const durations = {
  instant: 0,
  fast: 100,
  normal: 200,
  slow: 300,
  slower: 500,
} as const;
