/**
 * ViewSelector — Placeholder view switcher for the app
 *
 * Per product direction: we currently default to the Salary Book view.
 * Other views are shown for future expansion but are not yet usable.
 */

import { cx } from "@/lib/utils";
import { APP_VIEWS, type ViewKey } from "@/config/views";

export function ViewSelector() {
  // Hard-coded for now; will become router/state driven later.
  const activeView: ViewKey = "salary-book";

  return (
    <div className="space-y-1">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
        View
      </div>

      <div className="flex flex-col gap-1">
        {APP_VIEWS.map((view) => {
          const isActive = view.key === activeView;
          const isDisabled = !view.enabled;

          return (
            <div
              key={view.key}
              aria-current={isActive ? "page" : undefined}
              className={cx(
                "text-left text-[11px] leading-none select-none",
                // Match checkbox label sizing/alignment a bit
                "px-0 py-0.5",
                isActive && "font-semibold text-foreground",
                !isActive && !isDisabled && "text-foreground/80",
                isDisabled && "text-muted-foreground/40"
              )}
            >
              {view.label}
            </div>
          );
        })}
      </div>
    </div>
  );
}
