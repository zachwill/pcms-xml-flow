import { cx } from "@/lib/utils";
import type { GuaranteeType } from "../../../data";

/** Guarantee type indicator (shown below salary) */
export function GuaranteeBadge({ guarantee }: { guarantee: GuaranteeType }) {
  if (!guarantee) return null;

  const labels: Record<NonNullable<GuaranteeType>, string> = {
    GTD: "GTD",
    PARTIAL: "PRT",
    "NON-GTD": "NG",
  };

  const colorClasses: Record<NonNullable<GuaranteeType>, string> = {
    GTD: "text-green-600 dark:text-green-400",
    PARTIAL: "text-yellow-600 dark:text-yellow-400",
    "NON-GTD": "text-red-500 dark:text-red-400",
  };

  return (
    <span
      className={cx("text-[9px] font-medium", colorClasses[guarantee])}
      title={
        guarantee === "GTD"
          ? "Fully Guaranteed"
          : guarantee === "PARTIAL"
            ? "Partially Guaranteed"
            : "Non-Guaranteed"
      }
    >
      {labels[guarantee]}
    </span>
  );
}
