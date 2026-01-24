import { cx } from "@/lib/utils";

/** Two-way badge for salary columns (sized to match salary amounts) */
export function TwoWaySalaryBadge() {
  return (
    <span
      className={cx(
        "inline-flex items-center justify-center",
        "text-[10px] px-1.5 py-0.5 rounded",
        "bg-amber-100 dark:bg-amber-900/50",
        "text-amber-700 dark:text-amber-300",
        "font-medium"
      )}
    >
      Two-Way
    </span>
  );
}
