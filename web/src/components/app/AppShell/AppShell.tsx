import React, { type ReactNode } from "react";

import { ThreePaneFrame } from "@/layouts/ThreePaneFrame";

export interface AppShellProps {
  /** Optional header slot. */
  header?: ReactNode;
  /** Main surface. */
  main: ReactNode;
  /** Optional right-hand panel (legacy name: sidebar). */
  sidebar?: ReactNode;
  /** Header offset in pixels. */
  headerHeight?: number;
}

/**
 * AppShell — Legacy wrapper around ThreePaneFrame
 *
 * Kept for compatibility; new views should use ThreePaneFrame directly.
 */
export function AppShell({
  header,
  main,
  sidebar,
  headerHeight,
}: AppShellProps) {
  return (
    <ThreePaneFrame
      header={header}
      main={main}
      right={sidebar}
      headerHeight={headerHeight}
    />
  );
}
