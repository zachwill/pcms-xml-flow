import { useCallback, useEffect, useRef, useState } from "react";

/**
 * useScrollSpy — Scroll-driven section tracking with progress
 *
 * Silk-inspired patterns:
 * - Scroll position IS state (not derived from it)
 * - Progress-driven model: exposes 0→1 progress through current section
 * - Lifecycle awareness: idle → scrolling → settling
 * - CACHED POSITIONS: avoid getBoundingClientRect() during scroll (layout thrashing)
 *
 * The "active team" is determined by which section header is currently at/past
 * the sticky threshold. This drives:
 * 1. Sidebar default mode (shows active team context)
 * 2. Team Selector Grid highlight
 * 3. Scroll-linked animations (internal progress tracking)
 *
 * @see web/reference/silkhq/03-scroll-and-gesture-trapping.md
 */

// ============================================================================
// Types
// ============================================================================

export type ScrollState = "idle" | "scrolling" | "settling";

interface CachedSection {
  code: string;
  top: number; // Absolute top position relative to scroll container
}

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

}

// ============================================================================
// Constants
// ============================================================================

const DEFAULT_SCROLL_END_DELAY = 100;
const DEFAULT_SETTLE_DELAY = 50;
const FADE_THRESHOLD = 0.8;

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
  const [scrollState, setScrollState] = useState<ScrollState>("idle");
  
  // sectionProgress is a ref, not state — updating it every frame would cause re-renders
  const sectionProgressRef = useRef(0);

  // ---------------------------------------------------------------------------
  // Refs
  // ---------------------------------------------------------------------------

  // Registered section elements: teamCode → element
  const sectionsRef = useRef<Map<string, HTMLElement>>(new Map());

  // CACHED positions: sorted array of { code, top }
  // Only updated on registration changes, resize, or explicit invalidation
  const cachedSectionsRef = useRef<CachedSection[]>([]);

  // Cache for scroll container metrics (updated on resize)
  const containerMetricsRef = useRef<{
    scrollHeight: number;
    clientHeight: number;
  }>({ scrollHeight: 0, clientHeight: 0 });

  // Timers for scroll state machine
  const scrollEndTimerRef = useRef<number | null>(null);
  const settleTimerRef = useRef<number | null>(null);

  // RAF handle for batching updates
  const rafRef = useRef<number | null>(null);

  // Flag to prevent re-renders during active scroll
  const isScrollingRef = useRef(false);

  // Last known active team (to avoid unnecessary state updates)
  const lastActiveTeamRef = useRef<string | null>(null);

  // Pending scroll target (used when section isn't registered yet)
  const pendingScrollRef = useRef<{
    teamCode: string;
    behavior: ScrollBehavior;
  } | null>(null);

  // Force active team during programmatic navigation to avoid flicker
  const forcedActiveTeamRef = useRef<string | null>(null);
  const forcedActiveTargetRef = useRef<number | null>(null);

  const clearForcedActive = useCallback(() => {
    forcedActiveTeamRef.current = null;
    forcedActiveTargetRef.current = null;
  }, []);

  // ---------------------------------------------------------------------------
  // Position Caching (only called on mount/resize/registration, NOT during scroll)
  // ---------------------------------------------------------------------------

  /**
   * Recalculate and cache all section positions.
   * This is the ONLY place we call getBoundingClientRect().
   * Called on: mount, resize, section registration changes.
   */
  const rebuildPositionCache = useCallback(() => {
    const container = containerRef?.current;
    const sections = sectionsRef.current;

    if (sections.size === 0) {
      cachedSectionsRef.current = [];
      clearForcedActive();
      return;
    }

    // Get container's current scroll position and bounds
    const scrollTop = container?.scrollTop ?? window.scrollY ?? 0;
    const containerTop = container?.getBoundingClientRect().top ?? 0;

    // Build position cache
    const cached: CachedSection[] = [];

    sections.forEach((element, code) => {
      const rect = element.getBoundingClientRect();
      // Convert viewport-relative to scroll-container-relative absolute position
      const absoluteTop = container
        ? rect.top - containerTop + scrollTop
        : rect.top + scrollTop;

      cached.push({ code, top: absoluteTop });
    });

    // Sort by position (top to bottom)
    cached.sort((a, b) => a.top - b.top);

    cachedSectionsRef.current = cached;

    if (forcedActiveTeamRef.current) {
      const forcedSection = cached.find(
        (section) => section.code === forcedActiveTeamRef.current
      );
      if (!forcedSection) {
        clearForcedActive();
      } else {
        forcedActiveTargetRef.current = forcedSection.top - topOffset;
      }
    }

    // Also cache container metrics
    if (container) {
      containerMetricsRef.current = {
        scrollHeight: container.scrollHeight,
        clientHeight: container.clientHeight,
      };
    } else {
      containerMetricsRef.current = {
        scrollHeight: document.documentElement.scrollHeight,
        clientHeight: window.innerHeight,
      };
    }
  }, [containerRef, clearForcedActive, topOffset]);

  // ---------------------------------------------------------------------------
  // Fast Scroll Calculation (uses cached positions only, NO DOM reads)
  // ---------------------------------------------------------------------------

  /**
   * Calculate active team and progress using ONLY cached positions.
   * No getBoundingClientRect() calls — pure math from scrollTop.
   */
  const calculateFromCache = useCallback((): [string | null, number] => {
    const cached = cachedSectionsRef.current;
    if (cached.length === 0) {
      return [null, 0];
    }

    // Read scrollTop (this is cheap, no layout forced)
    const container = containerRef?.current;
    const scrollTop = container?.scrollTop ?? window.scrollY ?? 0;
    const threshold = scrollTop + topOffset + activationOffset;

    // Binary search would be faster for many sections, but linear is fine for ~30
    let activeIndex = 0;
    for (let i = cached.length - 1; i >= 0; i--) {
      const section = cached[i];
      if (section && section.top <= threshold) {
        activeIndex = i;
        break;
      }
    }

    const activeSection = cached[activeIndex];
    if (!activeSection) {
      return [null, 0];
    }

    // Calculate progress
    let progress = 0;
    const nextSection = cached[activeIndex + 1];

    if (nextSection) {
      const sectionHeight = nextSection.top - activeSection.top;
      if (sectionHeight > 0) {
        const distanceScrolled = threshold - activeSection.top;
        progress = Math.max(0, Math.min(1, distanceScrolled / sectionHeight));
      }
    } else {
      // Last section: progress based on distance to bottom
      const { scrollHeight, clientHeight } = containerMetricsRef.current;
      const maxScroll = scrollHeight - clientHeight;
      const distanceScrolled = threshold - activeSection.top;
      const remainingDistance = maxScroll - activeSection.top;

      if (remainingDistance > 0) {
        progress = Math.max(0, Math.min(1, distanceScrolled / remainingDistance));
      } else {
        progress = 1;
      }
    }

    return [activeSection.code, progress];
  }, [containerRef, topOffset, activationOffset]);

  const applyFadedSections = useCallback((activeCode: string | null, progress: number) => {
    const cached = cachedSectionsRef.current;
    if (cached.length === 0) return;

    if (!activeCode) {
      cached.forEach((section) => {
        const el = sectionsRef.current.get(section.code);
        if (el) {
          el.removeAttribute("data-faded");
        }
      });
      return;
    }

    const activeIndex = cached.findIndex((s) => s.code === activeCode);

    cached.forEach((section, index) => {
      const el = sectionsRef.current.get(section.code);
      if (!el) return;

      const shouldFade =
        activeIndex !== -1 &&
        (index < activeIndex || (index === activeIndex && progress >= FADE_THRESHOLD));

      if (shouldFade) {
        el.setAttribute("data-faded", "");
      } else {
        el.removeAttribute("data-faded");
      }
    });
  }, []);

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
    isScrollingRef.current = false;
    setScrollState("settling");

    settleTimerRef.current = window.setTimeout(() => {
      setScrollState("idle");
      settleTimerRef.current = null;
    }, settleDelay);
  }, [settleDelay]);

  const handleScrollStart = useCallback(() => {
    clearTimers();
    isScrollingRef.current = true;
    setScrollState("scrolling");
  }, [clearTimers]);

  const handleScrollContinue = useCallback(() => {
    if (scrollEndTimerRef.current !== null) {
      clearTimeout(scrollEndTimerRef.current);
    }

    scrollEndTimerRef.current = window.setTimeout(() => {
      scrollEndTimerRef.current = null;
      transitionToSettling();
    }, scrollEndDelay);
  }, [scrollEndDelay, transitionToSettling]);

  // ---------------------------------------------------------------------------
  // Scroll Handler (optimized: minimal work, no layout reads)
  // ---------------------------------------------------------------------------

  const handleScroll = useCallback(() => {
    // State machine transitions
    if (!isScrollingRef.current) {
      handleScrollStart();
    }
    handleScrollContinue();

    // Debounce via RAF — only one calculation per frame
    if (rafRef.current !== null) {
      return; // Already have a pending update
    }

    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null;

      const forcedActiveTeam = forcedActiveTeamRef.current;
      const forcedTargetTop = forcedActiveTargetRef.current;

      if (forcedActiveTeam) {
        const container = containerRef?.current;
        const scrollTop = container?.scrollTop ?? window.scrollY ?? 0;
        const tolerance = 2;

        if (
          forcedTargetTop === null ||
          Math.abs(scrollTop - forcedTargetTop) > tolerance
        ) {
          return;
        }

        clearForcedActive();
      }

      const [newActiveTeam, newProgress] = calculateFromCache();
      const prevActiveTeam = lastActiveTeamRef.current;
      const prevProgress = sectionProgressRef.current;

      // Store progress in ref
      sectionProgressRef.current = newProgress;

      // =====================================================================
      // CSS-driven fading: only update data-faded attributes at boundaries
      // =====================================================================
      const crossedThreshold =
        (prevProgress < FADE_THRESHOLD && newProgress >= FADE_THRESHOLD) ||
        (prevProgress >= FADE_THRESHOLD && newProgress < FADE_THRESHOLD);
      const teamChanged = newActiveTeam !== prevActiveTeam;

      if (teamChanged || crossedThreshold) {
        applyFadedSections(newActiveTeam, newProgress);
      }

      // Only update React state if activeTeam actually changed
      if (teamChanged) {
        lastActiveTeamRef.current = newActiveTeam;
        setActiveTeam(newActiveTeam);
      }
    });
  }, [
    handleScrollStart,
    handleScrollContinue,
    calculateFromCache,
    applyFadedSections,
    clearForcedActive,
    containerRef,
  ]);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  const performScrollToTeam = useCallback(
    (teamCode: string, behavior: ScrollBehavior): number | null => {
      const cached = cachedSectionsRef.current.find((s) => s.code === teamCode);
      if (!cached) return null;

      const targetTop = cached.top - topOffset;
      const container = containerRef?.current;

      if (container) {
        const maxScroll = container.scrollHeight - container.clientHeight;
        container.scrollTo({
          top: Math.max(0, Math.min(targetTop, maxScroll)),
          behavior,
        });
      } else {
        const maxScroll =
          document.documentElement.scrollHeight - window.innerHeight;
        window.scrollTo({
          top: Math.max(0, Math.min(targetTop, maxScroll)),
          behavior,
        });
      }

      return targetTop;
    },
    [containerRef, topOffset]
  );

  const registerSection = useCallback(
    (teamCode: string, element: HTMLElement | null) => {
      if (element) {
        sectionsRef.current.set(teamCode, element);
      } else {
        sectionsRef.current.delete(teamCode);
      }

      // Rebuild cache after registration change
      // Use RAF to batch multiple rapid registrations
      requestAnimationFrame(() => {
        rebuildPositionCache();

        // Recalculate active team if we haven't set one yet or on unregistration
        if (lastActiveTeamRef.current === null || !element) {
          const [newActive, newProgress] = calculateFromCache();
          if (newActive) {
            lastActiveTeamRef.current = newActive;
            sectionProgressRef.current = newProgress;
            setActiveTeam(newActive);
            applyFadedSections(newActive, newProgress);
          }
        }

        const pending = pendingScrollRef.current;
        if (pending) {
          const targetTop = performScrollToTeam(
            pending.teamCode,
            pending.behavior
          );
          if (targetTop !== null) {
            forcedActiveTargetRef.current = targetTop;
            pendingScrollRef.current = null;
          }
        }
      });
    },
    [
      rebuildPositionCache,
      calculateFromCache,
      applyFadedSections,
      performScrollToTeam,
    ]
  );

  const scrollToTeam = useCallback(
    (teamCode: string, behavior: ScrollBehavior = "instant") => {
      // Set active team immediately to prevent flicker
      lastActiveTeamRef.current = teamCode;
      setActiveTeam(teamCode);
      sectionProgressRef.current = 0;
      applyFadedSections(teamCode, 0);

      clearForcedActive();
      forcedActiveTeamRef.current = teamCode;

      const targetTop = performScrollToTeam(teamCode, behavior);
      if (targetTop === null) {
        pendingScrollRef.current = { teamCode, behavior };
      } else {
        forcedActiveTargetRef.current = targetTop;
        pendingScrollRef.current = null;
      }
    },
    [applyFadedSections, performScrollToTeam, clearForcedActive]
  );

  // ---------------------------------------------------------------------------
  // Effects
  // ---------------------------------------------------------------------------

  // Set up scroll listener + resize observer
  useEffect(() => {
    const container = containerRef?.current;
    const scrollTarget = container ?? window;

    // Initial cache build
    rebuildPositionCache();

    // Initial active section
    const [initialActive, initialProgress] = calculateFromCache();
    lastActiveTeamRef.current = initialActive;
    sectionProgressRef.current = initialProgress;
    setActiveTeam(initialActive);
    applyFadedSections(initialActive, initialProgress);

    // Scroll listener (passive for perf)
    scrollTarget.addEventListener("scroll", handleScroll, { passive: true });

    // Resize observer to rebuild cache on size changes
    const resizeObserver = new ResizeObserver(() => {
      // Debounce resize handling
      requestAnimationFrame(() => {
        rebuildPositionCache();
      });
    });

    if (container) {
      resizeObserver.observe(container);
    } else {
      resizeObserver.observe(document.documentElement);
    }

    // Also listen for window resize (for non-container scroll)
    const handleResize = () => {
      requestAnimationFrame(() => {
        rebuildPositionCache();
      });
    };
    window.addEventListener("resize", handleResize, { passive: true });

    return () => {
      scrollTarget.removeEventListener("scroll", handleScroll);
      resizeObserver.disconnect();
      window.removeEventListener("resize", handleResize);
      clearTimers();
      clearForcedActive();

      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [
    containerRef,
    handleScroll,
    rebuildPositionCache,
    calculateFromCache,
    applyFadedSections,
    clearTimers,
    clearForcedActive,
  ]);

  // ---------------------------------------------------------------------------
  // Return
  // ---------------------------------------------------------------------------

  return {
    activeTeam,
    scrollState,
    registerSection,
    scrollToTeam,
  };
}
