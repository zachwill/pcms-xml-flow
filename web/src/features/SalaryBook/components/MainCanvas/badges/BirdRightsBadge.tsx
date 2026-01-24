import { cx } from "@/lib/utils";
import type { SalaryBookPlayer } from "../../../data";

/** Bird rights indicator (text-only; shown under salaries) */
export function BirdRightsBadge({
  birdRights,
}: {
  birdRights: SalaryBookPlayer["bird_rights"];
}) {
  if (!birdRights) return null;

  const labels = {
    BIRD: "Bird",
    EARLY_BIRD: "E-Bird",
    NON_BIRD: "Non-Bird",
  };

  return (
    <span
      className={cx(
        "inline-flex items-center",
        // text-only (no pill background)
        "text-teal-700 dark:text-teal-300",
        "text-[9px] font-medium",
        "leading-none"
      )}
    >
      {labels[birdRights]}
    </span>
  );
}
