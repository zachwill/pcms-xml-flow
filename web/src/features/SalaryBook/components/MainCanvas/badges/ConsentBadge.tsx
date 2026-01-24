import { cx } from "@/lib/utils";

/** Consent indicator (shown under current season if trade consent required) — pill badge style */
export function ConsentBadge() {
  return (
    <span
      className={cx(
        "inline-flex items-center",
        "px-1.5 py-0.5 rounded-full",
        "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300",
        "text-[9px] font-semibold uppercase tracking-wide",
        "leading-none"
      )}
      title="Player consent required"
    >
      Consent
    </span>
  );
}
