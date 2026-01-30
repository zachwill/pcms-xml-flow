import { useCallback, useEffect, useRef, useState } from "react";
import { animate, durations, easings } from "@/lib/animate";
import type { SidebarEntity } from "./useSidebarStack";

/**
 * useSidebarTransition — Manages entity transitions with safe-to-unmount lifecycle
 *
 * Silk pattern: Separate "open" from "safe to unmount".
 * - When pushing: new entity appears immediately, animates in
 * - When popping: old entity animates out, THEN unmounts
 * - When replacing: crossfade (old out, new in simultaneously)
 *
 * This prevents "content disappears before animation finishes".
 *
 * @see web/reference/silkhq/02-sheet-system-architecture.md
 * @see web/reference/silkhq/AGENTS.md (patterns we steal)
 */

export type TransitionState =
  | "idle"           // No entity, nothing animating
  | "entering"       // Entity animating in
  | "present"        // Entity fully visible
  | "exiting"        // Entity animating out
  | "replacing";     // Old entity exiting while new enters

interface SidebarTransitionResult {
  /**
   * The entity to render (may be the outgoing entity during exit animation).
   * Render if this is non-null.
   */
  stagedEntity: SidebarEntity | null;

  /**
   * Current transition state for styling/accessibility.
   */
  transitionState: TransitionState;

  /**
   * Ref to attach to the entity detail container for animations.
   */
  containerRef: React.RefObject<HTMLDivElement | null>;

  /**
   * Whether content is safe to unmount (animation complete).
   * Use: render if `currentEntity || !safeToUnmount`
   */
  safeToUnmount: boolean;
}

interface TransitionConfig {
  /** Duration for enter animation in ms */
  enterDuration?: number;
  /** Duration for exit animation in ms */
  exitDuration?: number;
  /** Easing for enter animation */
  enterEasing?: string;
  /** Easing for exit animation */
  exitEasing?: string;
}

const defaultConfig: Required<TransitionConfig> = {
  enterDuration: durations.normal,
  exitDuration: durations.fast,
  enterEasing: easings.easeOut,
  exitEasing: easings.easeIn,
};

export function useSidebarTransition(
  currentEntity: SidebarEntity | null,
  config: TransitionConfig = {}
): SidebarTransitionResult {
  const {
    enterDuration,
    exitDuration,
    enterEasing,
    exitEasing,
  } = { ...defaultConfig, ...config };

  // The entity currently being rendered (may lag behind currentEntity during exit)
  const [stagedEntity, setStagedEntity] = useState<SidebarEntity | null>(currentEntity);
  const [transitionState, setTransitionState] = useState<TransitionState>(
    currentEntity ? "present" : "idle"
  );
  const [safeToUnmount, setSafeToUnmount] = useState(true);

  const containerRef = useRef<HTMLDivElement>(null);

  // Track the previous entity for comparison
  const prevEntityRef = useRef<SidebarEntity | null>(currentEntity);

  // Track in-flight animations so we can cancel them
  const animationRef = useRef<Animation | null>(null);

  const cancelCurrentAnimation = useCallback(() => {
    if (animationRef.current) {
      animationRef.current.cancel();
      animationRef.current = null;
    }
  }, []);

  // Enter animation keyframes
  const enterKeyframes: Keyframe[] = [
    { opacity: 0, transform: "translateX(8px)" },
    { opacity: 1, transform: "translateX(0)" },
  ];

  // Exit animation keyframes
  const exitKeyframes: Keyframe[] = [
    { opacity: 1, transform: "translateX(0)" },
    { opacity: 0, transform: "translateX(8px)" },
  ];

  useEffect(() => {
    const prevEntity = prevEntityRef.current;
    const hasEntity = currentEntity !== null;
    const hadEntity = prevEntity !== null;

    // Same entity (or both null) - no transition needed
    if (currentEntity === prevEntity) {
      return;
    }

    // Check if it's the same entity by type and ID
    const isSameEntity =
      hasEntity &&
      hadEntity &&
      prevEntity.type === currentEntity.type &&
      getEntityId(prevEntity) === getEntityId(currentEntity);

    if (isSameEntity) {
      // Same entity, just update ref
      prevEntityRef.current = currentEntity;
      return;
    }

    cancelCurrentAnimation();

    // Case 1: No entity -> Has entity (PUSH)
    if (!hadEntity && hasEntity) {
      setStagedEntity(currentEntity);
      setSafeToUnmount(false);
      setTransitionState("entering");

      // Animate in on next frame (after mount)
      requestAnimationFrame(() => {
        const el = containerRef.current;
        if (!el) {
          setTransitionState("present");
          setSafeToUnmount(true);
          return;
        }

        animate(el, enterKeyframes, {
          duration: enterDuration,
          easing: enterEasing,
        }).then(() => {
          setTransitionState("present");
          setSafeToUnmount(true);
        });
      });
    }

    // Case 2: Has entity -> No entity (POP)
    else if (hadEntity && !hasEntity) {
      setSafeToUnmount(false);
      setTransitionState("exiting");

      const el = containerRef.current;
      if (!el) {
        setStagedEntity(null);
        setTransitionState("idle");
        setSafeToUnmount(true);
      } else {
        animate(el, exitKeyframes, {
          duration: exitDuration,
          easing: exitEasing,
        }).then(() => {
          setStagedEntity(null);
          setTransitionState("idle");
          setSafeToUnmount(true);
        });
      }
    }

    // Case 3: Has entity -> Different entity (REPLACE)
    else if (hadEntity && hasEntity) {
      setSafeToUnmount(false);
      setTransitionState("replacing");

      const el = containerRef.current;
      if (!el) {
        setStagedEntity(currentEntity);
        setTransitionState("present");
        setSafeToUnmount(true);
      } else {
        // Exit old, then enter new
        animate(el, exitKeyframes, {
          duration: exitDuration,
          easing: exitEasing,
        }).then(() => {
          setStagedEntity(currentEntity);

          // Enter new on next frame
          requestAnimationFrame(() => {
            const newEl = containerRef.current;
            if (!newEl) {
              setTransitionState("present");
              setSafeToUnmount(true);
              return;
            }

            setTransitionState("entering");
            animate(newEl, enterKeyframes, {
              duration: enterDuration,
              easing: enterEasing,
            }).then(() => {
              setTransitionState("present");
              setSafeToUnmount(true);
            });
          });
        });
      }
    }

    prevEntityRef.current = currentEntity;
  }, [
    currentEntity,
    cancelCurrentAnimation,
    enterDuration,
    exitDuration,
    enterEasing,
    exitEasing,
  ]);

  return {
    stagedEntity,
    transitionState,
    containerRef,
    safeToUnmount,
  };
}

/**
 * Get a stable ID for an entity (for comparison)
 */
function getEntityId(entity: SidebarEntity): string {
  switch (entity.type) {
    case "player":
      return `player-${entity.playerId}`;
    case "agent":
      return `agent-${entity.agentId}`;
    case "pick":
      return `pick-${entity.teamCode}-${entity.draftYear}-${entity.draftRound}`;
    case "team":
      return `team-${entity.teamCode}`;
  }
}
