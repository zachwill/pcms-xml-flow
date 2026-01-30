/**
 * FilterToggles — Command bar filter controls
 *
 * Today we expose two controls:
 * - Display: checkbox filters that shape the Salary Book table
 * - Rows: a placeholder "row source" selector (only Salary is active for now)
 */

import { useState } from "react";

import { cx, focusRing } from "@/lib/utils";
import { Checkbox, Radio, RadioGroup } from "@/components/ui";
import {
  FILTER_METADATA,
  useFilters,
  type DisplayFilter,
} from "@/state/filters";

/**
 * Single filter checkbox with label
 */
interface FilterCheckboxProps {
  filterKey: DisplayFilter;
  label: string;
  checked: boolean;
  onChange: () => void;
}

function FilterCheckbox({ filterKey, label, checked, onChange }: FilterCheckboxProps) {
  const id = `filter-display-${filterKey}`;

  return (
    <div className="flex items-center gap-1.5">
      <Checkbox
        id={id}
        checked={checked}
        onCheckedChange={onChange}
        className={cx("size-3.5", focusRing())}
      />
      <label
        htmlFor={id}
        className={cx(
          "text-[11px] leading-none cursor-pointer select-none",
          "text-foreground/80 hover:text-foreground transition-colors"
        )}
      >
        {label}
      </label>
    </div>
  );
}

function DisplayGroup() {
  const { isFilterActive, toggleFilter } = useFilters();
  const filters = FILTER_METADATA.display;

  return (
    <div className="space-y-1">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
        Display
      </div>

      <div className="space-y-1">
        {filters.map((filter) => (
          <FilterCheckbox
            key={filter.key}
            filterKey={filter.key as DisplayFilter}
            label={filter.label}
            checked={isFilterActive("display", filter.key)}
            onChange={() => toggleFilter("display", filter.key)}
          />
        ))}
      </div>
    </div>
  );
}

type RowsMode = "ctg" | "epm" | "salary";

const ROWS_OPTIONS: Array<{ value: RowsMode; label: string; disabled?: boolean }> = [
  { value: "ctg", label: "CTG", disabled: true },
  { value: "epm", label: "EPM", disabled: true },
  { value: "salary", label: "Salaries" },
];

interface RowsRadioProps {
  value: RowsMode;
  label: string;
  disabled?: boolean;
}

function RowsRadio({ value, label, disabled }: RowsRadioProps) {
  return (
    <label
      className={cx(
        "flex items-center gap-1.5 select-none",
        disabled ? "cursor-not-allowed opacity-50" : "cursor-pointer"
      )}
    >
      <Radio value={value} disabled={disabled} size="sm" />
      <span
        className={cx(
          "text-[11px] leading-none",
          disabled
            ? "text-muted-foreground/80"
            : "text-foreground/80 hover:text-foreground transition-colors"
        )}
      >
        {label}
      </span>
    </label>
  );
}

function RowsGroup() {
  const [rowsMode, setRowsMode] = useState<RowsMode>("salary");

  return (
    <div className="space-y-1">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
        Rows
      </div>

      <RadioGroup
        value={rowsMode}
        onValueChange={(v) => setRowsMode(v as RowsMode)}
        orientation="vertical"
        className="gap-1"
      >
        {ROWS_OPTIONS.map((opt) => (
          <RowsRadio
            key={opt.value}
            value={opt.value}
            label={opt.label}
            disabled={opt.disabled}
          />
        ))}
      </RadioGroup>
    </div>
  );
}

/**
 * FilterToggles — Main export
 */
export function FilterToggles() {
  return (
    <div className="flex items-start gap-4">
      <div className="min-w-[4.5rem]">
        <DisplayGroup />
      </div>
      <div className="min-w-[4.5rem]">
        <RowsGroup />
      </div>
    </div>
  );
}
