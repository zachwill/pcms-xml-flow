import { cx } from "@/lib/utils";

/** Position chip (e.g., PG, SG, SF, PF, C) */
export function PositionChip({ position }: { position: string }) {
  return (
    <span
      className={cx(
        "inline-flex items-center justify-center",
        "px-1.5 py-0.5 rounded",
        "bg-muted text-muted-foreground",
        "text-[10px] font-medium uppercase tracking-wide",
        "min-w-[28px]"
      )}
    >
      {position}
    </span>
  );
}
