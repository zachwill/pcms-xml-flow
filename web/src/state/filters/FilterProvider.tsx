import React, {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import {
  DEFAULT_FILTER_STATE,
  type FilterKey,
  type FilterState,
} from "./types";

export interface FilterChangeHandlers {
  onBeforeChange?: () => void;
  onAfterChange?: () => void;
}

interface FiltersContextValue {
  filters: FilterState;
  toggleFilter: (group: keyof FilterState, key: FilterKey) => void;
  isFilterActive: (group: keyof FilterState, key: FilterKey) => boolean;
  resetFilters: () => void;
  setGroupFilters: (group: keyof FilterState, value: boolean) => void;

  /**
   * Allows the currently-mounted view shell to register scroll preservation handlers.
   *
   * This is intentionally a single "active" handler set (last writer wins).
   */
  setChangeHandlers: (handlers: FilterChangeHandlers | null) => void;
}

const FiltersContext = createContext<FiltersContextValue | null>(null);

export function useFilters() {
  const ctx = useContext(FiltersContext);
  if (!ctx) throw new Error("useFilters must be used within <FilterProvider>");
  return ctx;
}

export function FilterProvider({ children }: { children: ReactNode }) {
  const [filters, setFilters] = useState<FilterState>(DEFAULT_FILTER_STATE);
  const changeHandlersRef = useRef<FilterChangeHandlers | null>(null);

  const setChangeHandlers = useCallback((handlers: FilterChangeHandlers | null) => {
    changeHandlersRef.current = handlers;
  }, []);

  const scheduleAfterChange = useCallback(() => {
    const onAfterChange = changeHandlersRef.current?.onAfterChange;
    if (!onAfterChange) return;

    // Double-RAF to ensure DOM is committed.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        onAfterChange();
      });
    });
  }, []);

  const toggleFilter = useCallback(
    (group: keyof FilterState, key: FilterKey) => {
      changeHandlersRef.current?.onBeforeChange?.();

      setFilters((prev) => ({
        ...prev,
        [group]: {
          ...prev[group],
          [key]: !prev[group][key as keyof typeof prev[typeof group]],
        },
      }));

      scheduleAfterChange();
    },
    [scheduleAfterChange]
  );

  const isFilterActive = useCallback(
    (group: keyof FilterState, key: FilterKey): boolean => {
      return filters[group][key as keyof typeof filters[typeof group]] ?? false;
    },
    [filters]
  );

  const resetFilters = useCallback(() => {
    changeHandlersRef.current?.onBeforeChange?.();
    setFilters(DEFAULT_FILTER_STATE);
    scheduleAfterChange();
  }, [scheduleAfterChange]);

  const setGroupFilters = useCallback(
    (group: keyof FilterState, value: boolean) => {
      changeHandlersRef.current?.onBeforeChange?.();

      setFilters((prev) => {
        const groupFilters = prev[group];
        const newGroupFilters = Object.keys(groupFilters).reduce(
          (acc, k) => ({ ...acc, [k]: value }),
          {} as typeof groupFilters
        );
        return {
          ...prev,
          [group]: newGroupFilters,
        };
      });

      scheduleAfterChange();
    },
    [scheduleAfterChange]
  );

  const value = useMemo<FiltersContextValue>(
    () => ({
      filters,
      toggleFilter,
      isFilterActive,
      resetFilters,
      setGroupFilters,
      setChangeHandlers,
    }),
    [filters, toggleFilter, isFilterActive, resetFilters, setGroupFilters, setChangeHandlers]
  );

  return <FiltersContext.Provider value={value}>{children}</FiltersContext.Provider>;
}
