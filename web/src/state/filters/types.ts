/**
 * Global filter types + defaults
 *
 * Filters are "lenses, not navigation" (see web/specs/00-ui-philosophy.md).
 * Today these filters primarily shape the Salary Book table, but they live
 * at the app level so additional views can reuse or override them over time.
 */

/** Display filter keys */
export type DisplayFilter = "capHolds" | "exceptions" | "draftPicks" | "deadMoney";

/** Financials filter keys */
export type FinancialsFilter = "taxAprons" | "cashVsCap" | "luxuryTax";

/** Contracts filter keys */
export type ContractsFilter = "options" | "incentives" | "twoWay";

/** All possible filter keys */
export type FilterKey = DisplayFilter | FinancialsFilter | ContractsFilter;

/** Filter state by group */
export interface FilterState {
  display: Record<DisplayFilter, boolean>;
  financials: Record<FinancialsFilter, boolean>;
  contracts: Record<ContractsFilter, boolean>;
}

/**
 * Default filter state (matches current spec defaults)
 * Display: Cap Holds ✗, Exceptions ✓, Draft Picks ✓, Dead Money ✗
 * Financials: Tax/Aprons ✓, Cash vs Cap ✗, Luxury Tax ✗
 * Contracts: Options ✓, Incentives ✓, Two-Way ✓
 */
export const DEFAULT_FILTER_STATE: FilterState = {
  display: {
    capHolds: false,
    exceptions: true,
    draftPicks: true,
    deadMoney: false,
  },
  financials: {
    taxAprons: true,
    cashVsCap: false,
    luxuryTax: false,
  },
  contracts: {
    options: true,
    incentives: true,
    twoWay: true,
  },
};

/** Filter metadata for rendering */
export interface FilterMeta {
  key: FilterKey;
  label: string;
  group: keyof FilterState;
}

/** Filter metadata organized by group */
export const FILTER_METADATA: Record<keyof FilterState, FilterMeta[]> = {
  display: [
    { key: "capHolds", label: "Cap Holds", group: "display" },
    { key: "exceptions", label: "Exceptions", group: "display" },
    { key: "draftPicks", label: "Draft Picks", group: "display" },
    { key: "deadMoney", label: "Dead Money", group: "display" },
  ],
  financials: [
    { key: "taxAprons", label: "Tax/Aprons", group: "financials" },
    { key: "cashVsCap", label: "Cash vs Cap", group: "financials" },
    { key: "luxuryTax", label: "Luxury Tax", group: "financials" },
  ],
  contracts: [
    { key: "options", label: "Options", group: "contracts" },
    { key: "incentives", label: "Incentives", group: "contracts" },
    { key: "twoWay", label: "Two-Way", group: "contracts" },
  ],
};
