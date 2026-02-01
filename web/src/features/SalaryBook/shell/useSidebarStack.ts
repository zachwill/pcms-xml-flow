import { useCallback, useMemo, useState } from "react";

/**
 * useSidebarStack — Manages sidebar entity navigation (intentionally shallow)
 */

export type EntityType = "player" | "agent" | "pick" | "team" | "trade" | "buyout";

interface BaseEntity {
  type: EntityType;
}

export interface PlayerEntity extends BaseEntity {
  type: "player";
  playerId: number;
  playerName: string;
  teamCode: string;
}

export interface AgentEntity extends BaseEntity {
  type: "agent";
  agentId: number;
  agentName: string;
}

export interface PickEntity extends BaseEntity {
  type: "pick";
  teamCode: string;
  draftYear: number;
  draftRound: number;
  rawFragment: string;
}

export interface TeamEntity extends BaseEntity {
  type: "team";
  teamCode: string;
  teamName: string;
}

export interface TradeEntity extends BaseEntity {
  type: "trade";
}

export interface BuyoutEntity extends BaseEntity {
  type: "buyout";
}

export type SidebarEntity =
  | PlayerEntity
  | AgentEntity
  | PickEntity
  | TeamEntity
  | TradeEntity
  | BuyoutEntity;

export type SidebarMode = "default" | "entity";

interface SidebarStackResult {
  mode: SidebarMode;
  currentEntity: SidebarEntity | null;
  stack: SidebarEntity[];
  depth: number;
  push: (entity: SidebarEntity) => void;
  pop: () => void;
  clear: () => void;
  canGoBack: boolean;
  replace: (entity: SidebarEntity) => void;
}

function isTeamEntity(entity: SidebarEntity | undefined): entity is TeamEntity {
  return entity?.type === "team";
}

export function useSidebarStack(): SidebarStackResult {
  const [stack, setStack] = useState<SidebarEntity[]>([]);

  const push = useCallback((entity: SidebarEntity) => {
    setStack((prev) => {
      if (entity.type === "team") return [entity];

      const base = prev[0];
      if (isTeamEntity(base)) return [base, entity];

      return [entity];
    });
  }, []);

  const pop = useCallback(() => {
    setStack((prev) => {
      if (prev.length === 0) return prev;
      if (prev.length === 1) return [];
      return prev.slice(0, 1);
    });
  }, []);

  const clear = useCallback(() => {
    setStack([]);
  }, []);

  const replace = useCallback((entity: SidebarEntity) => {
    setStack((prev) => {
      if (entity.type === "team") return [entity];

      const base = prev[0];
      if (isTeamEntity(base)) return [base, entity];

      return [entity];
    });
  }, []);

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
