import React, { type ReactNode } from "react";

import { ShellProvider } from "@/state/shell";
import { TopNav } from "@/components/app/TopNav/TopNav";

export interface AppShellProps {
  main: ReactNode;
  sidebar: ReactNode;
}

/**
 * AppShell — The invariant application layout
 *
 * - Fixed top navigation / filters header
 * - Single vertical scroll canvas (main)
 * - Intelligence sidebar (right)
 */
export function AppShell({ main, sidebar }: AppShellProps) {
  return (
    <ShellProvider topOffset={0}>
      <div className="h-screen w-screen flex flex-col overflow-hidden bg-background">
        <TopNav />

        <div
          className="flex flex-1 overflow-hidden relative"
          style={{ marginTop: "130px", zIndex: 0 }}
        >
          {main}
          {sidebar}
        </div>
      </div>
    </ShellProvider>
  );
}
