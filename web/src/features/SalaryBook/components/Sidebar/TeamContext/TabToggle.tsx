import { cx, focusRing } from "@/lib/utils";

type TabId = "cap-outlook" | "team-stats";

/**
 * Tab toggle for switching between Cap Outlook and Team Stats
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

  return (
    <div className="flex gap-1 p-1 rounded-lg bg-muted/50">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          className={cx(
            "flex-1 px-3 py-1.5 text-sm font-medium rounded-md transition-all",
            focusRing(),
            activeTab === tab.id
              ? "bg-background text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground hover:bg-background/50"
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}

export type { TabId };
