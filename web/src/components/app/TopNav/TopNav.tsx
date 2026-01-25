/**
 * TopNav — Fixed navigation + filter header
 *
 * Composes:
 * - TeamSelectorGrid: 30-team navigation grid with scroll-spy highlight
 * - FilterToggles: global "lens" checkboxes
 * - ViewSelector: placeholder view list (Salary Book is the only active view today)
 *
 * Positioned fixed at viewport top with highest z-index.
 * Height: 130px (main content area is offset by this height)
 */

import { cx } from "@/lib/utils";
import { FilterToggles } from "./FilterToggles";
import { TeamSelectorGrid } from "./TeamSelectorGrid";
import { ViewSelector } from "./ViewSelector";

/**
 * TopNav — Main export
 */
export function TopNav() {
  return (
    <div
      className={cx(
        // Fixed positioning at viewport top
        "fixed top-0 left-0 right-0 z-50",
        // Height matches the topOffset in SalaryBookProvider
        "h-[130px]",
        // Border
        "border-b border-border",
        // Layout - items aligned to start, not spread apart
        "flex items-start px-4 pt-3 gap-6"
      )}
      style={{ backgroundColor: "var(--background, #fff)" }}
    >
      {/* Team Selector Grid */}
      <TeamSelectorGrid />

      {/* Vertical divider */}
      <div className="h-20 w-px bg-border self-center" />

      {/* Filters: positioned next to teams */}
      <FilterToggles />

      {/* Vertical divider */}
      <div className="h-20 w-px bg-border self-center" />

      {/* Views: placeholder (Salary Book is the only active view right now) */}
      <ViewSelector />
    </div>
  );
}
