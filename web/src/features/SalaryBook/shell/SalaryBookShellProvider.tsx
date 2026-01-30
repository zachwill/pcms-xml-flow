import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { useRegisterFilterChangeHandlers } from "@/state/filters";
import { useScrollSpy, type ScrollState } from "./useScrollSpy";
import { TEAM_ORDER, sortTeamsByOrder } from "./teamOrder";
import {
  useSidebarStack,
  type SidebarEntity,
  type SidebarMode,
} from "./useSidebarStack";

// ============================================================================
// Context Types
// ============================================================================

const INITIAL_TEAMS = sortTeamsByOrder(["ATL", "BKN", "BOS", "POR"]);

export interface ShellScrollContextValue {
  // Canvas ref (scroll container)
  canvasRef: React.RefObject<HTMLDivElement | null>;

  // Scroll-spy state
  activeTeam: string | null;
  scrollState: ScrollState;
  registerSection: (teamCode: string, element: HTMLElement | null) => void;
  scrollToTeam: (teamCode: string, behavior?: ScrollBehavior) => void;
}

export interface ShellSidebarContextValue {
  sidebarMode: SidebarMode;
  currentEntity: SidebarEntity | null;
  pushEntity: (entity: SidebarEntity) => void;
  popEntity: () => void;
  clearStack: () => void;
  canGoBack: boolean;
}

export interface ShellTeamsContextValue {
  loadedTeams: string[];
  setLoadedTeams: (teams: string[]) => void;
}

const ShellScrollContext = createContext<ShellScrollContextValue | null>(null);
const ShellSidebarContext = createContext<ShellSidebarContextValue | null>(null);
const ShellTeamsContext = createContext<ShellTeamsContextValue | null>(null);

// ============================================================================
// Hooks
// ============================================================================

export function useShellScrollContext() {
  const ctx = useContext(ShellScrollContext);
  if (!ctx) {
    throw new Error("useShellScrollContext must be used within <SalaryBookShellProvider>");
  }
  return ctx;
}

export function useShellSidebarContext() {
  const ctx = useContext(ShellSidebarContext);
  if (!ctx) {
    throw new Error("useShellSidebarContext must be used within <SalaryBookShellProvider>");
  }
  return ctx;
}

export function useShellTeamsContext() {
  const ctx = useContext(ShellTeamsContext);
  if (!ctx) {
    throw new Error("useShellTeamsContext must be used within <SalaryBookShellProvider>");
  }
  return ctx;
}

// ============================================================================
// Provider
// ============================================================================

export interface SalaryBookShellProviderProps {
  children: ReactNode;

  /** Sticky threshold offset INSIDE the scroll container (typically 0). */
  topOffset?: number;

  /** Switch context sooner than exact sticky handoff. */
  activationOffset?: number;
}

export function SalaryBookShellProvider({
  children,
  topOffset = 0,
  activationOffset = 0,
}: SalaryBookShellProviderProps) {
  const canvasRef = useRef<HTMLDivElement>(null);

  // ---------------------------------------------------------------------------
  // Scroll-spy
  // ---------------------------------------------------------------------------

  const { activeTeam, scrollState, registerSection, scrollToTeam } =
    useScrollSpy({
      topOffset,
      activationOffset,
      containerRef: canvasRef,
    });

  // ---------------------------------------------------------------------------
  // Sync scroll state to DOM (Silk pattern for performant CSS-based updates)
  // ---------------------------------------------------------------------------

  useEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    el.setAttribute("data-scroll-state", scrollState);
  }, [scrollState]);

  // ---------------------------------------------------------------------------
  // Filter-change scroll preservation
  // ---------------------------------------------------------------------------

  const activeTeamBeforeFilterChangeRef = useRef<string | null>(null);

  // Track registered section elements for filter-change restoration
  const sectionElementsRef = useRef<Map<string, HTMLElement>>(new Map());

  const registerSectionWithTracking = useCallback(
    (teamCode: string, element: HTMLElement | null) => {
      if (element) {
        sectionElementsRef.current.set(teamCode, element);
      } else {
        sectionElementsRef.current.delete(teamCode);
      }
      registerSection(teamCode, element);
    },
    [registerSection]
  );

  const handleBeforeFilterChange = useCallback(() => {
    activeTeamBeforeFilterChangeRef.current = activeTeam;
  }, [activeTeam]);

  const handleAfterFilterChange = useCallback(() => {
    const teamToRestore = activeTeamBeforeFilterChangeRef.current;
    if (!teamToRestore) return;

    const element = sectionElementsRef.current.get(teamToRestore);
    if (!element) {
      activeTeamBeforeFilterChangeRef.current = null;
      return;
    }

    scrollToTeam(teamToRestore, "instant");
    activeTeamBeforeFilterChangeRef.current = null;
  }, [scrollToTeam]);

  const filterChangeHandlers = useMemo(
    () => ({
      onBeforeChange: handleBeforeFilterChange,
      onAfterChange: handleAfterFilterChange,
    }),
    [handleBeforeFilterChange, handleAfterFilterChange]
  );

  useRegisterFilterChangeHandlers(filterChangeHandlers);

  // ---------------------------------------------------------------------------
  // Sidebar stack
  // ---------------------------------------------------------------------------

  const { mode: sidebarMode, currentEntity, push, pop, clear, canGoBack } =
    useSidebarStack();

  // ---------------------------------------------------------------------------
  // Loaded teams state
  // ---------------------------------------------------------------------------

  const [loadedTeams, setLoadedTeams] = useState<string[]>(INITIAL_TEAMS);

  useEffect(() => {
    let timeoutId: number | null = null;
    let intervalId: number | null = null;

    timeoutId = window.setTimeout(() => {
      intervalId = window.setInterval(() => {
        setLoadedTeams((prev) => {
          const remaining = TEAM_ORDER.filter((team) => !prev.includes(team));
          if (remaining.length === 0) {
            if (intervalId !== null) {
              clearInterval(intervalId);
              intervalId = null;
            }
            return prev;
          }

          const nextChunk = remaining.slice(0, 4);
          return sortTeamsByOrder([...prev, ...nextChunk]);
        });
      }, 500);
    }, 4000);

    return () => {
      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }
      if (intervalId !== null) {
        clearInterval(intervalId);
      }
    };
  }, []);

  // ---------------------------------------------------------------------------
  // Context values
  // ---------------------------------------------------------------------------

  const scrollValue = useMemo<ShellScrollContextValue>(
    () => ({
      canvasRef,
      activeTeam,
      scrollState,
      registerSection: registerSectionWithTracking,
      scrollToTeam,
    }),
    [
      activeTeam,
      scrollState,
      registerSectionWithTracking,
      scrollToTeam,
    ]
  );

  const sidebarValue = useMemo<ShellSidebarContextValue>(
    () => ({
      sidebarMode,
      currentEntity,
      pushEntity: push,
      popEntity: pop,
      clearStack: clear,
      canGoBack,
    }),
    [sidebarMode, currentEntity, push, pop, clear, canGoBack]
  );

  const teamsValue = useMemo<ShellTeamsContextValue>(
    () => ({
      loadedTeams,
      setLoadedTeams,
    }),
    [loadedTeams]
  );

  return (
    <ShellScrollContext.Provider value={scrollValue}>
      <ShellTeamsContext.Provider value={teamsValue}>
        <ShellSidebarContext.Provider value={sidebarValue}>
          {children}
        </ShellSidebarContext.Provider>
      </ShellTeamsContext.Provider>
    </ShellScrollContext.Provider>
  );
}
