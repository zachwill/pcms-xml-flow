import { useEffect, useState, useCallback } from "react";

/**
 * useVisualViewport — Tracks the visual viewport (critical for mobile keyboard)
 * 
 * Silk pattern: window.visualViewport provides the actual visible area
 * excluding the on-screen keyboard, which window.innerHeight does not.
 */
export interface VisualViewportData {
  width: number;
  height: number;
  offsetTop: number;
  offsetLeft: number;
  pageTop: number;
  pageLeft: number;
  scale: number;
}

export function useVisualViewport(): VisualViewportData | null {
  const [viewport, setViewport] = useState<VisualViewportData | null>(null);

  const updateViewport = useCallback(() => {
    const vv = window.visualViewport;
    if (!vv) return;

    setViewport({
      width: vv.width,
      height: vv.height,
      offsetTop: vv.offsetTop,
      offsetLeft: vv.offsetLeft,
      pageTop: vv.pageTop,
      pageLeft: vv.pageLeft,
      scale: vv.scale,
    });
  }, []);

  useEffect(() => {
    if (!window.visualViewport) return;

    const vv = window.visualViewport;
    updateViewport();

    vv.addEventListener("resize", updateViewport);
    vv.addEventListener("scroll", updateViewport);

    return () => {
      vv.removeEventListener("resize", updateViewport);
      vv.removeEventListener("scroll", updateViewport);
    };
  }, [updateViewport]);

  return viewport;
}
