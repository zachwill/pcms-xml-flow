import { useCallback, useMemo, useState } from "react";

/**
 * useSidebarStack — Manages sidebar entity navigation (intentionally shallow)
 *
 * Problem this solves:
 * - The sidebar should NOT behave like a browser history where every click
 *   adds another "Back" step.
 *
 * Intended UX:
 * - Default Mode: show TeamContext (driven by scroll-spy)
 * - Entity Mode: show ONE detail entity (player/agent/pick/team)
 * - Clicking another entity swaps the detail view (doesn't push deeper)
 * - Back returns to the team context in a single step
 *
 * Optional exception:
 * - If a user pins a Team entity (team detail), we allow ONE additional
 *   detail entity on top of that pinned team, so Back returns to the pinned
 *   team (and another Back returns to scroll-spy context).
 *
 * This means the internal "stack" is capped to:
 * - []
 * - [entity]
 * - [teamEntity, entity]
 */

/** Entity types that can be pushed onto the sidebar */
export type EntityType = "player" | "agent" | "pick" | "team";

/** Base entity structure */
interface BaseEntity {
  type: EntityType;
}

/** Player entity pushed when clicking a player row */
export interface PlayerEntity extends BaseEntity {
  type: "player";
  playerId: number;
  playerName: string;
  teamCode: string;
}

/** Agent entity pushed when clicking an agent name */
export interface AgentEntity extends BaseEntity {
  type: "agent";
  agentId: number;
  agentName: string;
}

/** Pick entity pushed when clicking a draft pick pill */
export interface PickEntity extends BaseEntity {
  type: "pick";
  teamCode: string;
  draftYear: number;
  draftRound: number;
  rawFragment: string;
}

/**
 * Team entity pushed when clicking team name in header
 * Unlike default mode, this is "pinned" and won't change on scroll.
 */
export interface TeamEntity extends BaseEntity {
  type: "team";
  teamCode: string;
  teamName: string;
}

/** Union type for all pushable entities */
export type SidebarEntity = PlayerEntity | AgentEntity | PickEntity | TeamEntity;

/** Current sidebar mode */
export type SidebarMode = "default" | "entity";

interface SidebarStackResult {
  /** Current sidebar mode: default (team context) or entity (detail view) */
  mode: SidebarMode;

  /** Current entity being displayed (null in default mode) */
  currentEntity: SidebarEntity | null;

  /** Internal stack (capped at 2; useful for future breadcrumbs/debugging) */
  stack: SidebarEntity[];

  /** Stack depth (0 = default mode) */
  depth: number;

  /** Open an entity in the sidebar (shallow; typically replaces current) */
  push: (entity: SidebarEntity) => void;

  /** Back (pops to pinned team, or to default mode) */
  pop: () => void;

  /** Clear entire stack (return to default mode) */
  clear: () => void;

  /** Check if we can go back */
  canGoBack: boolean;

  /** Replace current entity (alias of push for now; preserves pinned team base) */
  replace: (entity: SidebarEntity) => void;
}

function isTeamEntity(entity: SidebarEntity | undefined): entity is TeamEntity {
  return entity?.type === "team";
}

export function useSidebarStack(): SidebarStackResult {
  const [stack, setStack] = useState<SidebarEntity[]>([]);

  /**
   * Push (shallow navigation)
   *
   * Rules:
   * - Clicking a team pins that team: [team]
   * - If a team is pinned as the base, clicking a non-team entity shows it on top: [team, entity]
   * - Otherwise, clicking any entity replaces what you're looking at: [entity]
   */
  const push = useCallback((entity: SidebarEntity) => {
    setStack((prev) => {
      // Pinning a team always resets to that team
      if (entity.type === "team") return [entity];

      // If there's a pinned team base, keep it and swap/insert the detail entity
      const base = prev[0];
      if (isTeamEntity(base)) return [base, entity];

      // Otherwise: single-step detail navigation
      return [entity];
    });
  }, []);

  /**
   * Pop (Back)
   * - [team, entity] -> [team]
   * - [entity] -> []
   */
  const pop = useCallback(() => {
    setStack((prev) => {
      if (prev.length === 0) return prev;
      if (prev.length === 1) return [];
      // length 2 (capped) => return base
      return prev.slice(0, 1);
    });
  }, []);

  /** Clear to default mode */
  const clear = useCallback(() => {
    setStack([]);
  }, []);

  /**
   * Replace current entity.
   *
   * Today this behaves like `push`, but we keep the method for API stability
   * and to make intent explicit for callers.
   */
  const replace = useCallback((entity: SidebarEntity) => {
    setStack((prev) => {
      if (entity.type === "team") return [entity];

      const base = prev[0];
      if (isTeamEntity(base)) return [base, entity];

      return [entity];
    });
  }, []);

  // Derived state
  const mode: SidebarMode = stack.length > 0 ? "entity" : "default";
  const currentEntity: SidebarEntity | null = stack.length > 0 ? stack[stack.length - 1]! : null;
  const canGoBack = stack.length > 0;
  const depth = stack.length;

  return useMemo<SidebarStackResult>(
    () => ({
      mode,
      currentEntity,
      stack,
      depth,
      push,
      pop,
      clear,
      canGoBack,
      replace,
    }),
    [mode, currentEntity, stack, depth, push, pop, clear, canGoBack, replace]
  );
}
