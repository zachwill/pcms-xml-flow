import { useCallback, useEffect, useRef, useState } from "react";

/**
 * useScrollSpy — Scroll-driven section tracking with progress
 *
 * Silk-inspired patterns:
 * - Scroll position IS state (not derived from it)
 * - Progress-driven model: exposes 0→1 progress through current section
 * - Lifecycle awareness: idle → scrolling → settling
 * - State-machine based boundary handling with two interaction modes:
 *   1. Top-boundary anchoring mode: Traps small movements near section top
 *   2. Normal scrolling mode: Standard section tracking with minimal hysteresis
 *
 * The "active team" is determined by which section header is currently at/past
 * the sticky threshold. This drives:
 * 1. Sidebar default mode (shows active team context)
 * 2. Team Selector Grid highlight
 * 3. Scroll-linked animations (via sectionProgress)
 *
 * @see web/reference/silkhq/03-scroll-and-gesture-trapping.md
 * @see web/reference/silkhq/02-sheet-system-architecture.md
 */

// ============================================================================
// Types
// ============================================================================

export type ScrollState = "idle" | "scrolling" | "settling";

/**
 * Boundary interaction mode — determines how scroll position maps to active team.
 *
 * - anchored: User is within the anchor zone at the top of a section.
 *             Small movements don't change active team. Provides "stickiness".
 * - committed: User has scrolled beyond the anchor zone (committed to scroll).
 *              Normal section tracking applies.
 */
export type BoundaryMode = "anchored" | "committed";

export interface ScrollSpyOptions {
  /**
   * Offset from container top where sticky headers attach.
   * This is the "threshold line" — sections become active when their top
   * crosses this line.
   */
  topOffset?: number;

  /**
   * Extra pixels below the sticky threshold to switch active team sooner.
   * Useful for making the transition feel more natural (switch before
   * the header is exactly at the sticky position).
   */
  activationOffset?: number;

  /**
   * Scroll container ref. Defaults to window/document if not provided.
   */
  containerRef?: React.RefObject<HTMLElement | null>;

  /**
   * Debounce delay (ms) for detecting scroll end.
   * After this delay with no scroll events, state transitions to "settling".
   */
  scrollEndDelay?: number;

  /**
   * Additional delay (ms) after "settling" before returning to "idle".
   * Allows scroll snap / momentum to complete.
   */
  settleDelay?: number;

  /**
   * Buffer in pixels for UPWARD scroll hysteresis.
   * When scrolling UP near a boundary, the current team stays active until
   * the user scrolls this far past the boundary.
   * This prevents flicker when user subtly scrolls up at the top of a team.
   * Set smaller than before since we now have anchor zones.
   */
  hysteresisBuffer?: number;

  /**
   * Anchor zone size in pixels at the top of each section.
   * Within this zone, small movements (both up and down) are "trapped" —
   * the active team doesn't change until you scroll beyond this zone.
   * This prevents "top-of-page drift" where tiny scrolls expose content.
   */
  anchorZone?: number;

  /**
   * Commitment threshold in pixels. When scrolling upward near a team
   * boundary, the user must scroll at least this far to "commit" to
   * switching to the previous team. Prevents flicker during snap-back.
   */
  commitmentThreshold?: number;

  /**
   * Small range in pixels at the top of a section where progress
   * is forced to 0. Prevents accidental cutoff of top-row content.
   */
  topStickRange?: number;
}

export interface ScrollSpyResult {
  /**
   * Currently active team code (whose header is at/past the sticky threshold).
   * Null if no sections registered or scroll is above all sections.
   */
  activeTeam: string | null;

  /**
   * Progress through the current section: 0 when section just became active,
   * 1 when the next section is about to take over.
   *
   * Use for scroll-linked animations (header fade, parallax, etc).
   * For the last section, progress is based on scroll distance to bottom.
   */
  sectionProgress: number;

  /**
   * Current scroll lifecycle state.
   * - idle: not scrolling
   * - scrolling: actively scrolling (events firing)
   * - settling: scroll ended, waiting for momentum/snap to complete
   */
  scrollState: ScrollState;

  /**
   * Current boundary interaction mode.
   * - anchored: Within anchor zone, small movements trapped
   * - committed: Beyond anchor zone, normal tracking
   */
  boundaryMode: BoundaryMode;

