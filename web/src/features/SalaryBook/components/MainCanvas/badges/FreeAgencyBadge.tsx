import { cx } from "@/lib/utils";
import type { SalaryBookPlayer } from "../../../data";

/** Free agency type + year indicator (text-only; shown under salaries) */
export function FreeAgencyBadge({
  type,
  year,
}: {
  type: SalaryBookPlayer["free_agency_type"];
  year: number | null;
}) {
  if (!type || !year) return null;

  return (
    <span
      className={cx(
        "inline-flex items-center",
        // text-only (no pill background)
        type === "UFA"
          ? "text-red-700 dark:text-red-300"
          : "text-sky-700 dark:text-sky-300",
        "text-[9px] font-medium",
        "leading-none"
      )}
      title={type === "UFA" ? "Unrestricted Free Agent" : "Restricted Free Agent"}
    >
      {type} {year.toString().slice(-2)}
    </span>
  );
}
