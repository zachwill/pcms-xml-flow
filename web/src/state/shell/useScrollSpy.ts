import { useCallback, useEffect, useRef, useState } from "react";

/**
 * useScrollSpy — Tracks which team section header is currently sticky
 *
 * The "active team" is determined by which team's header is currently in the
 * sticky position at the top of the scroll container. This drives:
 * 1. Team Selector Grid highlight (no flicker)
 * 2. Sidebar default mode content (shows active team context)
 */

interface ScrollSpyOptions {
  /** Offset from top where sticky headers attach (accounts for fixed header outside the scroll container) */
  topOffset?: number;

  /**
   * Extra pixels BELOW the sticky threshold to switch the active team a bit sooner.
   */
  activationOffset?: number;

  /** Scroll container ref - defaults to document if not provided */
  containerRef?: React.RefObject<HTMLElement | null>;
}

interface ScrollSpyResult {
  /** Currently active team code (team whose header is sticky) */
  activeTeam: string | null;
  /** Register a team section element for observation */
  registerSection: (teamCode: string, element: HTMLElement | null) => void;
  /** Manually set active team (e.g., after jump-to-team navigation) */
  setActiveTeam: (teamCode: string) => void;
  /** Scroll to a specific team section */
  scrollToTeam: (teamCode: string, behavior?: ScrollBehavior) => void;
}

