import { useEffect, useRef, useCallback } from "react";

/**
 * useTransformCompensation — Keeps an element visually "fixed" when an ancestor transforms
 * 
 * Silk pattern: If an ancestor is being transformed (e.g. during a transition),
 * this hook applies an inverse transform to the target element so it appears
 * stationary relative to the viewport.
 * 
 * @param containerRef - The element that is being transformed
 * @param targetRef - The element that should stay fixed
 */
export function useTransformCompensation(
  containerRef: React.RefObject<HTMLElement | null>,
  targetRef: React.RefObject<HTMLElement | null>
) {
  const rafRef = useRef<number | null>(null);

  const sync = useCallback(() => {
    const container = containerRef.current;
    const target = targetRef.current;

    if (!container || !target) return;

    // Get the current computed transform of the container
    const style = window.getComputedStyle(container);
    const transform = style.transform;

    if (transform && transform !== "none") {
      // Invert the transform matrix
      // For simple 2D translations, we can just parse the matrix
      // matrix(a, b, c, d, tx, ty)
      const parts = transform.match(/matrix\((.+)\)/);
      if (parts && parts[1]) {
        const matrix = parts[1].split(", ").map(Number);
        if (matrix.length === 6) {
          const [a, b, c, d, tx, ty] = matrix as [
            number,
            number,
            number,
            number,
            number,
            number,
          ];

          // Apply inverse transform to target.
          // Using translate3d(0,0,0) as base to ensure layer promotion.
          if (a !== 0 && d !== 0) {
            target.style.transform = `matrix(${1 / a}, ${-b}, ${-c}, ${1 / d}, ${-tx}, ${-ty})`;
          } else {
            target.style.transform = "";
          }
        }
      }
    } else {
      target.style.transform = "";
    }

    rafRef.current = requestAnimationFrame(sync);
  }, [containerRef, targetRef]);

  useEffect(() => {
    rafRef.current = requestAnimationFrame(sync);
    return () => {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [sync]);
}
