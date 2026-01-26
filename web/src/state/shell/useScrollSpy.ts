import { useCallback, useEffect, useRef, useState } from "react";

/**
 * useScrollSpy — Scroll-driven section tracking with progress
 *
 * Silk-inspired patterns:
 * - Scroll position IS state (not derived from it)
 * - Progress-driven model: exposes 0→1 progress through current section
 * - Lifecycle awareness: idle → scrolling → settling
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
   * Buffer in pixels for "active team hysteresis".
   * Prevents rapid flipping between sections when near a boundary.
   * If a team is active, it stays active until the user has scrolled
   * this far past the boundary.
   */
  hysteresisBuffer?: number;

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
const DEFAULT_HYSTERESIS_BUFFER = 32;
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

  // ---------------------------------------------------------------------------
  // Refs
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
   * Calculate active team and section progress.
   * Returns [activeTeamCode, progress].
   */
  const calculateScrollState = useCallback((): [string | null, number] => {
    const sections = sectionsRef.current;
    const sortedCodes = sortedSectionsRef.current;

    if (sortedCodes.length === 0) {
      return [null, 0];
    }

    const metrics = getScrollMetrics();
    const threshold = metrics.scrollTop + topOffset + activationOffset;

    // 1. Find the "Natural" Active Section
    // This is the last section whose top is at or before the threshold.
    let naturalIndex = -1;
    for (let i = sortedCodes.length - 1; i >= 0; i--) {
      const code = sortedCodes[i];
      if (!code) continue;

      const element = sections.get(code);
      if (!element) continue;

      const elementTop = getElementTop(element);
      if (elementTop <= threshold) {
        naturalIndex = i;
        break;
      }
    }

    // 2. Resolve Active Team with Hysteresis (Upward-Biased Gravity)
    // Silk pattern: A section stays active even when its header has moved 
    // slightly below the threshold, but only when scrolling UP.
    // This prevents "boundary chatter" during scroll snaps.
    const currentActive = activeTeamRef.current;
    let activeIndex = naturalIndex;

    if (currentActive && naturalIndex !== -1) {
      const currentIndex = sortedCodes.indexOf(currentActive);
      
      // Case: Scrolling UP (Natural choice is ABOVE our current active team)
      if (naturalIndex < currentIndex) {
        const currentElement = sections.get(currentActive);
        if (currentElement) {
          const currentTop = getElementTop(currentElement);
          
          // Stick to the current team if its header is still "close" to the top
          // (i.e. it hasn't fallen more than hysteresisBuffer pixels down)
          if (currentTop <= threshold + hysteresisBuffer) {
            activeIndex = currentIndex;
          }
        }
      }
      // Case: Scrolling DOWN (Natural is below Current)
      // No hysteresis applied; the next team takes over immediately.
    }

    // Fallback: If nothing above threshold, default to the first section
    if (activeIndex === -1 && sortedCodes.length > 0) {
      activeIndex = 0;
    }

    const activeCode = sortedCodes[activeIndex] ?? null;

    // 3. Calculate Progress with "Top Stick" Clamping
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

    return [activeCode, progress];
  }, [getScrollMetrics, getElementTop, topOffset, activationOffset, hysteresisBuffer, topStickRange]);

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
      const [newActiveTeam, newProgress] = calculateScrollState();

      setActiveTeam((prev) => (prev !== newActiveTeam ? newActiveTeam : prev));
      setSectionProgress(newProgress);

      rafRef.current = null;
    });
  }, [calculateScrollState]);

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
    [containerRef, topOffset, getElementTop]
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
    registerSection,
    scrollToTeam,
    setActiveTeam,
  };
}
