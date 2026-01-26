/**
 * MainCanvas — Main scrollable canvas component
 *
 * Renders all team sections in a single vertical scroll container.
 * The scroll position drives the scroll-spy active team detection.
 */

import { cx } from "@/lib/utils";
import { useShellContext } from "@/state/shell";
import { TeamSection } from "./TeamSection";

export interface MainCanvasProps {
  /** Optional additional className */
  className?: string;
}

/** Main scrollable canvas - renders all team sections */
export function MainCanvas({ className }: MainCanvasProps) {
  const { canvasRef, loadedTeams } = useShellContext();

  return (
    <div
      ref={canvasRef}
      className={cx(
        "flex-1 overflow-y-auto overflow-x-hidden",
        "bg-background relative",
        "overscroll-y-contain", // Prevent scroll chaining to parent/body
        className
      )}
      style={{
        isolation: "isolate",
        WebkitOverflowScrolling: "touch", // iOS momentum scrolling
        scrollSnapType: "y mandatory",
      }}
    >
      {/* Team sections will be rendered here */}
      <div className="min-h-full">
        {loadedTeams.length === 0 ? (
          <div className="flex items-center justify-center h-96 text-muted-foreground">
            No teams loaded. Select teams from the Team Selector Grid.
          </div>
        ) : (
          <div className="space-y-0">
            {loadedTeams.map((teamCode) => (
              <TeamSection key={teamCode} teamCode={teamCode} />
            ))}

            {/*
              Small scroll spacer so the last team header can still reach the sticky position
              without adding a huge blank tail at the end of the list.
            */}
            <div aria-hidden className="h-8" />
          </div>
        )}
      </div>
    </div>
  );
}
