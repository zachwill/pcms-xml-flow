export type ViewKey = "free-agents" | "salary-book" | "system-values" | "tankathon";

export interface AppView {
  key: ViewKey;
  label: string;
  enabled: boolean;
}

// Placeholder registry. Only Salary Book is implemented today.
export const APP_VIEWS: AppView[] = [
  { key: "free-agents", label: "Free Agents", enabled: false },
  { key: "salary-book", label: "Salary Book", enabled: true },
  { key: "system-values", label: "System Values", enabled: false },
  { key: "tankathon", label: "Tankathon", enabled: false },
];
