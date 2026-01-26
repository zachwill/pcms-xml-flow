import { useEffect, useState } from "react";

/**
 * useClientMediaQuery — Hydration-safe media query hook
 * 
 * Silk pattern: Returns false during SSR/hydration to ensure 
 * server/client HTML match, then updates on the client.
 */
export function useClientMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(query);
    
    // Set initial value
    if (media.matches !== matches) {
      setMatches(media.matches);
    }

    const listener = () => setMatches(media.matches);
    media.addEventListener("change", listener);
    
    return () => media.removeEventListener("change", listener);
  }, [query, matches]);

  return matches;
}
