import React, { type ReactNode } from "react";

export interface ThreePaneFrameProps {
  /** Optional header slot (typically fixed). */
  header?: ReactNode;
  /** Main scrollable surface. */
  main: ReactNode;
  /** Optional right-hand panel. */
  right?: ReactNode;
  /** Offset in pixels to push main/right below a fixed header. */
  headerHeight?: number;
}

/**
 * ThreePaneFrame — dumb layout frame
 *
 * Provides a fixed viewport scaffold with header/main/right slots.
 * The header is rendered as-is; callers own its positioning.
 */
export function ThreePaneFrame({
  header,
  main,
  right,
  headerHeight = 0,
}: ThreePaneFrameProps) {
  const contentOffset = header && headerHeight > 0 ? `${headerHeight}px` : undefined;

  return (
    <div className="h-screen w-screen flex flex-col overflow-hidden bg-background">
      {header}

      <div
        className="flex flex-1 overflow-hidden relative"
        style={{ marginTop: contentOffset, zIndex: 0 }}
      >
        {main}
        {right}
      </div>
    </div>
  );
}
