import React from "react";
import { cx } from "@/lib/utils";

/**
 * PlayerSalary
 *
 * Renders a salary value in a table-friendly way:
 * - The *cell* can be centered as a column
 * - The salary text itself is right-aligned within a fixed-width slot
 *   so values like "$25.3M" line up with "$4.8M".
 */

export interface PlayerSalaryProps {
  /** Salary amount in raw dollars (e.g. 11_000_000) */
  amount: number | null;
  /** Render a two-way badge instead of a number */
  showTwoWayBadge?: boolean;
  /** Width of the numeric slot (default 6ch, use 7ch for totals) */
  slotWidth?: string;
  className?: string;
}

function TwoWaySalaryBadge() {
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

function formatSalary(amount: number | null): string {
  if (amount === null) return "—";
  if (amount === 0) return "$0K";

  const millions = amount / 1_000_000;
  if (millions >= 1) return `$${millions.toFixed(1)}M`;

  const thousands = amount / 1_000;
  return `$${Math.round(thousands)}K`;
}

export function PlayerSalary({
  amount,
  showTwoWayBadge = false,
  slotWidth = "6ch",
  className,
}: PlayerSalaryProps) {
  if (showTwoWayBadge) {
    return (
      <span className={cx("grid place-items-center", className)}>
        <TwoWaySalaryBadge />
      </span>
    );
  }

  const label = formatSalary(amount);
  const isEmpty = amount === null;

  return (
    // Outer wrapper: takes full cell width so the *slot* can be centered reliably.
    <span className={cx("grid place-items-center w-full", className)}>
      {/* Inner slot: configurable width + right aligned for numeric alignment */}
      <span
        className={cx(
          "inline-block font-mono tabular-nums",
          isEmpty ? "text-center text-gray-400/50" : "text-right"
        )}
        style={{ width: slotWidth }}
      >
        {label}
      </span>
    </span>
  );
}
