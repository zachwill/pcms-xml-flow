/**
 * FilterToggles — Filter controls for Display, Financials, and Contracts
 *
 * Three columns of checkbox groups that shape table content without
 * changing navigation state. Connected to useFilterState via context.
 *
 * Per spec:
 * - Display: Cap Holds, Exceptions, Draft Picks, Dead Money
 * - Financials: Tax/Aprons, Cash vs Cap, Luxury Tax
 * - Contracts: Options, Incentives, Two-Way
 */

import { cx, focusRing } from "@/lib/utils";
import { Checkbox } from "@/components/ui";
import { useFilters, FILTER_METADATA, type FilterState, type FilterKey } from "@/state/filters";

/**
 * Group header labels
 */
const GROUP_LABELS: Record<keyof FilterState, string> = {
  display: "Display",
  financials: "Financials",
  contracts: "Contracts",
};

/**
 * Single filter checkbox with label
 */
interface FilterCheckboxProps {
  group: keyof FilterState;
  filterKey: FilterKey;
  label: string;
  checked: boolean;
  onChange: () => void;
}

function FilterCheckbox({
  group,
  filterKey,
  label,
  checked,
  onChange,
}: FilterCheckboxProps) {
  const id = `filter-${group}-${filterKey}`;

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

/**
 * Filter group column with header and checkboxes
 */
interface FilterGroupProps {
  group: keyof FilterState;
  label: string;
}

function FilterGroup({ group, label }: FilterGroupProps) {
  const { isFilterActive, toggleFilter } = useFilters();
  const filters = FILTER_METADATA[group];

  return (
    <div className="space-y-1">
      {/* Group header */}
      <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
        {label}
      </div>

      {/* Filter checkboxes */}
      <div className="space-y-1">
        {filters.map((filter) => (
          <FilterCheckbox
            key={filter.key}
            group={group}
            filterKey={filter.key}
            label={filter.label}
            checked={isFilterActive(group, filter.key)}
            onChange={() => toggleFilter(group, filter.key)}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * FilterToggles — Main export
 *
 * Three-column layout of filter groups that control table content visibility.
 * Filters do NOT affect sidebar state or navigation.
 */
export function FilterToggles() {
  return (
    <div
      className={cx(
        // Three-column grid layout
        "grid grid-cols-3 gap-4",
        // Constrain width
        "max-w-sm"
      )}
    >
      {(Object.keys(GROUP_LABELS) as Array<keyof FilterState>).map((group) => (
        <FilterGroup key={group} group={group} label={GROUP_LABELS[group]} />
      ))}
    </div>
  );
}