export function useScrollSpy(options: ScrollSpyOptions = {}): ScrollSpyResult {
  const { topOffset = 0, activationOffset = 0, containerRef } = options;

  const [activeTeam, setActiveTeam] = useState<string | null>(null);

  const sectionsRef = useRef<Map<string, HTMLElement>>(new Map());
  const intersectionRatiosRef = useRef<Map<string, number>>(new Map());
  const observerRef = useRef<IntersectionObserver | null>(null);
  const pendingUpdateRef = useRef<number | null>(null);

  const isScrollingProgrammaticallyRef = useRef<boolean>(false);
  const programmaticScrollSettleTimeoutRef = useRef<number | null>(null);
  const programmaticScrollMaxTimeoutRef = useRef<number | null>(null);
  const removeProgrammaticScrollListenerRef = useRef<(() => void) | null>(null);

  const calculateActiveTeam = useCallback(() => {
    const container = containerRef?.current ?? document.documentElement;
    const scrollTop =
      containerRef?.current?.scrollTop ??
      window.scrollY ??
      document.documentElement.scrollTop;

    const threshold = scrollTop + topOffset + activationOffset + 1;

    let activeCode: string | null = null;
    let closestDistance = Infinity;

    sectionsRef.current.forEach((element, teamCode) => {
      const rect = element.getBoundingClientRect();
      const containerRect = containerRef?.current?.getBoundingClientRect();
      const elementTop = containerRef?.current
        ? rect.top - (containerRect?.top ?? 0) + (containerRef.current.scrollTop ?? 0)
        : rect.top + scrollTop;

      if (elementTop <= threshold) {
        const distance = threshold - elementTop;
        if (distance < closestDistance) {
          closestDistance = distance;
          activeCode = teamCode;
        }
      }
    });

    if (!activeCode && sectionsRef.current.size > 0) {
      let topmostCode: string | null = null;
      let topmostTop = Infinity;
      sectionsRef.current.forEach((element, teamCode) => {
        const rect = element.getBoundingClientRect();
        const elementTop = containerRef?.current
          ? rect.top - (containerRef.current.getBoundingClientRect()?.top ?? 0)
          : rect.top;

        if (elementTop < topmostTop) {
          topmostTop = elementTop;
          topmostCode = teamCode;
        }
      });
      activeCode = topmostCode;
    }

    return activeCode;
  }, [containerRef, topOffset, activationOffset]);

  const updateActiveTeam = useCallback(() => {
    if (isScrollingProgrammaticallyRef.current) return;

    if (pendingUpdateRef.current !== null) {
      cancelAnimationFrame(pendingUpdateRef.current);
    }

    pendingUpdateRef.current = requestAnimationFrame(() => {
      const newActiveTeam = calculateActiveTeam();
      setActiveTeam((prev) => (prev !== newActiveTeam ? newActiveTeam : prev));
      pendingUpdateRef.current = null;
    });
  }, [calculateActiveTeam]);

  const registerSection = useCallback(
    (teamCode: string, element: HTMLElement | null) => {
      if (element) {
        sectionsRef.current.set(teamCode, element);

        if (observerRef.current) {
          observerRef.current.observe(element);
        }

        if (sectionsRef.current.size === 1) {
          updateActiveTeam();
        }
      } else {
        const existingElement = sectionsRef.current.get(teamCode);
        if (existingElement && observerRef.current) {
          observerRef.current.unobserve(existingElement);
        }
        sectionsRef.current.delete(teamCode);
        intersectionRatiosRef.current.delete(teamCode);
      }
    },
    [updateActiveTeam]
  );

  const scrollToTeam = useCallback(
    (teamCode: string, behavior: ScrollBehavior = "smooth") => {
      const element = sectionsRef.current.get(teamCode);
      if (!element) return;

      setActiveTeam(teamCode);

      isScrollingProgrammaticallyRef.current = true;

      removeProgrammaticScrollListenerRef.current?.();
      removeProgrammaticScrollListenerRef.current = null;

      const scrollTarget: HTMLElement | Window = containerRef?.current ?? window;

      const clearTimers = () => {
        if (programmaticScrollSettleTimeoutRef.current !== null) {
          clearTimeout(programmaticScrollSettleTimeoutRef.current);
          programmaticScrollSettleTimeoutRef.current = null;
        }
        if (programmaticScrollMaxTimeoutRef.current !== null) {
          clearTimeout(programmaticScrollMaxTimeoutRef.current);
          programmaticScrollMaxTimeoutRef.current = null;
        }
      };

      const finish = () => {
        if (!isScrollingProgrammaticallyRef.current) return;

        isScrollingProgrammaticallyRef.current = false;

        removeProgrammaticScrollListenerRef.current?.();
        removeProgrammaticScrollListenerRef.current = null;

        clearTimers();
        updateActiveTeam();
      };

      const scheduleSettleCheck = () => {
        if (programmaticScrollSettleTimeoutRef.current !== null) {
          clearTimeout(programmaticScrollSettleTimeoutRef.current);
        }
        programmaticScrollSettleTimeoutRef.current = window.setTimeout(finish, 120);
      };

      const onProgrammaticScroll = () => {
        scheduleSettleCheck();
      };

      scrollTarget.addEventListener("scroll", onProgrammaticScroll, { passive: true } as any);
      removeProgrammaticScrollListenerRef.current = () => {
        scrollTarget.removeEventListener("scroll", onProgrammaticScroll as any);
        clearTimers();
      };

      const nudgePx = 1;

      if (scrollTarget === window) {
        const rect = element.getBoundingClientRect();
        const rawBase = window.scrollY + rect.top - topOffset;
        const rawTarget = rawBase <= 0 ? rawBase : rawBase + nudgePx;
        const maxScrollTop = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
        const target = Math.min(Math.max(0, rawTarget), maxScrollTop);
        window.scrollTo({ top: target, behavior });
      } else if (containerRef?.current) {
        const containerEl = containerRef.current;
        const containerRect = containerEl.getBoundingClientRect();
        const rect = element.getBoundingClientRect();
        const rawBase = containerEl.scrollTop + (rect.top - containerRect.top) - topOffset;
        const rawTarget = rawBase <= 0 ? rawBase : rawBase + nudgePx;
        const maxScrollTop = Math.max(0, containerEl.scrollHeight - containerEl.clientHeight);
        const target = Math.min(Math.max(0, rawTarget), maxScrollTop);
        containerEl.scrollTo({ top: target, behavior });
      }

      scheduleSettleCheck();

      programmaticScrollMaxTimeoutRef.current = window.setTimeout(
        finish,
        behavior === "smooth" ? 2000 : 250
      );
    },
    [containerRef, topOffset, updateActiveTeam]
  );

  useEffect(() => {
    const scrollTarget = containerRef?.current ?? window;

    observerRef.current = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          sectionsRef.current.forEach((element, teamCode) => {
            if (element === entry.target) {
              intersectionRatiosRef.current.set(teamCode, entry.intersectionRatio);
            }
          });
        });

        updateActiveTeam();
      },
      {
        root: containerRef?.current ?? null,
        rootMargin: `-${topOffset + activationOffset}px 0px 0px 0px`,
        threshold: [0, 0.1, 0.5, 0.9, 1],
      }
    );

    sectionsRef.current.forEach((element) => {
      observerRef.current?.observe(element);
    });

    const handleScroll = () => {
      updateActiveTeam();
    };

    scrollTarget.addEventListener("scroll", handleScroll, { passive: true });

    updateActiveTeam();

    return () => {
      if (observerRef.current) {
        observerRef.current.disconnect();
        observerRef.current = null;
      }

      scrollTarget.removeEventListener("scroll", handleScroll);

      if (pendingUpdateRef.current !== null) {
        cancelAnimationFrame(pendingUpdateRef.current);
      }

      isScrollingProgrammaticallyRef.current = false;

      removeProgrammaticScrollListenerRef.current?.();
      removeProgrammaticScrollListenerRef.current = null;

      if (programmaticScrollSettleTimeoutRef.current !== null) {
        clearTimeout(programmaticScrollSettleTimeoutRef.current);
        programmaticScrollSettleTimeoutRef.current = null;
      }

      if (programmaticScrollMaxTimeoutRef.current !== null) {
        clearTimeout(programmaticScrollMaxTimeoutRef.current);
        programmaticScrollMaxTimeoutRef.current = null;
      }
    };
  }, [containerRef, topOffset, activationOffset, updateActiveTeam]);

  return {
    activeTeam,
    registerSection,
    setActiveTeam,
    scrollToTeam,
  };
}
