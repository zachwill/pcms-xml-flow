import { useLayoutEffect, useRef, useState } from "react";
import { cx, focusRing } from "@/lib/utils";

type TabId = "cap-outlook" | "team-stats";

/**
 * Tab toggle for switching between Cap Outlook and Team Stats
 *
 * Features a sliding indicator that animates between tabs (Silk-inspired pattern).
 * The indicator is a separate element that slides behind the buttons, creating
 * a more fluid transition than instant background swaps.
 *
 * Animation uses WAAPI with our animate() helper for smooth motion + persistent styles.
 */
export function TabToggle({
  activeTab,
  onTabChange,
}: {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}) {
  const tabs: { id: TabId; label: string }[] = [
    { id: "cap-outlook", label: "Cap Outlook" },
    { id: "team-stats", label: "Team Stats" },
  ];

  // Refs for measuring positions
  const containerRef = useRef<HTMLDivElement>(null);
  const indicatorRef = useRef<HTMLDivElement>(null);
  const tabRefs = useRef<Map<TabId, HTMLButtonElement>>(new Map());

  // Track whether we've done initial positioning (skip animation on first render)
  const hasInitialized = useRef(false);
  const [isReady, setIsReady] = useState(false);

  // Position/animate indicator when activeTab changes
  useLayoutEffect(() => {
    const indicator = indicatorRef.current;
    const activeButton = tabRefs.current.get(activeTab);

    if (!indicator || !activeButton) return;

    const targetLeft = activeButton.offsetLeft;
    const targetWidth = activeButton.offsetWidth;

    indicator.style.transform = `translateX(${targetLeft}px)`;
    indicator.style.width = `${targetWidth}px`;

    if (!hasInitialized.current) {
      hasInitialized.current = true;
      setIsReady(true);
    }
  }, [activeTab]);

  // Register tab button refs
  const registerTab = (id: TabId) => (el: HTMLButtonElement | null) => {
    if (el) {
      tabRefs.current.set(id, el);
    } else {
      tabRefs.current.delete(id);
    }
  };

  return (
    <div
      ref={containerRef}
      className="relative flex gap-1 p-1 rounded-lg bg-muted border border-border"
    >
      {/* Sliding indicator — positioned absolutely behind buttons */}
      <div
        ref={indicatorRef}
        className={cx(
          "absolute top-1 bottom-1 rounded-md",
          "bg-background shadow-sm",
          "pointer-events-none",
          "transition-[transform,width,opacity] duration-150 ease-out",
          // Start invisible until positioned (prevents flash)
          !isReady && "opacity-0"
        )}
        aria-hidden="true"
      />

      {/* Tab buttons — z-10 to sit above indicator */}
      {tabs.map((tab) => (
        <button
          key={tab.id}
          ref={registerTab(tab.id)}
          onClick={() => onTabChange(tab.id)}
          className={cx(
            // Layout
            "relative z-10 flex-1 px-3 py-1.5",
            // Typography
            "text-sm font-medium",
            // Shape (for focus ring)
            "rounded-md",
            // Transition for text color only (indicator handles background)
            "transition-colors duration-150",
            // Focus
            focusRing(),
            // Text color based on active state
            activeTab === tab.id
              ? "text-foreground"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}

export type { TabId };
