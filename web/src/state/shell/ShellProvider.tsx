import React, {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { useRegisterFilterChangeHandlers } from "@/state/filters";
import { useScrollSpy, type ScrollState } from "./useScrollSpy";
import {
  useSidebarStack,
  type SidebarEntity,
  type SidebarMode,
} from "./useSidebarStack";

// ============================================================================
// Context Types
// ============================================================================

export interface ShellContextValue {
  // Canvas ref (scroll container)
  canvasRef: React.RefObject<HTMLDivElement | null>;

  // Scroll-spy state
  activeTeam: string | null;
  sectionProgress: number;
  scrollState: ScrollState;
  registerSection: (teamCode: string, element: HTMLElement | null) => void;
  scrollToTeam: (teamCode: string, behavior?: ScrollBehavior) => void;

  // Sidebar stack state
  sidebarMode: SidebarMode;
  currentEntity: SidebarEntity | null;
  pushEntity: (entity: SidebarEntity) => void;
  popEntity: () => void;
  clearStack: () => void;
  canGoBack: boolean;

  // Loaded teams
  loadedTeams: string[];
  setLoadedTeams: (teams: string[]) => void;
}

const ShellContext = createContext<ShellContextValue | null>(null);

// ============================================================================
// Hook
// ============================================================================

export function useShellContext() {
  const ctx = useContext(ShellContext);
  if (!ctx) {
    throw new Error("useShellContext must be used within <ShellProvider>");
  }
  return ctx;
}

// ============================================================================
// Provider
// ============================================================================

export interface ShellProviderProps {
  children: ReactNode;

  /** Sticky threshold offset INSIDE the scroll container (typically 0). */
  topOffset?: number;

  /** Switch context sooner than exact sticky handoff. */
  activationOffset?: number;
}

export function ShellProvider({
  children,
  topOffset = 0,
  activationOffset = 0,
}: ShellProviderProps) {
  const canvasRef = useRef<HTMLDivElement>(null);

  // ---------------------------------------------------------------------------
  // Scroll-spy
  // ---------------------------------------------------------------------------

  const {
    activeTeam,
    sectionProgress,
    scrollState,
    registerSection,
    scrollToTeam,
  } = useScrollSpy({
    topOffset,
    activationOffset,
    containerRef: canvasRef,
  });

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

  const [loadedTeams, setLoadedTeams] = useState<string[]>([
    "ATL",
    "BKN",
    "BOS",
    "CHA",
    "CHI",
    "CLE",
    "DAL",
    "DEN",
    "DET",
    "GSW",
    "HOU",
    "IND",
    "LAC",
    "LAL",
    "MEM",
    "MIA",
    "MIL",
    "MIN",
    "NOP",
    "NYK",
    "OKC",
    "ORL",
    "PHI",
    "PHX",
    "POR",
    "SAC",
    "SAS",
    "TOR",
    "UTA",
    "WAS",
  ]);

  // ---------------------------------------------------------------------------
  // Context value
  // ---------------------------------------------------------------------------

  const value = useMemo<ShellContextValue>(
    () => ({
      canvasRef,
      activeTeam,
      sectionProgress,
      scrollState,
      registerSection: registerSectionWithTracking,
      scrollToTeam,
      sidebarMode,
      currentEntity,
      pushEntity: push,
      popEntity: pop,
      clearStack: clear,
      canGoBack,
      loadedTeams,
      setLoadedTeams,
    }),
    [
      activeTeam,
      sectionProgress,
      scrollState,
      registerSectionWithTracking,
      scrollToTeam,
      sidebarMode,
      currentEntity,
      push,
      pop,
      clear,
      canGoBack,
      loadedTeams,
    ]
  );

  return <ShellContext.Provider value={value}>{children}</ShellContext.Provider>;
}
