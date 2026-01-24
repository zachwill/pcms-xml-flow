import { cx } from "@/lib/utils";
import type { ContractOption } from "../../../data";

/** Contract option indicator (PO, TO, ETO) — pill badge style */
export function OptionBadge({ option }: { option: ContractOption }) {
  if (!option) return null;

  const colorClasses = {
    PO: "bg-blue-100 text-blue-700 dark:bg-blue-900/50 dark:text-blue-300",
    TO: "bg-purple-100 text-purple-700 dark:bg-purple-900/50 dark:text-purple-300",
    ETO: "bg-orange-100 text-orange-700 dark:bg-orange-900/50 dark:text-orange-300",
  };

  return (
    <span
      className={cx(
        "inline-flex items-center",
        "px-1.5 py-0.5 rounded-full",
        "text-[9px] font-semibold uppercase tracking-wide",
        "leading-none",
        colorClasses[option]
      )}
      title={
        option === "PO"
          ? "Player Option"
          : option === "TO"
            ? "Team Option"
            : "Early Termination Option"
      }
    >
      {option}
    </span>
  );
}