  /**
   * Register a section element for tracking.
   * Call with null to unregister.
   */
  registerSection: (teamCode: string, element: HTMLElement | null) => void;

  /**
   * Programmatically scroll to a team section.
   * Sets activeTeam immediately to prevent flicker during scroll.
   */
  scrollToTeam: (teamCode: string, behavior?: ScrollBehavior) => void;

  /**
   * Manually set active team (for external control).
   * Typically not needed — prefer scrollToTeam.
   */
  setActiveTeam: (teamCode: string) => void;
}

// ============================================================================
// Constants
// ============================================================================

const DEFAULT_SCROLL_END_DELAY = 100;
const DEFAULT_SETTLE_DELAY = 50;

// Reduced from 32px — anchor zone now handles most top-boundary cases
const DEFAULT_HYSTERESIS_BUFFER = 16;

// Anchor zone: ~10px at top of section where small scrolls are "trapped"
const DEFAULT_ANCHOR_ZONE = 10;

// Commitment threshold: user must scroll 20px past boundary to commit to switch
const DEFAULT_COMMITMENT_THRESHOLD = 20;

const DEFAULT_TOP_STICK_RANGE = 12;

// ============================================================================
// Hook Implementation
// ============================================================================

export function useScrollSpy(options: ScrollSpyOptions = {}): ScrollSpyResult {
  const {
    topOffset = 0,
    activationOffset = 0,
    containerRef,
    scrollEndDelay = DEFAULT_SCROLL_END_DELAY,
    settleDelay = DEFAULT_SETTLE_DELAY,
    hysteresisBuffer = DEFAULT_HYSTERESIS_BUFFER,
    anchorZone = DEFAULT_ANCHOR_ZONE,
    commitmentThreshold = DEFAULT_COMMITMENT_THRESHOLD,
    topStickRange = DEFAULT_TOP_STICK_RANGE,
  } = options;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  const [activeTeam, _setActiveTeam] = useState<string | null>(null);
  const activeTeamRef = useRef<string | null>(null);

  const setActiveTeam = useCallback((team: string | null) => {
    activeTeamRef.current = team;
    _setActiveTeam(team);
  }, []);

  const [sectionProgress, setSectionProgress] = useState(0);
  const [scrollState, setScrollState] = useState<ScrollState>("idle");
  const [boundaryMode, setBoundaryMode] = useState<BoundaryMode>("anchored");

  // ---------------------------------------------------------------------------
  // Refs for State Machine
  // ---------------------------------------------------------------------------

  // Registered section elements: teamCode → element
  const sectionsRef = useRef<Map<string, HTMLElement>>(new Map());

  // Sorted section order cache (by DOM position)
  const sortedSectionsRef = useRef<string[]>([]);

  // Timers for scroll state machine
  const scrollEndTimerRef = useRef<number | null>(null);
  const settleTimerRef = useRef<number | null>(null);

  // RAF handle for batching updates
  const rafRef = useRef<number | null>(null);

  // Previous scroll position for direction detection
  const prevScrollTopRef = useRef<number>(0);

  // Track the "anchor point" — where we entered the current section
  // Used to determine if we've scrolled far enough to commit to a switch
  const anchorPointRef = useRef<number | null>(null);

  // Pending team change — used for debounced/committed team switches
  // Prevents flicker by requiring sustained scroll before switching
  const pendingTeamRef = useRef<string | null>(null);

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /**
   * Get scroll metrics for the container.
   */
  const getScrollMetrics = useCallback(() => {
    const container = containerRef?.current;
    const vv = window.visualViewport;

    if (container) {
      return {
        scrollTop: container.scrollTop,
        scrollHeight: container.scrollHeight,
        clientHeight: container.clientHeight,
        containerTop: container.getBoundingClientRect().top,
      };
    }

    // Window scroll — prioritize visualViewport height on mobile
    // to account for keyboard, but fallback to innerHeight/documentElement
    return {
      scrollTop: window.scrollY ?? document.documentElement.scrollTop,
      scrollHeight: document.documentElement.scrollHeight,
      clientHeight: vv ? vv.height : (window.innerHeight ?? document.documentElement.clientHeight),
      containerTop: 0,
    };
  }, [containerRef]);

  /**
   * Get the absolute top position of an element relative to the scroll container.
   */
  const getElementTop = useCallback(
    (element: HTMLElement): number => {
      const rect = element.getBoundingClientRect();
      const metrics = getScrollMetrics();

      if (containerRef?.current) {
        // Relative to scroll container
        return rect.top - metrics.containerTop + metrics.scrollTop;
      }

      // Relative to document
      return rect.top + metrics.scrollTop;
    },
    [containerRef, getScrollMetrics]
  );

  /**
   * Sort sections by their DOM position (top to bottom).
   */
  const updateSortedSections = useCallback(() => {
    const entries = Array.from(sectionsRef.current.entries());

    entries.sort(([, elA], [, elB]) => {
      const topA = getElementTop(elA);
      const topB = getElementTop(elB);
      return topA - topB;
    });

    sortedSectionsRef.current = entries.map(([code]) => code);
  }, [getElementTop]);

  /**
   * Calculate active team, section progress, and boundary mode.
   * Returns [activeTeamCode, progress, boundaryMode].
   *
   * State machine logic:
   * 1. Detect scroll direction (up/down/none)
   * 2. Find "natural" active section (which section header is at threshold)
   * 3. Apply anchor zone logic: if within anchor zone, trap small movements
   * 4. Apply commitment logic: require sustained scroll to switch teams
   * 5. Calculate progress through current section
   */
  const calculateScrollState = useCallback((): [string | null, number, BoundaryMode] => {
    const sections = sectionsRef.current;
    const sortedCodes = sortedSectionsRef.current;

    if (sortedCodes.length === 0) {
      return [null, 0, "anchored"];
    }

    const metrics = getScrollMetrics();
    const currentScrollTop = metrics.scrollTop;
    const threshold = currentScrollTop + topOffset + activationOffset;

    // 1. Detect Scroll Direction
    const prevScrollTop = prevScrollTopRef.current;
    const scrollDelta = currentScrollTop - prevScrollTop;
    const isScrollingUp = scrollDelta < 0;
    const isScrollingDown = scrollDelta > 0;
    prevScrollTopRef.current = currentScrollTop;

    // 2. Find the "Natural" Active Section
    // This is the last section whose top is at or before the threshold.
    let naturalIndex = -1;
    let naturalElement: HTMLElement | null = null;
    let naturalTop = 0;

    for (let i = sortedCodes.length - 1; i >= 0; i--) {
      const code = sortedCodes[i];
      if (!code) continue;

      const element = sections.get(code);
      if (!element) continue;

      const elementTop = getElementTop(element);
      if (elementTop <= threshold) {
        naturalIndex = i;
        naturalElement = element;
        naturalTop = elementTop;
        break;
      }
    }

    // Fallback: If nothing above threshold, default to the first section
    if (naturalIndex === -1 && sortedCodes.length > 0) {
      naturalIndex = 0;
      const firstCode = sortedCodes[0];
      if (firstCode) {
        naturalElement = sections.get(firstCode) ?? null;
        naturalTop = naturalElement ? getElementTop(naturalElement) : 0;
      }
    }

    const naturalCode = sortedCodes[naturalIndex] ?? null;
    const currentActive = activeTeamRef.current;
    const currentIndex = currentActive ? sortedCodes.indexOf(currentActive) : -1;

    // 3. Determine Boundary Mode: Are we in the anchor zone?
    // The anchor zone is a small region at the top of each section where
    // small movements (both up and down) are "trapped" — the active team
    // doesn't change until you scroll beyond this zone.
    const distanceIntoSection = threshold - naturalTop;
    const isInAnchorZone = distanceIntoSection >= 0 && distanceIntoSection < anchorZone;
    let newBoundaryMode: BoundaryMode = isInAnchorZone ? "anchored" : "committed";

    // 4. Resolve Active Team with Commitment Logic
    // Different rules for different scenarios:
    let activeIndex = naturalIndex;

    if (currentActive && naturalIndex !== -1 && naturalIndex !== currentIndex) {
      // Case A: Scrolling UP (Natural choice is ABOVE our current active team)
      if (isScrollingUp && naturalIndex < currentIndex) {
        const currentElement = sections.get(currentActive);
        if (currentElement) {
          const currentTop = getElementTop(currentElement);

          // Set anchor point when we first enter the boundary zone
          if (anchorPointRef.current === null) {
            anchorPointRef.current = currentScrollTop;
          }

          const scrolledDistance = anchorPointRef.current - currentScrollTop;

          // Stay with current team unless:
          // 1. User has scrolled past commitment threshold, OR
          // 2. Current team header has fallen well below threshold
          if (scrolledDistance < commitmentThreshold &&
              currentTop <= threshold + hysteresisBuffer) {
            activeIndex = currentIndex;
            newBoundaryMode = "anchored";
          } else {
            // User has committed to the switch
            anchorPointRef.current = null;
          }
        }
      }
      // Case B: Scrolling DOWN (Natural is below Current)
      // Much less hysteresis needed. Switch immediately but respect anchor zone.
      else if (isScrollingDown && naturalIndex > currentIndex) {
        // If we're in the anchor zone of the new section, stay with current
        // This prevents "top-of-page drift" when scrolling just a tiny bit
        if (isInAnchorZone && distanceIntoSection < anchorZone / 2) {
          activeIndex = currentIndex;
          newBoundaryMode = "anchored";
        } else {
          // Clear anchor point — we've moved to a new section
          anchorPointRef.current = null;
        }
      }
      // Case C: Not actively scrolling (scrollDelta ≈ 0)
      // Keep current team to prevent flicker during micro-adjustments
      else if (Math.abs(scrollDelta) < 1) {
        activeIndex = currentIndex;
      }
    } else {
      // Same section or no previous team — clear anchor point
      if (naturalIndex === currentIndex) {
        // If we've scrolled beyond anchor zone, clear the anchor point
        if (!isInAnchorZone) {
          anchorPointRef.current = null;
        }
      }
    }

    const activeCode = sortedCodes[activeIndex] ?? null;

    // 5. Calculate Progress with "Top Stick" Clamping
    let progress = 0;

    if (activeCode !== null) {
      const activeElement = sections.get(activeCode);

      if (activeElement) {
        const activeTop = getElementTop(activeElement);

        // Find the next section (if any)
        const nextCode = sortedCodes[activeIndex + 1];
        const nextElement = nextCode ? sections.get(nextCode) : null;

        if (nextElement) {
          const nextTop = getElementTop(nextElement);
          const sectionHeight = nextTop - activeTop;

          if (sectionHeight > 0) {
            // Apply Top-Stick: If we are within the stick range, progress is 0.
            const rawDistance = threshold - activeTop;
            const distanceScrolled = rawDistance < topStickRange ? 0 : rawDistance;

            progress = Math.max(0, Math.min(1, distanceScrolled / sectionHeight));

            // Silk pattern: Edge Clamping
            if (progress < 0.05) progress = 0;
            if (progress > 0.95) progress = 1;
          }
        } else {
          // Last section: progress based on scroll to bottom
          const rawDistance = threshold - activeTop;
          const distanceScrolled = rawDistance < topStickRange ? 0 : rawDistance;

          const remainingScroll = metrics.scrollHeight - metrics.clientHeight - activeTop;

          if (remainingScroll > 0) {
            progress = Math.max(0, Math.min(1, distanceScrolled / remainingScroll));

            // Silk pattern: Edge Clamping
            if (progress < 0.05) progress = 0;
            if (progress > 0.95) progress = 1;
          } else {
            progress = 1;
          }
        }
      }
    }

    return [activeCode, progress, newBoundaryMode];
  }, [getScrollMetrics, getElementTop, topOffset, activationOffset, hysteresisBuffer, anchorZone, commitmentThreshold, topStickRange]);

  // ---------------------------------------------------------------------------
  // Scroll State Machine
  // ---------------------------------------------------------------------------

  const clearTimers = useCallback(() => {
    if (scrollEndTimerRef.current !== null) {
      clearTimeout(scrollEndTimerRef.current);
      scrollEndTimerRef.current = null;
    }
    if (settleTimerRef.current !== null) {
      clearTimeout(settleTimerRef.current);
      settleTimerRef.current = null;
    }
  }, []);

  const transitionToSettling = useCallback(() => {
    setScrollState("settling");

    settleTimerRef.current = window.setTimeout(() => {
      setScrollState("idle");
      settleTimerRef.current = null;
    }, settleDelay);
  }, [settleDelay]);

  const handleScrollStart = useCallback(() => {
    clearTimers();
    setScrollState("scrolling");
  }, [clearTimers]);

  const handleScrollContinue = useCallback(() => {
    // Reset the scroll-end timer on each scroll event
    if (scrollEndTimerRef.current !== null) {
      clearTimeout(scrollEndTimerRef.current);
    }

    scrollEndTimerRef.current = window.setTimeout(() => {
      scrollEndTimerRef.current = null;
      transitionToSettling();
    }, scrollEndDelay);
  }, [scrollEndDelay, transitionToSettling]);

  // ---------------------------------------------------------------------------
  // Update Handler
  // ---------------------------------------------------------------------------

  const updateActiveSection = useCallback(() => {
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
    }

    rafRef.current = requestAnimationFrame(() => {
      const [newActiveTeam, newProgress, newBoundaryMode] = calculateScrollState();

      // Only update if value actually changed (prevents unnecessary renders)
      if (activeTeamRef.current !== newActiveTeam) {
        setActiveTeam(newActiveTeam);
      }
      setSectionProgress(newProgress);
      setBoundaryMode(newBoundaryMode);

      rafRef.current = null;
    });
  }, [calculateScrollState, setActiveTeam]);

  // ---------------------------------------------------------------------------
  // Scroll Handler
  // ---------------------------------------------------------------------------

  const handleScroll = useCallback(() => {
    // Update scroll state machine
    if (scrollState === "idle") {
      handleScrollStart();
    }
    handleScrollContinue();

    // Update active section
    updateActiveSection();
  }, [scrollState, handleScrollStart, handleScrollContinue, updateActiveSection]);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  const registerSection = useCallback(
    (teamCode: string, element: HTMLElement | null) => {
      if (element) {
        sectionsRef.current.set(teamCode, element);
      } else {
        sectionsRef.current.delete(teamCode);
      }

      // Re-sort sections after registration change
      updateSortedSections();

      // Update active section if this is the first registration
      if (sectionsRef.current.size === 1 || !element) {
        updateActiveSection();
      }
    },
    [updateSortedSections, updateActiveSection]
  );

  const scrollToTeam = useCallback(
    (teamCode: string, behavior: ScrollBehavior = "instant") => {
      const element = sectionsRef.current.get(teamCode);
      if (!element) return;

      // Set active team immediately to prevent flicker
      setActiveTeam(teamCode);
      setSectionProgress(0);
      setBoundaryMode("anchored");

      // Reset state machine refs for clean transition
      anchorPointRef.current = null;
      pendingTeamRef.current = null;

      // Perform the scroll
      const targetTop = getElementTop(element) - topOffset;
      const scrollTarget = containerRef?.current ?? window;

      if (scrollTarget === window) {
        const maxScroll = document.documentElement.scrollHeight - window.innerHeight;
        const clampedTop = Math.max(0, Math.min(targetTop, maxScroll));
        window.scrollTo({ top: clampedTop, behavior });
      } else if (containerRef?.current) {
        const container = containerRef.current;
        const maxScroll = container.scrollHeight - container.clientHeight;
        const clampedTop = Math.max(0, Math.min(targetTop, maxScroll));
        container.scrollTo({ top: clampedTop, behavior });
      }
    },
    [containerRef, topOffset, getElementTop, setActiveTeam]
  );

  // ---------------------------------------------------------------------------
  // Effects
  // ---------------------------------------------------------------------------

  // Set up scroll listener
  useEffect(() => {
    const scrollTarget = containerRef?.current ?? window;

    scrollTarget.addEventListener("scroll", handleScroll, { passive: true });

    // Initial calculation
    updateSortedSections();
    updateActiveSection();

    return () => {
      scrollTarget.removeEventListener("scroll", handleScroll);

      // Cleanup timers
      clearTimers();

      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [containerRef, handleScroll, updateSortedSections, updateActiveSection, clearTimers]);

  // ---------------------------------------------------------------------------
  // Return
  // ---------------------------------------------------------------------------

  return {
    activeTeam,
    sectionProgress,
    scrollState,
    boundaryMode,
    registerSection,
    scrollToTeam,
    setActiveTeam,
  };
}
