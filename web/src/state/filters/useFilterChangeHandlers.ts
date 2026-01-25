import { useEffect } from "react";
import { useFilters, type FilterChangeHandlers } from "./FilterProvider";

/**
 * Register "before/after" callbacks for filter changes.
 *
 * Used by the active view shell to preserve scroll position when toggling lenses.
 */
export function useRegisterFilterChangeHandlers(handlers: FilterChangeHandlers) {
  const { setChangeHandlers } = useFilters();

  useEffect(() => {
    setChangeHandlers(handlers);
    return () => setChangeHandlers(null);
  }, [setChangeHandlers, handlers]);
}
