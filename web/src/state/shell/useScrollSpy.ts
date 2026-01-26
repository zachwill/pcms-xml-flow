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
 * @see web/reference/silkhq/07-scroll-and-scrolltrap.md
 * @see web/reference/silkhq/04-sheet-runtime-model.md
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
  } = options;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  const [activeTeam, setActiveTeam] = useState<string | null>(null);
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

    if (container) {
      return {
        scrollTop: container.scrollTop,
        scrollHeight: container.scrollHeight,
        clientHeight: container.clientHeight,
        containerTop: container.getBoundingClientRect().top,
      };
    }

    // Window scroll
    return {
      scrollTop: window.scrollY ?? document.documentElement.scrollTop,
      scrollHeight: document.documentElement.scrollHeight,
      clientHeight: window.innerHeight,
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

    // Find the active section: last section whose top is at or before threshold
    let activeCode: string | null = null;
    let activeIndex = -1;

    for (let i = sortedCodes.length - 1; i >= 0; i--) {
      const code = sortedCodes[i];
      if (!code) continue;

      const element = sections.get(code);
      if (!element) continue;

      const elementTop = getElementTop(element);

      if (elementTop <= threshold) {
        activeCode = code;
        activeIndex = i;
        break;
      }
    }

    // If nothing found, use the first section (we're above all sections)
    if (activeCode === null && sortedCodes.length > 0) {
      const firstCode = sortedCodes[0];
      if (firstCode) {
        activeCode = firstCode;
        activeIndex = 0;
      }
    }

    // Calculate progress through the active section
    let progress = 0;

    if (activeCode !== null) {
      const activeElement = sections.get(activeCode);

      if (activeElement) {
        const activeTop = getElementTop(activeElement);

        // Find the next section (if any)
        const nextCode = sortedCodes[activeIndex + 1];
        const nextElement = nextCode ? sections.get(nextCode) : null;

        if (nextElement) {
          // Progress = how far from active top to next top
          const nextTop = getElementTop(nextElement);
          const sectionHeight = nextTop - activeTop;

          if (sectionHeight > 0) {
            const distanceScrolled = threshold - activeTop;
            progress = Math.max(0, Math.min(1, distanceScrolled / sectionHeight));
          }
        } else {
          // Last section: progress based on scroll to bottom
          const distanceScrolled = threshold - activeTop;
          const remainingScroll = metrics.scrollHeight - metrics.clientHeight - activeTop;

          if (remainingScroll > 0) {
            progress = Math.max(0, Math.min(1, distanceScrolled / remainingScroll));
          } else {
            progress = 1;
          }
        }
      }
    }

    return [activeCode, progress];
  }, [getScrollMetrics, getElementTop, topOffset, activationOffset]);

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
